# buddy-hardened-terraform-modules

Standardized Terraform modules for Buddy application repos.

## Modules

### `modules/ecr-repository`

Creates an app-owned ECR repository with:

- scan on push
- optional immutability
- configurable encryption (`AES256` or `KMS`)
- lifecycle policy profiles:
  - `count` (default)
  - `dev_short` (7-day tagged cleanup + 1-day untagged cleanup defaults)

### `modules/ecs-app`

Creates a standardized ECS Fargate service with:

- task execution role and log group
- task runtime role with optional inline policy injection
- service-level security group
- rolling deployments with circuit breaker
- optional ALB/NLB target group registration
- optional Cloudflare Tunnel sidecar (`cloudflared`) using Secrets Manager token

## Standard Composition Pattern

App repos should compose both modules in the same deploy root:

1. Create `app-dev` ECR with mutable tags and short retention.
2. Create `app-prod` ECR with immutable tags and conservative retention.
3. Deploy app service via `modules/ecs-app`, selecting ECR repo by environment.
4. Read shared network/cluster state from `buddy-shared-infrastructure`.

See `examples/ecs-ecr-app` for a reference root module.

## Release Promotion Contract

- Dev and main builds publish to the app's `-dev` repository using SHA tags.
- Semver releases (`vX.Y.Z`) promote the already-built digest from `-dev` to `-prod`.
- Prod ECS deploys reference only semver tags from `-prod` repository.

## Versioning

Release module changes with semantic version tags (for example `v0.1.0`).
App repos should pin module sources to explicit tags.

## CI Validation

Workflow: `.github/workflows/terraform-modules-ci.yml`

- Runs `terraform fmt -check -recursive`
- Runs `terraform init -backend=false -upgrade` and `terraform validate` for:
  - `modules/ecr-repository`
  - `modules/ecs-app`
  - `examples/ecs-ecr-app`
