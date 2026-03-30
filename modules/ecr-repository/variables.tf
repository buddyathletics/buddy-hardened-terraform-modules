variable "repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "scan_on_push" {
  description = "Enable image scan on push"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "Tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "encryption_type" {
  description = "ECR encryption type (AES256 or KMS)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN when encryption_type is KMS"
  type        = string
  default     = ""

  validation {
    condition     = var.encryption_type != "KMS" || trimspace(var.kms_key_arn) != ""
    error_message = "kms_key_arn is required when encryption_type is KMS."
  }
}

variable "create_lifecycle_policy" {
  description = "Whether to create lifecycle policy"
  type        = bool
  default     = true
}

variable "lifecycle_policy_type" {
  description = "Lifecycle profile for retention rules: count (default) or dev_short"
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "dev_short"], var.lifecycle_policy_type)
    error_message = "lifecycle_policy_type must be count or dev_short."
  }
}

variable "lifecycle_tag_prefixes" {
  description = "Tagged image prefixes included by count-based lifecycle policy"
  type        = list(string)
  default     = ["latest", "main", "prod", "dev"]
}

variable "max_tagged_image_count" {
  description = "Maximum number of tagged images to retain for count-based lifecycle policy"
  type        = number
  default     = 30
}

variable "dev_lifecycle_tag_prefixes" {
  description = "Tagged image prefixes included by dev_short retention profile"
  type        = list(string)
  default     = ["sha-", "dev-", "latest"]
}

variable "dev_tagged_expire_days" {
  description = "Expire tagged images older than this many days in dev_short profile"
  type        = number
  default     = 7
}

variable "untagged_expire_days" {
  description = "Expire untagged images older than this many days in dev_short profile"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
