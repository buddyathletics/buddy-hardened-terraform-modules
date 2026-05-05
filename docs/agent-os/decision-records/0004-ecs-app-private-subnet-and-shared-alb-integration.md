# 0004 - ECS App Private Subnet and Shared ALB Integration

## Status
Accepted

## Decision
- Extend `modules/ecs-app` to support optional ALB/NLB target group registration via `target_group_arn`.
- Add optional `health_check_grace_period_seconds` for load-balanced service stabilization.
- Add dedicated ECS task role with optional inline runtime policy (`task_role_policy_json`).
- Default `assign_public_ip` to `false` to align with private-subnet service deployment patterns.

## Consequences
- App repos can attach services to shared ALB listeners without forking module logic.
- Runtime IAM can be scoped separately from execution IAM.
- Private subnet deployment is the default behavior for new consumers.
- Existing consumers can preserve previous behavior by explicitly setting `assign_public_ip=true`.
