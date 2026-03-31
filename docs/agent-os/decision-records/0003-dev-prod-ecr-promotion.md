# 0003 — Dev/Prod ECR Promotion Model

## Status
Accepted

## Context
Application repos need environment isolation for artifacts and deterministic prod releases without rebuilding images.

## Decision
- Standardize on two repositories per app: `<app>-dev` and `<app>-prod`.
- Use mutable tags + short retention profile for dev repositories.
- Use immutable tags for prod repositories.
- Promote by digest from dev to prod for semver releases (`vX.Y.Z`) rather than rebuilding.
- Standard app-repo tag contract:
  - dev repository: `sha-<commit>`, `dev-latest`
  - prod repository: `vX.Y.Z` and mirrored `sha-<commit>`
- Keep prod release versions human-controlled via explicit semver input (tag/release or manual release workflow).

## Consequences
- Prod artifacts are traceable to tested dev artifacts by digest.
- Rollbacks are simpler (redeploy prior semver tag from prod repo).
- Dev storage/scanning costs remain low with aggressive lifecycle cleanup.
