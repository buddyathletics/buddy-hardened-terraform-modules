#!/usr/bin/env bash
# Integration-test harness for the modules in this repo.
#
# Runs `terraform apply` against a real AWS account, asserts the module's
# outputs/resources are correct, then ALWAYS runs `terraform destroy` —
# success, failure, or interrupt.
#
# The destroy is wired through a bash trap on EXIT/INT/TERM, so even if:
#   - assertions fail
#   - the apply hangs and the user Ctrl-Cs
#   - the script is killed by a parent process
# the destroy still fires before the script terminates.
#
# Usage:
#   AWS_PROFILE=buddy-athletics ./scripts/test-integration.sh
#
# Required environment:
#   AWS_PROFILE     — AWS profile with permission to manage ECS, IAM, SSM,
#                     CloudWatch, SecurityGroups, ECR, ServiceDiscovery.
# Optional:
#   TEST_RUN_ID     — suffix for resource names (default: "v030-lifecycle").
#                     Set to a unique value if running multiple iterations
#                     in parallel.
#   SKIP_DESTROY    — if "1", leaves resources standing for manual inspection.
#                     ONLY use when actively debugging — defeats the safety net.

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants — pulled from buddy-shared-infrastructure dev environment
# ---------------------------------------------------------------------------
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly TEST_RUN_ID="${TEST_RUN_ID:-v030-lifecycle}"
readonly VPC_ID="vpc-02c70e3658b562682"
readonly SUBNET_IDS='["subnet-0e977a967db4f3867","subnet-0704955d46cf78031"]'
readonly CLUSTER_ARN="arn:aws:ecs:us-east-1:643025068953:cluster/buddy-athletics-dev-cluster"

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_DIR="${REPO_ROOT}/tests/integration"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()   { printf '\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()    { printf '\033[1;32m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
fail()  { printf '\033[1;31m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ---------------------------------------------------------------------------
# Guaranteed-destroy trap. Fires on:
#   EXIT  — normal end (success OR failure)
#   INT   — Ctrl-C
#   TERM  — kill
# Idempotent: safe to fire multiple times.
# ---------------------------------------------------------------------------
DESTROY_RAN=0
destroy_resources() {
  if [[ "${DESTROY_RAN}" -eq 1 ]]; then
    return 0
  fi
  DESTROY_RAN=1

  if [[ "${SKIP_DESTROY:-0}" == "1" ]]; then
    fail "SKIP_DESTROY=1 — leaving resources standing. Run 'terraform -chdir=${TEST_DIR} destroy -auto-approve' manually when done."
    return 0
  fi

  log "Trap fired — running terraform destroy (this MUST complete to keep AWS bill clean)"

  # Retry destroy up to 5 times with backoff. The TF plugin is occasionally
  # slow to start on macOS (provider startup race), surfacing as
  # "timeout while waiting for plugin to start". A retry virtually always
  # succeeds because the plugin binary is now warm. Delays: 5s, 15s, 30s, 60s.
  #
  # Retries pass -lock=false because a previously-killed terraform may have
  # left a stale local-state flock that force-unlock can't clean (macOS-specific).
  local attempt=1
  local max_attempts=5
  local delay=5
  while (( attempt <= max_attempts )); do
    local lock_flag=""
    if (( attempt > 1 )); then
      lock_flag="-lock=false"
    fi

    if terraform -chdir="${TEST_DIR}" destroy -auto-approve ${lock_flag} \
        -var "test_run_id=${TEST_RUN_ID}" \
        -var "vpc_id=${VPC_ID}" \
        -var "subnet_ids=${SUBNET_IDS}" \
        -var "ecs_cluster_arn=${CLUSTER_ARN}"; then
      ok "Destroy complete (attempt ${attempt}/${max_attempts})"
      return 0
    fi

    if (( attempt < max_attempts )); then
      fail "Destroy attempt ${attempt}/${max_attempts} failed — retrying in ${delay}s"
      sleep "${delay}"
      delay=$(( delay * 2 ))
      attempt=$(( attempt + 1 ))
    else
      break
    fi
  done

  fail "Destroy failed after ${max_attempts} attempts — manually run:"
  fail "  terraform -chdir=${TEST_DIR} destroy -auto-approve \\"
  fail "    -var test_run_id=${TEST_RUN_ID} \\"
  fail "    -var vpc_id=${VPC_ID} \\"
  fail "    -var 'subnet_ids=${SUBNET_IDS}' \\"
  fail "    -var ecs_cluster_arn=${CLUSTER_ARN}"
  fail "Do NOT leave a failed-destroy un-investigated; AWS resources may still exist."
  return 1
}
trap destroy_resources EXIT INT TERM

# ---------------------------------------------------------------------------
# Step 1 — terraform init
# ---------------------------------------------------------------------------
log "Initializing test config in ${TEST_DIR}"
terraform -chdir="${TEST_DIR}" init -upgrade

# ---------------------------------------------------------------------------
# Step 2 — terraform apply
# ---------------------------------------------------------------------------
log "Applying test fixtures + module under test (apply takes ~2-3 min)"
terraform -chdir="${TEST_DIR}" apply -auto-approve \
  -var "test_run_id=${TEST_RUN_ID}" \
  -var "vpc_id=${VPC_ID}" \
  -var "subnet_ids=${SUBNET_IDS}" \
  -var "ecs_cluster_arn=${CLUSTER_ARN}"

# ---------------------------------------------------------------------------
# Step 3 — assertions on the module's outputs
#
# Uses jq + plain variables (NOT bash 4 associative arrays) so the script
# runs on macOS default bash 3.2.
# ---------------------------------------------------------------------------
log "Reading outputs"
get_output() {
  terraform -chdir="${TEST_DIR}" output -raw "$1"
}

readonly APP_NAME="$(get_output app_name)"
readonly ECS_SERVICE_NAME="$(get_output ecs_service_name)"
readonly AUTOSCALING_RESOURCE_ID="$(get_output appautoscaling_target_resource_id)"
readonly SERVICE_CONNECT_NS_ARN="$(get_output service_connect_namespace_arn)"
readonly PEER_SG_ID="$(get_output peer_security_group_id)"
readonly SERVICE_SG_ID="$(get_output security_group_id)"
log "App name: ${APP_NAME}"

# 1. ECS service named correctly
expected_service="${APP_NAME}-service"
if [[ "${ECS_SERVICE_NAME}" == "${expected_service}" ]]; then
  ok "ecs_service_name = ${ECS_SERVICE_NAME}"
else
  fail "Expected ECS service '${expected_service}', got '${ECS_SERVICE_NAME}'"
  exit 1
fi

# 2. Autoscaling target wired correctly
expected_resource_id="service/buddy-athletics-dev-cluster/${APP_NAME}-service"
if [[ "${AUTOSCALING_RESOURCE_ID}" == "${expected_resource_id}" ]]; then
  ok "appautoscaling_target_resource_id = ${AUTOSCALING_RESOURCE_ID}"
else
  fail "Expected autoscaling resource_id '${expected_resource_id}', got '${AUTOSCALING_RESOURCE_ID}'"
  exit 1
fi

# 3. Three default alarms rendered (ALB-derived 3 skipped because target_group_arn is null)
alarm_count="$(terraform -chdir="${TEST_DIR}" output -json alarm_names | jq 'length')"
if [[ "${alarm_count}" == "3" ]]; then
  ok "alarm_names has 3 entries (CPU, memory, task count) — ALB-derived alarms correctly skipped"
else
  fail "Expected 3 alarms, got ${alarm_count}"
  terraform -chdir="${TEST_DIR}" output alarm_names
  exit 1
fi

# 4. Specific alarm names
for expected in "${APP_NAME}-cpu-high" "${APP_NAME}-memory-high" "${APP_NAME}-task-count-low"; do
  if terraform -chdir="${TEST_DIR}" output -json alarm_names | jq -e --arg n "${expected}" 'index($n) != null' >/dev/null; then
    ok "Alarm present: ${expected}"
  else
    fail "Expected alarm '${expected}' not found in alarm_names"
    exit 1
  fi
done

# 5. Task execution role has the SSM policy granting ssm:GetParameters
role_name="${APP_NAME}-ecs-task-execution-role"
policy_name="${APP_NAME}-secrets-access"
if aws iam get-role-policy --role-name "${role_name}" --policy-name "${policy_name}" --output json 2>/dev/null \
    | jq -e '.PolicyDocument.Statement[] | select((.Action | type == "array") and (.Action | index("ssm:GetParameters")))' >/dev/null; then
  ok "Task execution role has ssm:GetParameters on test secret"
else
  fail "Task execution role missing ssm:GetParameters policy"
  aws iam get-role-policy --role-name "${role_name}" --policy-name "${policy_name}" --output json 2>&1 || true
  exit 1
fi

# 6. Service Connect namespace exists and is HTTP type
ns_id="$(awk -F/ '{print $NF}' <<<"${SERVICE_CONNECT_NS_ARN}")"
ns_type="$(aws servicediscovery get-namespace --id "${ns_id}" --query 'Namespace.Type' --output text 2>/dev/null || true)"
if [[ "${ns_type}" == "HTTP" ]]; then
  ok "Service Connect namespace exists (${ns_id}, type=HTTP)"
else
  fail "Service Connect namespace ${ns_id} missing or wrong type (got '${ns_type}')"
  exit 1
fi

# 7. Security group ingress rule from peer SG to service SG on container port
ingress_count="$(aws ec2 describe-security-groups --group-ids "${SERVICE_SG_ID}" \
  --query "SecurityGroups[0].IpPermissions[?contains(UserIdGroupPairs[].GroupId, '${PEER_SG_ID}')] | length(@)" \
  --output text 2>/dev/null || echo 0)"
if [[ "${ingress_count}" -ge 1 ]]; then
  ok "Service SG ingress rule from peer SG present"
else
  fail "Expected ingress on service SG (${SERVICE_SG_ID}) from peer SG (${PEER_SG_ID}); not found"
  exit 1
fi

ok "All assertions passed."
log "Trap will now run terraform destroy. Wait for it to finish before considering the test complete."

# Trap fires on EXIT — destroy runs automatically.
