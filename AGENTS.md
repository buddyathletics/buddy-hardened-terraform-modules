# AGENTS.md — How to work in this repo

Guidance for AI agents (Claude, Codex, Cursor, etc.) and humans contributing to `buddy-hardened-terraform-modules`. This file is **canonical** for repo conventions; if you're an agent and you skip something here, the PR will fail CI.

## What this repo is

Reusable, hardened Terraform modules consumed by every Buddy app (admin, host, facility, user, future). Each module under `modules/` is independently versioned via `?ref=vX.Y.Z` git pins. **Backwards compatibility is non-negotiable**: a new module version must not introduce required inputs that break existing callers. Add inputs with sensible defaults instead.

```
modules/
  ecs-app/             — Hardened ECS Fargate service (ALB attach, SC, SSM secrets, alarms, autoscaling)
  ecr-repository/      — Hardened ECR repo (lifecycle profiles, scan-on-push, tag mutability)
examples/
  ecs-ecr-app/         — Reference consumer wired through both modules; serves as a contract test
tests/
  integration/         — Real-AWS end-to-end test fixture for ecs-app
scripts/
  docs.sh              — Regenerate per-module READMEs via terraform-docs
  test-integration.sh  — Apply + assert + must-always-destroy bash-trap test runner
```

## Required local checks before opening / updating a PR

These are **all** required. The corresponding CI jobs will fail your PR if you skip any.

### 1. Format

```bash
terraform fmt -check -recursive
```

CI: `Terraform Modules CI / validate` runs this from the repo root.

### 2. Validate

```bash
for dir in modules/ecr-repository modules/ecs-app examples/ecs-ecr-app tests/integration; do
  terraform -chdir="$dir" init -backend=false -upgrade
  terraform -chdir="$dir" validate
done
```

CI: same job.

### 3. Module docs (terraform-docs)

**Mandatory** any time you touch a module's `variables.tf`, `outputs.tf`, or add/remove a resource. The auto-generated tables in each `modules/*/README.md` between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` must stay in sync with the source.

```bash
./scripts/docs.sh           # regenerate
./scripts/docs.sh --check   # CI mode — exits non-zero if stale
```

CI: `Module Docs Check / docs-check` runs `--check` on every PR that touches `modules/`, the config, or the script. The PR is blocked from merging if drift is detected.

> Hand-written content **above** the `BEGIN_TF_DOCS` marker stays under human authorship — usage examples, design rationale, upgrade notes. Don't let terraform-docs touch that.

### 4. Integration test

For module behavioral changes (anything beyond comment-only or doc-only edits in a module):

```bash
AWS_PROFILE=buddy-athletics ./scripts/test-integration.sh
```

This applies a real AWS test deploy of the module, runs 9 assertions on the resources/IAM/SC namespace/SG ingress, then **always destroys** via a bash trap on EXIT/INT/TERM with up to 5 retries on plugin-startup flake. Must report `Destroy complete` at the end. **If you see anything else, do not push — investigate the manual destroy command printed by the script.**

CI: `Integration Test / integration-test` is committed but currently gated behind `vars.RUN_INTEGRATION_TEST == 'true'` until OIDC trust is set up (see Linear BUD-86). Once enabled, it runs on every PR touching `modules/`, `examples/`, `scripts/`, or `tests/integration/`.

### Iteration discipline (must always destroy)

The integration test creates ~$0.01 of resources per run. If a run leaves resources standing, you owe AWS until someone notices. **Always confirm `Destroy complete` before considering a test run finished.** The script retries destroy 5 times with backoff and prints the manual-recovery command if all retries fail. If you have to run the manual command, do it before opening the PR — don't push a known-leaked state.

## Conventional Commits

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

`release-please` reads commits on `main` to compute the next version, opens a release PR with an updated `CHANGELOG.md`, and on merge auto-tags + creates the GitHub release. **Do not tag manually.**

## Branch + merge model

- All work happens on feature branches: `feat/<thing>`, `fix/<thing>`, `chore/<thing>`.
- PRs target `main` directly (this is a module repo, no staging branch).
- **Squash-merge only** (repo setting). The squash commit message is what release-please reads, so write it as a Conventional Commit.
- **Linear history required** — no merge commits, no rebase merges.
- `main` is branch-protected: requires PR review + all CI checks green + conversation resolution.

## Linear linking

Every PR must reference its Linear issue in the description (`Closes BUD-XXX`). The PR template enforces this. If the work doesn't have a Linear issue, create one first — undocumented infra changes are a blameless audit failure waiting to happen.

## Backwards compatibility rules

When extending a module:

1. **All new inputs must have a default.** Existing callers should see zero plan diff after upgrading the `?ref=` pin.
2. **Existing input names + types are immutable** within a major version. To rename, ship the new input alongside the old one (with a deprecation note in the module README) and remove the old one in the next major release.
3. **Outputs are append-only** within a major version. Removing or renaming an output is a breaking change.
4. **The `examples/ecs-ecr-app` example must validate without source changes** after any module update. The CI matrix verifies this.

If you must break compatibility, mark the commit with `feat!:` or include `BREAKING CHANGE:` in the commit footer. Release-please will bump the major version, the changelog will surface the migration note, and consumers will know to read the upgrade guide.

## Adding a new module

1. Create `modules/<name>/` with `terraform.tf`, `main.tf`, `variables.tf`, `outputs.tf`.
2. Add a `modules/<name>/README.md` with usage examples and the BEGIN/END_TF_DOCS markers — see existing modules for the shape.
3. Run `./scripts/docs.sh` to populate the auto-generated section.
4. Add the new module path to `.github/workflows/terraform-modules-ci.yml`'s validate matrix.
5. If the module has a complex apply path, add or extend `tests/integration/main.tf` to exercise it; ensure the integration test still runs clean.
6. Update this AGENTS.md if any new conventions are introduced.

## Quick reference

| What | Command |
| --- | --- |
| Format | `terraform fmt -recursive` |
| Validate one dir | `terraform -chdir=modules/ecs-app validate` |
| Regenerate module docs | `./scripts/docs.sh` |
| Check docs in CI mode | `./scripts/docs.sh --check` |
| Run integration test | `AWS_PROFILE=buddy-athletics ./scripts/test-integration.sh` |
| Manual destroy if test left resources | `terraform -chdir=tests/integration destroy -auto-approve -lock=false -var test_run_id=v030-lifecycle -var vpc_id=... -var 'subnet_ids=[...]' -var ecs_cluster_arn=...` |
| Verify zero leftover test resources | `aws ec2 describe-security-groups --filters 'Name=group-name,Values=ecs-app-test*'` |
