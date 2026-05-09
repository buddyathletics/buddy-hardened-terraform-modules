# 0004 — `ecs-app` runtime shape: ALB attach, Service Connect, secrets, dual IAM roles

## Status
Accepted (v0.3.0 + v0.3.1)

## Context
The original `ecs-app` module shipped a Fargate service with a single IAM role (the **execution role**, used by ECS itself to pull images and write logs) and no first-class hooks for either ALB attachment or sibling-service traffic. Apps that needed any of those wired the resources outside the module — fragmenting the hardening contract across consumer repos.

Two consumer scenarios drove the v0.3.x runtime extensions:

1. **Public frontend + private API in one VPC.** The frontend has to register against a shared ALB target group; the API must remain unreachable from the public internet but accessible to the frontend. Both services need to coordinate through an internal discovery layer.
2. **Application code that calls AWS APIs at runtime.** Reading an S3 object, writing to DynamoDB, publishing to SQS — these need IAM credentials assumed by the *application*, not by ECS infrastructure. Conflating runtime perms with execution perms over-grants both directions.

## Decision

The module owns five additive surfaces, each opt-in via a default-null input so existing consumers see no plan diff:

| Surface | Inputs | Behavior when unset |
|---|---|---|
| **ALB attachment** | `target_group_arn`, `health_check_grace_period_seconds` | Service has no `load_balancer` block — internal-only |
| **ECS Service Connect** | `service_connect_namespace_arn`, `service_connect_port_alias` | Service is not in any mesh; setting only the namespace puts the service in client-only mode (joins the mesh, no published alias) |
| **SG-to-SG ingress** | `ingress_security_group_ids` | Service SG accepts no peer-SG ingress; CIDR ingress only |
| **Secrets injection** | `secrets` (map of env-var → SSM/Secrets Manager ARN) | No `secrets` block on the container; execution-role IAM is not extended |
| **Dual IAM roles** (v0.3.1) | `task_role_policy_json` | Task role exists with no inline policy — apps that don't call AWS at runtime pay nothing |

### Why two roles, not one
ECS distinguishes:

- **Execution role** (`execution_role_arn` on the task definition) — used by ECS itself to pull the image from ECR, fetch SSM/Secrets Manager values, and ship logs to CloudWatch. The module auto-extends this with `ssm:GetParameters` + `kms:Decrypt` on exactly the ARNs in `var.secrets`.
- **Task role** (`task_role_arn` on the task definition) — assumed by the running application code via the ECS task metadata endpoint. Used for runtime AWS SDK calls (S3, DynamoDB, SNS, Bedrock, etc.).

Conflating them means either the app has overly broad permissions (handed everything ECS needs to start) or ECS has overly broad permissions (handed everything the app needs to operate). The v0.3.1 task role is always created, so `var.task_role_policy_json` can be added in a later apply without forcing a task-definition recreate — and apps that genuinely don't need runtime AWS access leave it empty and pay nothing.

### Why isolation lives in security groups, not Service Connect
Service Connect is a discovery + load-balancing layer (Cloud Map + Envoy sidecars). It does **not** open ports. The reachability contract for `frontend → api` private traffic is enforced entirely by:

1. API service has `target_group_arn = null` → no ALB rule can forward to it
2. API SG accepts ingress on `container_port` only from `[frontend.security_group_id]`
3. No public DNS exists for the API hostname

Service Connect just makes `api:8006` resolve cleanly inside the namespace so the frontend's nginx can `proxy_pass` without templating IPs. Removing Service Connect would not weaken the isolation; it would only break ergonomics.

## Consequences
- New consumers compose the canonical "hardened public frontend + private API" pattern entirely from module inputs (see `examples/ecs-ecr-app`), with no per-app hardening to maintain.
- Existing v0.2.x consumers see no plan diff after upgrading the `?ref=` pin: every new input defaults to a no-op shape.
- IAM is least-privilege by default at both layers: execution role gets only what ECS needs (plus targeted SSM ARNs); task role gets nothing until a consumer supplies `task_role_policy_json`.
- The `assign_public_ip` default remains `true` for v0.3.x to preserve backwards compatibility with the current shared-infra public-subnet posture. Flipping it to `false` (private-subnet-first) is a deliberate breaking change deferred to v0.4.0, behind its own migration note.

## Out of scope (intentionally)
- **Cross-account secrets / KMS keys** — the auto-extended `kms:Decrypt` is granted only on `alias/aws/ssm`. Apps using customer-managed keys must extend the execution role themselves.
- **NLB attachment** — the `load_balancer` block currently assumes ALB semantics (HTTP target group, container port). NLB support would need a separate input shape.
- **Spot interruption handling** — `capacity_provider_strategy` is exposed but the module does not configure interruption notice handlers; consumer responsibility.
