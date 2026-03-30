variable "app_name" {
  description = "Application name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 80
}

variable "desired_count" {
  description = "Desired ECS task count"
  type        = number
  default     = 1
}

variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "repository_name_prefix" {
  description = "App ECR repository prefix (example: buddyapp-poc)"
  type        = string
}

variable "shared_state_bucket" {
  description = "S3 bucket for shared remote state"
  type        = string
}

variable "shared_state_key" {
  description = "S3 key for shared remote state"
  type        = string
}

variable "enable_cloudflare_tunnel" {
  description = "Whether to run cloudflared sidecar"
  type        = bool
  default     = false
}

variable "cloudflare_tunnel_token_secret_arn" {
  description = "Secrets Manager ARN for Cloudflare tunnel token"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
