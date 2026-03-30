# buddy-hardened-terraform-modules

Standardized Terraform modules for Buddy application repos.

## Modules

### `modules/ecr-repository`

Creates an app-owned ECR repository with:

- scan on push
- optional immutability
- configurable encryption (`AES256` or `KMS`)
- lifecycle policy for tagged image retention

### `modules/ecs-app`

Creates a standardized ECS Fargate service with:

- task execution role and log group
- service-level security group
- rolling deployments with circuit breaker
- optional Cloudflare Tunnel sidecar (`cloudflared`) using Secrets Manager token

## Standard Composition Pattern

App repos should compose both modules in the same deploy root:

1. Create app-owned ECR via `modules/ecr-repository`
2. Deploy app service via `modules/ecs-app`
3. Read shared network/cluster state from `buddy-shared-infrastructure`

See `examples/ecs-ecr-app` for a reference root module.

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
