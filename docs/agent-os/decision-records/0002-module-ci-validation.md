# 0002 - Module Repository CI Validation

## Status
Accepted

## Decision
Use GitHub Actions CI to enforce formatting and Terraform validation on every module and example root.

## Consequences
- Broken modules are caught before release tagging.
- Example composition remains a verified contract for app repositories.
- Module consumers can rely on tagged versions with baseline validation evidence.
