# Agent OS Docs

This repository provides reusable hardened Terraform modules for Buddy application repositories.

## CI/CD Composition Guidance
- Create two ECR repositories per app with `modules/ecr-repository`:
  - `<app>-dev` (mutable tags, short lifecycle retention)
  - `<app>-prod` (immutable release tags)
- Deploy ECS with `modules/ecs-app` using environment-selected repository URLs.
- `modules/ecs-app` supports private-subnet defaults, optional target group attachment, and optional task runtime IAM policy injection.
- Recommended release pattern:
  - build to `<app>-dev` as `sha-<commit>` and `dev-latest`
  - promote by digest into `<app>-prod` as `vX.Y.Z` (and mirrored `sha-<commit>`)
  - deploy prod using `image_tag=vX.Y.Z` only.
