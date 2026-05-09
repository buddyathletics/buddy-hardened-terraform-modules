# ----------------------------------------------------------------------------
# Identity + environment
# ----------------------------------------------------------------------------

variable "app_name_prefix" {
  description = "App identifier used as the prefix for ECS service names, ECR repository names, the Service Connect namespace, and the SSM parameter path. Example: \"buddyMVP-Admin\"."
  type        = string
}

variable "repository_name_prefix" {
  description = "ECR repository name prefix. Combined with the service role and environment to form the full repo name (e.g. \"buddyMVP-Admin-frontend-dev\")."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Resource tags applied to every resource the example creates."
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------
# Shared remote state (VPC + subnets + cluster come from buddy-shared-infrastructure)
# ----------------------------------------------------------------------------

variable "shared_state_bucket" {
  description = "S3 bucket holding the shared-infrastructure remote state."
  type        = string
}

variable "shared_state_key" {
  description = "S3 key of the shared-infrastructure state for the chosen environment (e.g. \"networking/dev/terraform.tfstate\")."
  type        = string
}

# ----------------------------------------------------------------------------
# Shared ALB inputs (Phase B of the rollout will export these from shared-infra;
# pass them in directly until the remote state surfaces them).
# ----------------------------------------------------------------------------

variable "shared_https_listener_arn" {
  description = "ARN of the shared ALB's HTTPS listener. The example creates a listener_rule on this listener that forwards the frontend hostname to its target group."
  type        = string
}

variable "shared_alb_security_group_id" {
  description = "Security group ID of the shared ALB. Granted ingress to the frontend's SG so the ALB can reach frontend tasks on container_port."
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm fan-out (Slack via Q Developer in chat applications). Pass null to keep alarms silent."
  type        = string
  default     = null
}

# ----------------------------------------------------------------------------
# Public hostname + ALB listener-rule priority
# ----------------------------------------------------------------------------

variable "frontend_hostname" {
  description = "Public hostname for the frontend (e.g. \"admin-dev.buddyathletics.com\"). The shared ALB matches this in a host_header listener rule."
  type        = string
}

variable "listener_rule_priority" {
  description = "Listener-rule priority on the shared HTTPS listener. Must be globally unique across all apps sharing the listener — coordinate via the per-app priority table (admin=100, host=110, facility=120, user=130; new apps in steps of 10)."
  type        = number
}

# ----------------------------------------------------------------------------
# Per-service config — frontend
# ----------------------------------------------------------------------------

variable "frontend_image_tag" {
  description = "Container image tag for the frontend service."
  type        = string
  default     = "latest"
}

variable "frontend_container_port" {
  description = "Container port the frontend listens on (and the ALB target group forwards to)."
  type        = number
  default     = 80
}

variable "frontend_health_check_path" {
  description = "ALB target group health check path on the frontend (e.g. \"/healthz\")."
  type        = string
  default     = "/healthz"
}

variable "frontend_cpu" {
  description = "Fargate CPU units for the frontend service."
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Fargate memory in MB for the frontend service."
  type        = number
  default     = 512
}

# ----------------------------------------------------------------------------
# Per-service config — API
# ----------------------------------------------------------------------------

variable "api_image_tag" {
  description = "Container image tag for the API service."
  type        = string
  default     = "latest"
}

variable "api_container_port" {
  description = "Container port the API listens on. The frontend reaches the API at http://api:<port> via the Service Connect namespace."
  type        = number
  default     = 8006
}

variable "api_cpu" {
  description = "Fargate CPU units for the API service."
  type        = number
  default     = 512
}

variable "api_memory" {
  description = "Fargate memory in MB for the API service."
  type        = number
  default     = 1024
}
