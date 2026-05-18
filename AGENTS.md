# AGENTS.md — how to work in this repo

Guidance for AI agents (Claude, Codex, Cursor, etc.) and humans contributing to `buddy-hardened-terraform-modules`. This file is **canonical** for repo conventions; if you're an agent and you skip something here, the PR will fail CI.

## 1. What this repo is

Reusable, hardened Terraform modules consumed by every Buddy app (admin, host, facility, user, future). Each module under `modules/` is independently versioned and consumed via `?ref=vX.Y.Z` git pins. **Backwards compatibility is non-negotiable**: a new module version must not introduce required inputs that break existing callers. Add inputs with sensible defaults instead.

Current modules:

- `modules/ecs-app/` — Hardened ECS Fargate service (ALB attach, Service Connect, SSM secrets, alarms, autoscaling, capacity provider mix).
- `modules/ecr-repository/` — Hardened ECR repository (lifecycle profiles `count`/`dev_short`, scan-on-push, configurable tag mutability and encryption).

`examples/ecs-ecr-app/` is the reference consumer wired through both modules and doubles as a CI contract test — it must validate without source changes after any module update.

## 2. Tech stack

| Tool | Version | Source of truth |
| --- | --- | --- |
| Terraform | `1.9.0` | `.github/workflows/terraform-modules-ci.yml` |
| AWS provider | `~> 5` | per-module `terraform.tf` |
| `terraform-docs` | latest | `.terraform-docs.yml` + `scripts/docs.sh` |
| `release-please` | `googleapis/release-please-action@v4` | `.github/workflows/release-please.yml` + `release-please-config.json` |

Local prereq: `AWS_PROFILE=buddy-athletics` for the integration test.

## 3. Repo layout

- `modules/ecs-app/` — hardened ECS Fargate service module.
- `modules/ecr-repository/` — hardened ECR repository module.
- `examples/ecs-ecr-app/` — reference consumer; contract test in the CI matrix.
- `tests/integration/` — real-AWS end-to-end test fixture for `ecs-app`.
- `scripts/docs.sh` — regenerates per-module READMEs via `terraform-docs`.
- `scripts/test-integration.sh` — apply + assert + must-always-destroy bash-trap runner.
- `docs/agent-os/` — decision records (ADRs) for this repo.
- `.github/workflows/` — `terraform-modules-ci`, `docs-check`, `integration-test`, `release-please`.
- `.github/pull_request_template.md` — required PR checklist.

## 4. Local setup

1. Install Terraform 1.9.0 (`tfenv install 1.9.0 && tfenv use 1.9.0`).
2. Install `terraform-docs` (https://terraform-docs.io) — required for `scripts/docs.sh`.
3. Configure AWS CLI: `aws configure --profile buddy-athletics`. The integration test reads `AWS_PROFILE=buddy-athletics` and resolves cluster/VPC/subnets from `buddy-shared-infrastructure` dev state.

No `.env` files in this repo. All inputs are flag- or env-var-driven.

## 5. Module dev runbook

This repo is a module library, not an app — there is no `npm run dev` equivalent. The "dev loop" is:

1. Edit a module under `modules/<name>/`.
2. Run `./scripts/docs.sh` if you changed `variables.tf`, `outputs.tf`, or resources (regenerates the auto-doc block in `modules/<name>/README.md`).
3. Run `terraform -chdir=modules/<name> init -backend=false -upgrade && terraform -chdir=modules/<name> validate`.
4. Run `AWS_PROFILE=buddy-athletics ./scripts/test-integration.sh` for any behavioral change.

To scaffold a **new** module, see §12 ("Adding a new module").

## 6. Required checks before opening / updating a PR

These are **all** required. The corresponding CI jobs will fail your PR if you skip any.

### 6.1 Format

```bash
terraform fmt -check -recursive
```

CI: `Terraform Modules CI / validate` runs this from the repo root.

### 6.2 Validate

```bash
for dir in modules/ecr-repository modules/ecs-app examples/ecs-ecr-app tests/integration; do
  terraform -chdir="$dir" init -backend=false -upgrade
  terraform -chdir="$dir" validate
done
```

CI: same job (note: `tests/integration` is validated locally but not in the CI matrix today — the matrix covers the first three dirs).

### 6.3 Module docs (terraform-docs)

**Mandatory** any time you touch a module's `variables.tf`, `outputs.tf`, or add/remove a resource. The auto-generated tables in each `modules/*/README.md` between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` must stay in sync with the source.

```bash
./scripts/docs.sh           # regenerate
./scripts/docs.sh --check   # CI mode — exits non-zero if stale
```

CI: `Module Docs Check / docs-check` runs `--check` on every PR that touches `modules/`, the config, or the script. The PR is blocked from merging if drift is detected.

> Hand-written content **above** the `BEGIN_TF_DOCS` marker stays under human authorship — usage examples, design rationale, upgrade notes. Don't let terraform-docs touch that.

### 6.4 Integration test

For module behavioral changes (anything beyond comment-only or doc-only edits in a module):

```bash
AWS_PROFILE=buddy-athletics ./scripts/test-integration.sh
```

This applies a real AWS test deploy of the module, runs 9 assertions on the resources/IAM/SC namespace/SG ingress, then **always destroys** via a bash trap on EXIT/INT/TERM with up to 5 retries on plugin-startup flake. Must report `Destroy complete` at the end. **If you see anything else, do not push — investigate the manual destroy command printed by the script.**

CI: `Integration Test / integration-test` is committed but currently gated behind `vars.RUN_INTEGRATION_TEST == 'true'` until OIDC trust is set up (see Linear BUD-86 and `tests/README.md`). Once enabled, it runs on every PR touching `modules/`, `examples/`, `scripts/`, or `tests/integration/`.

### Iteration discipline (must always destroy)

The integration test creates ~$0.01 of resources per run. If a run leaves resources standing, you owe AWS until someone notices. **Always confirm `Destroy complete` before considering a test run finished.** The script retries destroy 5 times with backoff and prints the manual-recovery command if all retries fail. If you have to run the manual command, do it before opening the PR — don't push a known-leaked state.

## 7. Branching & release model

- All work happens on feature branches: `feat/<thing>`, `fix/<thing>`, `chore/<thing>`.
- PRs target `main` directly (this is a module repo, no staging branch).
- **Squash-merge only** (repo setting). The squash commit message is what release-please reads, so write it as a Conventional Commit.
- **Linear history required** — no merge commits, no rebase merges.
- `main` is branch-protected: requires PR review + all CI checks green + conversation resolution.

`release-please` reads commits on `main` to compute the next version, opens a release PR with an updated `CHANGELOG.md`, and on merge auto-tags + creates the GitHub release. **Do not tag manually.**

## 8. Conventional Commits

PR titles and commit messages **must** follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

[body]

[footer]
```

Types this repo uses (in order of release-please impact):

| Type | Bumps | Example |
| --- | --- | --- |
| `feat:` | minor (post-1.0) / minor (pre-1.0) | `feat(ecs-app): add target_group_arn input` |
| `fix:` | patch | `fix(ecs-app): correct for_each on ingress SG list` |
| `feat!:` or footer `BREAKING CHANGE:` | major | `feat(ecs-app)!: rename autoscaling_max_capacity → max_replicas` |
| `perf:` | patch | |
| `refactor:` | none | |
| `test:` | none | |
| `docs:` | none | |
| `chore:` / `ci:` | none | |

Every PR must reference its Linear issue in the description (`Closes BUD-XXX`). The PR template enforces this. If the work doesn't have a Linear issue, create one first — undocumented infra changes are a blameless audit failure waiting to happen.

## 9. CI/CD

Four workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `terraform-modules-ci.yml` | push to `main`/`dev`, all PRs, manual dispatch | `terraform fmt -check -recursive` + init/validate on `modules/ecr-repository`, `modules/ecs-app`, `examples/ecs-ecr-app`. `tests/integration` is not in this matrix. |
| `docs-check.yml` | PRs touching `modules/`, `.terraform-docs.yml`, or `scripts/docs.sh` | `./scripts/docs.sh --check` — fails on doc drift. |
| `integration-test.yml` | gated behind `vars.RUN_INTEGRATION_TEST == 'true'` (BUD-86) | Runs the real-AWS integration test in CI. Off until OIDC trust to assume an AWS role from this repo's CI is wired. Until then, run locally. |
| `release-please.yml` | push to `main` | Opens/updates the release PR; on merge cuts a tag + GitHub release. |

## 10. Secrets & auth

- **Locally:** `AWS_PROFILE=buddy-athletics`. The integration test reads from this profile.
- **In CI today:** no AWS secrets required — integration-test CI is gated off. CI only runs `terraform fmt`/`validate` and `terraform-docs --check`, none of which call AWS.
- **In CI tomorrow (BUD-86):** an OIDC role assumed from this repo's CI, trusted by `buddy-shared-infrastructure/bootstrap/main.tf:65-101`. No static AWS keys.

## 11. Cross-repo contracts

This repo is the bottom of the dependency stack. Its consumers and dependencies:

- **Consumed by app repos** (e.g. `buddyMVP-Admin/deploy/main.tf`) as:

  ```hcl
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//modules/<name>?ref=vX.Y.Z"
  ```

  **Always pin a semver tag** — branch refs and floating refs are forbidden. Bumping the ref is the way modules are consumed.

- **Depends on `buddy-shared-infrastructure` at runtime only.** The integration test resolves cluster ARN, VPC, and subnets from shared-infra dev state. CI validation does not require shared-infra — modules `validate` without it.

- **OIDC trust** for the future integration-test CI is defined in `buddy-shared-infrastructure/bootstrap/main.tf:65-101`. This repo cannot grant itself AWS access.

## 12. Repo-specific conventions

### 12.1 Backwards-compatibility rules

When extending a module:

1. **All new inputs must have a default.** Existing callers should see zero plan diff after upgrading the `?ref=` pin.
2. **Existing input names + types are immutable** within a major version. To rename, ship the new input alongside the old one (with a deprecation note in the module README) and remove the old one in the next major release.
3. **Outputs are append-only** within a major version. Removing or renaming an output is a breaking change.
4. **`examples/ecs-ecr-app` must validate without source changes** after any module update. The CI matrix verifies this.

If you must break compatibility, mark the commit with `feat!:` or include `BREAKING CHANGE:` in the commit footer. Release-please will bump the major version, the changelog will surface the migration note, and consumers will know to read the upgrade guide.

### 12.2 Adding a new module

1. Create `modules/<name>/` with `terraform.tf`, `main.tf`, `variables.tf`, `outputs.tf`.
2. Add a `modules/<name>/README.md` with usage examples and the `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers — see existing modules for the shape.
3. Run `./scripts/docs.sh` to populate the auto-generated section.
4. Add the new module path to `.github/workflows/terraform-modules-ci.yml`'s validate loop.
5. If the module has a complex apply path, add or extend `tests/integration/main.tf` to exercise it; ensure the integration test still runs clean.
6. Update this `AGENTS.md` if any new conventions are introduced.

### 12.3 Auto-doc markers

Hand-written content (usage examples, design rationale, upgrade notes) lives **above** `<!-- BEGIN_TF_DOCS -->` and survives regeneration. Anything between the BEGIN/END markers is owned by `terraform-docs` — do not hand-edit.

## 13. Quick reference

| What | Command |
| --- | --- |
| Format | `terraform fmt -recursive` |
| Format check (CI mode) | `terraform fmt -check -recursive` |
| Validate one dir | `terraform -chdir=modules/ecs-app validate` |
| Validate all dirs | `for dir in modules/ecr-repository modules/ecs-app examples/ecs-ecr-app tests/integration; do terraform -chdir="$dir" init -backend=false -upgrade && terraform -chdir="$dir" validate; done` |
| Regenerate module docs | `./scripts/docs.sh` |
| Check docs in CI mode | `./scripts/docs.sh --check` |
| Run integration test | `AWS_PROFILE=buddy-athletics ./scripts/test-integration.sh` |
| Manual destroy if test left resources | `terraform -chdir=tests/integration destroy -auto-approve -lock=false -var test_run_id=v030-lifecycle -var vpc_id=... -var 'subnet_ids=[...]' -var ecs_cluster_arn=...` |
| Verify zero leftover test resources | `aws ec2 describe-security-groups --filters 'Name=group-name,Values=ecs-app-test*'` |

## 14. Decision records

Architectural decisions for this repo live in `docs/agent-os/decision-records/`:

- `0001-ecr-ownership.md` — Which repo owns ECR resources (app repos, not this one).
- `0002-module-ci-validation.md` — The CI validation matrix and the rationale for excluding `tests/integration` from it.
- `0003-dev-prod-ecr-promotion.md` — Dev→prod ECR image promotion contract.

This `AGENTS.md` references those ADRs rather than restating them. If an ADR conflicts with this file, the ADR wins — open a PR to update `AGENTS.md`.
