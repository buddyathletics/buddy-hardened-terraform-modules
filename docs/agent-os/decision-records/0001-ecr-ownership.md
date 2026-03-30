# 0001 - App-Owned ECR via Standard Module

## Status
Accepted

## Decision
Per-app ECR repositories are standardized in `buddy-hardened-terraform-modules/modules/ecr-repository` and consumed by app repos.

## Consequences
- Shared infrastructure repository does not own app artifact repositories.
- App repos can evolve ECR policy through module version upgrades.
