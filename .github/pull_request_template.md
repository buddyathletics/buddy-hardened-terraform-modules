<!--
  PR title MUST follow Conventional Commits (feat|fix|test|refactor|perf|docs|chore|ci):
  release-please reads PR titles + commit messages to compute the next semver bump.

  Examples:
    feat(ecs-app): add support for X         → minor bump
    fix(ecs-app): correct for_each on Y      → patch bump
    feat(ecs-app)!: replace input Z          → major bump (note the !)

  Sections marked "Optional" can be deleted if irrelevant. Sections not marked
  must be filled in.
-->

## Summary

<!-- 1-3 sentences: what does this change do and why? -->

## Type of change

- [ ] feat — new module input/output, new resource type, new behavior
- [ ] fix — bug fix in existing behavior
- [ ] refactor — internal change with no behavior diff
- [ ] perf — measurable performance improvement
- [ ] docs — docs only
- [ ] test — test additions / fixes only
- [ ] chore / ci — build, tooling, workflows
- [ ] **breaking change** (also append `!` to the commit type)

## Module(s) affected

- [ ] `modules/ecs-app`
- [ ] `modules/ecr-repository`
- [ ] `examples/ecs-ecr-app`
- [ ] `tests/integration` (test harness only)
- [ ] None (CI / docs / scripts only)

## Backwards compatibility

- [ ] All new inputs have defaults (existing callers see no plan diff)
- [ ] `examples/ecs-ecr-app` validates with no source change
- [ ] Resource changes that would force replacement are flagged in the description

If this is a breaking change, describe the upgrade path consumers need to follow.

## Required checks (CI enforces these — see [AGENTS.md](../AGENTS.md))

- [ ] `terraform fmt -check -recursive` passes locally
- [ ] `terraform validate` passes for every directory in the CI matrix
- [ ] **`./scripts/docs.sh` re-run** if any module `variables.tf`, `outputs.tf`, or resource changed. The auto-generated tables between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` in each `modules/*/README.md` must stay in sync with the source. **`Module Docs Check / docs-check` will fail this PR if you forgot.**
- [ ] **`./scripts/test-integration.sh` ran clean** for any module behavioral change — apply succeeded, all 9 assertions passed, `Destroy complete` printed at the end. **Must-always-destroy is mandatory; if the trap couldn't destroy, run the manual recovery command before pushing.**
- [ ] Manual verification (describe what):

<!--
  The integration test runs against shared-infra dev. Per the iteration-discipline policy:
  every test run MUST end with destroy. The script's bash trap guarantees this; if you see
  anything other than "Destroy complete" at the end, investigate before merging.
-->

## Linear

<!-- Closes BUD-XXX (parent epic) and lists any sub-issues this PR closes. -->
