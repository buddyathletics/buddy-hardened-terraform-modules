#!/usr/bin/env bash
# Regenerate per-module README terraform-docs blocks.
#
# Usage:
#   ./scripts/docs.sh           # update READMEs in place
#   ./scripts/docs.sh --check   # exit non-zero if READMEs are stale (CI mode)

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v terraform-docs >/dev/null 2>&1; then
  echo "terraform-docs not installed. Get it from https://terraform-docs.io" >&2
  exit 1
fi

mode="inject"
check_flag=""
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
  check_flag="--output-check"
fi

# The .terraform-docs.yml at repo root has `recursive: { enabled: true, path: modules }`,
# so a single invocation walks every modules/* directory and writes/checks each
# README's BEGIN_TF_DOCS / END_TF_DOCS block.
if [[ -n "${check_flag}" ]]; then
  terraform-docs --config .terraform-docs.yml ${check_flag} .
else
  terraform-docs --config .terraform-docs.yml .
fi

case "${mode}" in
  inject) echo "Updated module READMEs in ${REPO_ROOT}/modules/" ;;
  check)  echo "All module READMEs are in sync with their variables.tf / outputs.tf" ;;
esac
