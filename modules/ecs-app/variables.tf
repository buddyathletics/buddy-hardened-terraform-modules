variable "app_name" {
  description = "Unique application name used in resource names"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL"
  type        = string
}

variable "container_port" {
  description = "Container listening port"
  type        = number
}

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "Shared ECS cluster ARN"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "Fargate CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired ECS task count"
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = "Whether ECS tasks receive public IPs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "ingress_cidr_blocks" {
  description = "Optional CIDR blocks that may reach the app container port"
  type        = list(string)
  default     = []
}

variable "environment_variables" {
  description = "Container environment variables"
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "enable_cloudflare_tunnel" {
  description = "Whether to run cloudflared sidecar for Cloudflare Tunnel"
  type        = bool
  default     = false
}

variable "cloudflare_tunnel_token_secret_arn" {
  description = "Secrets Manager ARN containing Cloudflare tunnel token"
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_cloudflare_tunnel || trim(var.cloudflare_tunnel_token_secret_arn) != ""
    error_message = "cloudflare_tunnel_token_secret_arn is required when enable_cloudflare_tunnel is true."
  }
}

variable "cloudflared_image" {
  description = "Container image for cloudflared sidecar"
  type        = string
  default     = "cloudflare/cloudflared:latest"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
