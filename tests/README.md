# Integration tests

Real-AWS integration tests for the modules in this repo. **Tests run against a real AWS account; the harness uses a bash `trap` to guarantee `terraform destroy` runs even on failure or interrupt.**

## What's tested

| Test | What it exercises |
| --- | --- |
| `tests/integration/main.tf` | All v0.3.0 `ecs-app` additions except ALB attach (Service Connect, SG-to-SG ingress, SSM secrets, autoscaling resources, capacity provider mix, default alarms). ALB-related inputs (`target_group_arn` + 3 ALB-derived alarms) get exercised by the first real consumer of the shared ALB once `BUD-11` lands. |

## Running

```bash
export AWS_PROFILE=buddy-athletics
./scripts/test-integration.sh
```

The script:
1. `terraform init` in `tests/integration/`
2. `terraform apply -auto-approve` (creates ~12 throwaway resources — Cloud Map namespace, peer SG, SSM SecureString, ECR repo, ECS service, IAM role, log group, autoscaling target+policy, 3 alarms, security group with peer-SG ingress)
3. Asserts on Terraform outputs + AWS API state (service name, autoscaling resource id, alarm count + names, IAM policy attachment, Service Connect namespace, SG ingress rule)
4. **Trap-guaranteed `terraform destroy -auto-approve`** — fires on EXIT, INT, TERM. Even Ctrl-C runs destroy before the script terminates.

## Why a bash trap, not `terraform test`

`terraform test` plus `run` blocks with `module {}` overrides triggers a known plugin-startup-timeout bug in Terraform 1.14.x on macOS — provider plugins fail to start on the second `run` block within a single test invocation. The bash-trap approach bypasses this entirely (one `terraform apply`, one provider lifecycle) while preserving the must-always-destroy guarantee.

If you're tempted to revert to `terraform test`: confirm the plugin lifecycle bug is fixed in your TF version first by running an existing tftest with two `run` blocks. As of TF 1.14.4 + macOS 14, it isn't.

## Cost

Less than $0.01 per run. ECS service has `desired_count = 0` so no Fargate task hours are billed. Alarms, log groups, SGs, SSM SecureString, ECR repo, IAM role, Cloud Map namespace are all near-free at this volume. Apply takes ~2 min, destroy ~1 min.

## Iteration discipline

Per project policy: **every test run ends with destroy. If the script reports anything other than "Destroy complete", investigate immediately.** The script also supports `SKIP_DESTROY=1 ./scripts/test-integration.sh` for active debugging — but that defeats the safety net and should NEVER be used in CI or as a default.

Verify nothing was left after a normal run:

```bash
aws ec2 describe-security-groups --filters 'Name=group-name,Values=ecs-app-test*' --query 'length(SecurityGroups)' --output text   # expect 0
aws ecs list-services --cluster buddy-athletics-dev-cluster --query 'serviceArns[?contains(@, `ecs-app-test`)] | length(@)' --output text   # expect 0
aws servicediscovery list-namespaces --query 'Namespaces[?contains(Name,`ecs-app-test`)] | length(@)' --output text   # expect 0
aws ssm describe-parameters --query 'Parameters[?contains(Name,`ecs-app-test`)] | length(@)' --output text   # expect 0
```

## Adding a new test scenario

1. Either extend `tests/integration/main.tf` with new resources/assertions, or copy the directory to `tests/integration-<name>/` and write a parallel script.
2. Pick a unique `TEST_RUN_ID` if running scenarios in parallel — resource names collide otherwise.
3. Run locally before merging module changes — CI only validates terraform syntax, not behavior.

## CI integration (future)

`scripts/test-integration.sh` is not yet wired into GitHub Actions because the repo lacks an OIDC trust to assume an AWS role from CI. When that's set up:

```yaml
integration-test:
  needs: validate
  runs-on: ubuntu-latest
  permissions:
    id-token: write
    contents: read
  steps:
    - uses: actions/checkout@v4
    - uses: aws-actions/configure-aws-credentials@v6
      with:
        role-to-assume: arn:aws:iam::643025068953:role/<integration-test-role>
        aws-region: us-east-1
    - uses: hashicorp/setup-terraform@v3
      with: { terraform_version: 1.9.0 }
    - run: ./scripts/test-integration.sh
```

For now: run locally before merging.
