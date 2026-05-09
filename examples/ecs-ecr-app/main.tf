terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------------------------------------------------------
# Reference example: hardened public frontend + private API.
#
# Serves as the *contract test* for both modules in CI: any change to
# variables/outputs/resource shape that breaks this composition is caught
# by `terraform validate` before it ships.
#
# What this example demonstrates from the v0.3.0 module surface:
#
#   * Two ECR repos (one per service) with environment-correct lifecycle profiles
#   * Two ECS services in the same Service Connect namespace
#       - frontend → public via shared ALB target group; *client-only* mesh
#         participant (no Cloud Map alias — nothing inside the namespace ever
#         calls back into the frontend, so we don't publish one)
#       - api → internal-only (target_group_arn = null); registers as `api:8006`
#         so the frontend's nginx can `proxy_pass http://api:8006/`
#   * SG-to-SG ingress: API SG accepts traffic only from the frontend SG;
#     frontend SG accepts traffic only from the shared ALB SG
#   * Secret injection: DATABASE_URL pulled from SSM SecureString at task start
#     via the task execution role; value never lives in task definition,
#     Terraform state, or CI logs
#   * Default alarm set on both services routed to the shared SNS topic
#     (when the topic ARN is provided)
#
# Reachability is enforced by SGs, *not* by Service Connect. Service Connect
# is a discovery + load-balancing layer; it doesn't open ports.
# ----------------------------------------------------------------------------

locals {
  frontend_app_name  = "${var.app_name_prefix}-frontend-${var.environment}"
  api_app_name       = "${var.app_name_prefix}-api-${var.environment}"
  frontend_repo_name = "${var.repository_name_prefix}-frontend-${var.environment}"
  api_repo_name      = "${var.repository_name_prefix}-api-${var.environment}"
}

# Shared VPC / subnets / cluster come from the shared-infrastructure state.
data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.shared_state_bucket
    key    = var.shared_state_key
    region = var.aws_region
  }
}

# Per-app Service Connect namespace — gives the two services an internal DNS
# scope nobody else in the cluster can resolve into.
resource "aws_service_discovery_http_namespace" "this" {
  name        = "${var.app_name_prefix}-${var.environment}"
  description = "Internal Service Connect mesh for ${var.app_name_prefix} (${var.environment})"

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Frontend ALB target group + listener rule.
# Owned by the app, attached to the shared HTTPS listener. The listener rule's
# priority is per-app and globally unique on the listener — coordinate via the
# table in the buddyMVP-Admin architecture docs (admin=100, host=110, etc.).
# ----------------------------------------------------------------------------

resource "aws_lb_target_group" "frontend" {
  name        = "${var.app_name_prefix}-fe-${var.environment}"
  port        = var.frontend_container_port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id
  target_type = "ip"

  health_check {
    path                = var.frontend_health_check_path
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  deregistration_delay = 30
  tags                 = var.tags
}

resource "aws_lb_listener_rule" "frontend" {
  listener_arn = var.shared_https_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = [var.frontend_hostname]
    }
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# DATABASE_URL — SSM SecureString placeholder. Operator populates the real
# value out-of-band:
#
#   aws ssm put-parameter --overwrite \
#     --name /<app_name_prefix>/<env>/DATABASE_URL --type SecureString \
#     --value 'postgresql+asyncpg://...'
#
# Terraform never sees the real value (lifecycle ignore_changes), so it never
# lands in state, plan output, or CI logs. Rotate by repeating the put-parameter
# call + `aws ecs update-service --force-new-deployment`.
# ----------------------------------------------------------------------------

resource "aws_ssm_parameter" "database_url" {
  name        = "/${var.app_name_prefix}/${var.environment}/DATABASE_URL"
  description = "Postgres connection string. Populate out-of-band via aws ssm put-parameter."
  type        = "SecureString"
  value       = "PLACEHOLDER - populate via aws ssm put-parameter --overwrite"

  lifecycle {
    ignore_changes = [value]
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# ECR repositories — one per service.
# Dev gets MUTABLE tags + dev_short lifecycle (aggressive cleanup).
# Prod gets IMMUTABLE tags + count lifecycle (slower cleanup).
# ----------------------------------------------------------------------------

module "ecr_frontend" {
  source = "../../modules/ecr-repository"

  repository_name       = local.frontend_repo_name
  image_tag_mutability  = var.environment == "prod" ? "IMMUTABLE" : "MUTABLE"
  lifecycle_policy_type = var.environment == "prod" ? "count" : "dev_short"
  tags                  = var.tags
}

module "ecr_api" {
  source = "../../modules/ecr-repository"

  repository_name       = local.api_repo_name
  image_tag_mutability  = var.environment == "prod" ? "IMMUTABLE" : "MUTABLE"
  lifecycle_policy_type = var.environment == "prod" ? "count" : "dev_short"
  tags                  = var.tags
}

# ----------------------------------------------------------------------------
# Frontend ECS service — public via ALB; client-only Service Connect participant.
#
# `service_connect_port_alias` is intentionally omitted. The frontend joins the
# namespace (so it gets the Envoy sidecar and can resolve `api:8006`) but does
# NOT publish a `frontend:80` alias — nothing inside the mesh ever calls back
# into the frontend.
# ----------------------------------------------------------------------------

module "ecs_frontend" {
  source = "../../modules/ecs-app"

  app_name           = local.frontend_app_name
  ecr_repository_url = module.ecr_frontend.repository_url
  image_tag          = var.frontend_image_tag
  container_port     = var.frontend_container_port
  environment        = var.environment

  vpc_id          = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.shared.outputs.public_subnet_ids
  ecs_cluster_arn = data.terraform_remote_state.shared.outputs.ecs_cluster_arn

  # Public attach to the shared ALB.
  target_group_arn           = aws_lb_target_group.frontend.arn
  ingress_security_group_ids = [var.shared_alb_security_group_id]

  # Client-only Service Connect — joins the mesh, no published alias.
  service_connect_namespace_arn = aws_service_discovery_http_namespace.this.arn

  cpu    = var.frontend_cpu
  memory = var.frontend_memory

  autoscaling_min_capacity = var.environment == "prod" ? 2 : 1
  autoscaling_max_capacity = var.environment == "prod" ? 10 : 3

  capacity_provider_strategy = var.environment == "prod" ? [
    { capacity_provider = "FARGATE", base = 1, weight = 1 },
    { capacity_provider = "FARGATE_SPOT", base = 0, weight = 4 },
  ] : []

  enable_alarms       = true
  alarm_sns_topic_arn = var.alarm_sns_topic_arn

  tags = var.tags
}

# ----------------------------------------------------------------------------
# API ECS service — internal-only; server-mode Service Connect participant.
#
# Registers as `api:<api_container_port>` in the namespace. Only the frontend's
# SG can reach the API on that port — defense-in-depth at the SG layer in
# addition to the no-public-DNS / no-ALB-target posture.
# ----------------------------------------------------------------------------

module "ecs_api" {
  source = "../../modules/ecs-app"

  app_name           = local.api_app_name
  ecr_repository_url = module.ecr_api.repository_url
  image_tag          = var.api_image_tag
  container_port     = var.api_container_port
  environment        = var.environment

  vpc_id          = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.shared.outputs.public_subnet_ids
  ecs_cluster_arn = data.terraform_remote_state.shared.outputs.ecs_cluster_arn

  # No ALB attach — internal only.
  target_group_arn = null

  # Server-mode mesh participant: publishes `api:<port>` for the frontend.
  service_connect_namespace_arn = aws_service_discovery_http_namespace.this.arn
  service_connect_port_alias    = "api"

  # Defense-in-depth: only the frontend's SG may reach the API.
  ingress_security_group_ids = [module.ecs_frontend.security_group_id]

  cpu    = var.api_cpu
  memory = var.api_memory

  autoscaling_min_capacity = var.environment == "prod" ? 2 : 1
  autoscaling_max_capacity = var.environment == "prod" ? 15 : 3

  capacity_provider_strategy = var.environment == "prod" ? [
    { capacity_provider = "FARGATE", base = 1, weight = 1 },
    { capacity_provider = "FARGATE_SPOT", base = 0, weight = 4 },
  ] : []

  # Secret injection — execution-role IAM perms + kms:Decrypt are auto-extended
  # by the module against the exact ARN passed here. Value pulled at task start;
  # never lands in task definition, state, or logs.
  secrets = {
    DATABASE_URL = aws_ssm_parameter.database_url.arn
  }

  enable_alarms       = true
  alarm_sns_topic_arn = var.alarm_sns_topic_arn

  tags = var.tags
}
