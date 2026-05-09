# `ecr-repository` — Hardened ECR repo

Reusable Terraform module that creates an ECR repository with scan-on-push enabled, a tag-mutability policy, and an optional lifecycle policy with two pre-baked profiles:

| Profile | Use |
| --- | --- |
| `dev_short` | Aggressive lifecycle for dev images — keep last 10 by tag count, expire untagged after 1 day |
| `count` | Conservative for prod — keep last 30 tagged images |

## Usage

Dev repo (mutable tags, aggressive cleanup):

```hcl
module "ecr_dev" {
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//modules/ecr-repository?ref=v0.3.0"

  repository_name         = "my-app-dev"
  image_tag_mutability    = "MUTABLE"
  lifecycle_policy_type   = "dev_short"
  create_lifecycle_policy = true
  scan_on_push            = true
}
```

Prod repo (immutable tags, slower cleanup):

```hcl
module "ecr_prod" {
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//modules/ecr-repository?ref=v0.3.0"

  repository_name         = "my-app-prod"
  image_tag_mutability    = "IMMUTABLE"
  lifecycle_policy_type   = "count"
  create_lifecycle_policy = false # opt out if your team manages lifecycle elsewhere
  scan_on_push            = true
}
```

## Tag mutability policy

`image_tag_mutability = "IMMUTABLE"` is recommended for prod — once a tag points at a digest, it can't be reassigned. This prevents accidental rollbacks from going stale and matches the digest-promotion model used by `release-promote.yml` in consuming app repos.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_repository_name"></a> [repository\_name](#input\_repository\_name) | ECR repository name | `string` | n/a | yes |
| <a name="input_create_lifecycle_policy"></a> [create\_lifecycle\_policy](#input\_create\_lifecycle\_policy) | Whether to create lifecycle policy | `bool` | `true` | no |
| <a name="input_dev_lifecycle_tag_prefixes"></a> [dev\_lifecycle\_tag\_prefixes](#input\_dev\_lifecycle\_tag\_prefixes) | Tagged image prefixes included by dev\_short retention profile | `list(string)` | <pre>[<br/>  "sha-",<br/>  "dev-",<br/>  "latest"<br/>]</pre> | no |
| <a name="input_dev_tagged_expire_days"></a> [dev\_tagged\_expire\_days](#input\_dev\_tagged\_expire\_days) | Expire tagged images older than this many days in dev\_short profile | `number` | `7` | no |
| <a name="input_encryption_type"></a> [encryption\_type](#input\_encryption\_type) | ECR encryption type (AES256 or KMS) | `string` | `"AES256"` | no |
| <a name="input_image_tag_mutability"></a> [image\_tag\_mutability](#input\_image\_tag\_mutability) | Tag mutability setting (MUTABLE or IMMUTABLE) | `string` | `"MUTABLE"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN when encryption\_type is KMS | `string` | `""` | no |
| <a name="input_lifecycle_policy_type"></a> [lifecycle\_policy\_type](#input\_lifecycle\_policy\_type) | Lifecycle profile for retention rules: count (default) or dev\_short | `string` | `"count"` | no |
| <a name="input_lifecycle_tag_prefixes"></a> [lifecycle\_tag\_prefixes](#input\_lifecycle\_tag\_prefixes) | Tagged image prefixes included by count-based lifecycle policy | `list(string)` | <pre>[<br/>  "latest",<br/>  "main",<br/>  "prod",<br/>  "dev"<br/>]</pre> | no |
| <a name="input_max_tagged_image_count"></a> [max\_tagged\_image\_count](#input\_max\_tagged\_image\_count) | Maximum number of tagged images to retain for count-based lifecycle policy | `number` | `30` | no |
| <a name="input_scan_on_push"></a> [scan\_on\_push](#input\_scan\_on\_push) | Enable image scan on push | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags | `map(string)` | `{}` | no |
| <a name="input_untagged_expire_days"></a> [untagged\_expire\_days](#input\_untagged\_expire\_days) | Expire untagged images older than this many days in dev\_short profile | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_repository_arn"></a> [repository\_arn](#output\_repository\_arn) | ECR repository ARN |
| <a name="output_repository_name"></a> [repository\_name](#output\_repository\_name) | ECR repository name |
| <a name="output_repository_url"></a> [repository\_url](#output\_repository\_url) | ECR repository URL |
<!-- END_TF_DOCS -->
