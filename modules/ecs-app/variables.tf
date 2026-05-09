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
    condition     = !var.enable_cloudflare_tunnel || trimspace(var.cloudflare_tunnel_token_secret_arn) != ""
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

# ----------------------------------------------------------------------------
# v0.3.1 additions: dedicated ECS *task* role for application-runtime IAM
# (distinct from the execution role used by ECS itself to pull images and
# fetch secrets). Always created; inline policy only rendered when non-empty.
# ----------------------------------------------------------------------------

variable "task_role_policy_json" {
  description = "Optional inline IAM policy JSON attached to the ECS task role. Use this to grant the running application code access to AWS APIs (S3, DynamoDB, SQS, etc.). Empty (default) means the task role exists but has no runtime permissions, which is correct for apps that don't call AWS at runtime."
  type        = string
  default     = ""
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: ALB target group attach
# ----------------------------------------------------------------------------

variable "target_group_arn" {
  description = "Optional ALB target group ARN. When set, the service registers as a target on the shared ALB. When null, the service is internal-only (Service Connect required for sibling-service traffic)."
  type        = string
  default     = null
}

variable "health_check_grace_period_seconds" {
  description = "Grace period before ALB health checks count toward task replacement. Only effective when target_group_arn is set."
  type        = number
  default     = 60
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: ECS Service Connect (internal service mesh)
# ----------------------------------------------------------------------------

variable "service_connect_namespace_arn" {
  description = "Cloud Map HTTP namespace ARN for ECS Service Connect. When set, this service joins the namespace and can reach (or be reached by) sibling services without going through the public ALB."
  type        = string
  default     = null
}

variable "service_connect_port_alias" {
  description = "DNS alias for this service inside the Service Connect namespace (e.g. \"api\"). When set, sibling services in the same namespace reach this service at <alias>:<container_port>. Leave null for client-only mode (this service can call others but isn't reachable by alias)."
  type        = string
  default     = null
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: SG-to-SG ingress (lets a frontend's SG reach this service's SG)
# ----------------------------------------------------------------------------

variable "ingress_security_group_ids" {
  description = "Security group IDs allowed inbound on container_port. Use this to grant the frontend's SG access to the API's SG without exposing the API publicly. Empty list when service is fronted by ALB only."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: Secrets via SSM/Secrets Manager (never persisted in task definition)
# ----------------------------------------------------------------------------

variable "secrets" {
  description = "Map of env-var name to SSM parameter ARN (or Secrets Manager ARN). Rendered into the task definition's secrets field; the task execution role IAM policy is automatically extended with ssm:GetParameters and kms:Decrypt on those exact ARNs."
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: Application Auto Scaling (target tracking on CPU)
# ----------------------------------------------------------------------------

variable "autoscaling_min_capacity" {
  description = "Minimum task count for Application Auto Scaling. Sets the floor under which the service will not scale in."
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum task count for Application Auto Scaling. Sets the ceiling above which the service will not scale out."
  type        = number
  default     = 10
}

variable "autoscaling_cpu_target" {
  description = "Target average CPU utilization percent for the target-tracking scaling policy."
  type        = number
  default     = 70
}

variable "autoscaling_scale_out_cooldown" {
  description = "Cooldown (seconds) after scaling out before another scale-out can occur."
  type        = number
  default     = 60
}

variable "autoscaling_scale_in_cooldown" {
  description = "Cooldown (seconds) after scaling in before another scale-in can occur. Higher values smooth out flapping."
  type        = number
  default     = 300
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: FARGATE / FARGATE_SPOT capacity provider mix
# ----------------------------------------------------------------------------

variable "capacity_provider_strategy" {
  description = "FARGATE / FARGATE_SPOT mix. When empty, falls back to launch_type = FARGATE (current behavior). Example: prod uses 1 on-demand baseline + 4x spot weight: [{ capacity_provider = \"FARGATE\", base = 1, weight = 1 }, { capacity_provider = \"FARGATE_SPOT\", base = 0, weight = 4 }]."
  type = list(object({
    capacity_provider = string
    base              = number
    weight            = number
  }))
  default = []
}

# ----------------------------------------------------------------------------
# v0.3.0 additions: CloudWatch alarms (default set)
# ----------------------------------------------------------------------------

variable "enable_alarms" {
  description = "Render the default CloudWatch alarm set (CPU, memory, task count, plus ALB-derived alarms when target_group_arn is set). Consumers can override by setting this to false and creating their own alarms outside the module."
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN to publish alarm state changes to. When null, alarms exist but don't route anywhere."
  type        = string
  default     = null
}

variable "alarm_cpu_threshold" {
  description = "Percent CPU utilization that triggers the cpu_high alarm. Sustained at threshold for 15 minutes."
  type        = number
  default     = 85
}

variable "alarm_memory_threshold" {
  description = "Percent memory utilization that triggers the memory_high alarm. Sustained at threshold for 15 minutes."
  type        = number
  default     = 85
}

variable "alarm_5xx_error_rate_threshold" {
  description = "5xx-rate threshold (e.g. 0.01 for 1%) that triggers the alb_5xx_rate alarm. Only rendered when target_group_arn is set."
  type        = number
  default     = 0.01
}

variable "alarm_p95_latency_threshold_seconds" {
  description = "p95 latency threshold (seconds) for the alb_p95_latency alarm. Only rendered when target_group_arn is set."
  type        = number
  default     = 0.5
}
