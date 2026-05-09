# Integration test fixture for ecs-app v0.3.0.
#
# Single combined root config that exercises every new v0.3.0 input except
# `target_group_arn` (which requires the shared ALB from BUD-11; covered
# by the first BUD-38 deploy instead). Run via `scripts/test-integration.sh`
# to get guaranteed-destroy behavior.

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

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
# Variables
# ----------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for the test"
}

variable "test_run_id" {
  type        = string
  default     = "v030-lifecycle"
  description = "Suffix for test resource names — bump if running multiple iterations in parallel"
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID — pulled from shared-infra dev"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Existing subnet IDs — pulled from shared-infra dev (public subnets are fine for the test)"
}

variable "ecs_cluster_arn" {
  type        = string
  description = "Existing ECS cluster ARN — buddy-athletics-dev-cluster"
}

# ----------------------------------------------------------------------------
# Throwaway test fixtures (Cloud Map namespace, peer SG, SSM SecureString,
# ECR repo). All scoped by var.test_run_id and destroyed at the end.
# ----------------------------------------------------------------------------

locals {
  app_name = "ecs-app-test-${var.test_run_id}"
}

resource "aws_service_discovery_http_namespace" "test" {
  name        = "ecs-app-test-${var.test_run_id}"
  description = "Throwaway namespace for ecs-app v0.3.0 module test"
}

resource "aws_security_group" "peer" {
  name        = "ecs-app-test-peer-${var.test_run_id}"
  description = "Throwaway peer SG for ingress_security_group_ids test"
  vpc_id      = var.vpc_id
}

resource "aws_ssm_parameter" "test_secret" {
  name        = "/ecs-app-test/${var.test_run_id}/TEST_SECRET"
  description = "Throwaway SecureString for ecs-app v0.3.0 module test"
  type        = "SecureString"
  value       = "throwaway-not-a-real-secret"
}

# Throwaway ECR repo so the module's image_tag points somewhere resolvable.
module "ecr" {
  source = "../../modules/ecr-repository"

  repository_name         = local.app_name
  image_tag_mutability    = "MUTABLE"
  lifecycle_policy_type   = "dev_short"
  create_lifecycle_policy = true
  tags                    = { TestRun = local.app_name }
}

# ----------------------------------------------------------------------------
# Module under test — exercises every new v0.3.0 input except target_group_arn.
# ----------------------------------------------------------------------------

module "app" {
  source = "../../modules/ecs-app"

  app_name           = local.app_name
  ecr_repository_url = module.ecr.repository_url
  image_tag          = "does-not-exist-yet" # circuit breaker tolerates failed pull at desired_count=0
  container_port     = 8080
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  ecs_cluster_arn    = var.ecs_cluster_arn
  environment        = "test"
  cpu                = 256
  memory             = 512
  desired_count      = 0 # don't actually try to schedule a task

  # v0.3.0 — Service Connect attachment
  service_connect_namespace_arn = aws_service_discovery_http_namespace.test.arn
  service_connect_port_alias    = "test-app"

  # v0.3.0 — SG-to-SG ingress
  ingress_security_group_ids = [aws_security_group.peer.id]

  # v0.3.0 — SSM-backed secrets (task execution role gets ssm:GetParameters + kms:Decrypt)
  secrets = {
    TEST_SECRET = aws_ssm_parameter.test_secret.arn
  }

  # v0.3.0 — autoscaling resources
  autoscaling_min_capacity = 0
  autoscaling_max_capacity = 2

  # v0.3.0 — capacity provider mix is *not* exercised here because the shared
  # dev cluster has no capacity providers attached (cluster.capacityProviders=[]),
  # so passing FARGATE_SPOT would fail at apply. The variable + dynamic block
  # are still validated structurally via `terraform validate`. The first real
  # consumer (BUD-38 buddyMVP-Admin deploy/) covers the apply path once the
  # cluster has FARGATE + FARGATE_SPOT attached as part of shared-infra prep.
  capacity_provider_strategy = []

  # v0.3.0 — alarms (3 will render; ALB-derived 3 skipped because target_group_arn is null)
  enable_alarms = true

  tags = { TestRun = local.app_name }
}

# ----------------------------------------------------------------------------
# Outputs the wrapper script asserts on
# ----------------------------------------------------------------------------

output "app_name" {
  value = local.app_name
}

output "ecs_service_name" {
  value = module.app.ecs_service_name
}

output "task_definition_arn" {
  value = module.app.task_definition_arn
}

output "security_group_id" {
  value = module.app.security_group_id
}

output "task_execution_role_arn" {
  value = module.app.task_execution_role_arn
}

output "appautoscaling_target_resource_id" {
  value = module.app.appautoscaling_target_resource_id
}

output "alarm_names" {
  value = module.app.alarm_names
}

output "log_group_name" {
  value = module.app.log_group_name
}

output "ssm_parameter_arn" {
  value = aws_ssm_parameter.test_secret.arn
}

output "service_connect_namespace_arn" {
  value = aws_service_discovery_http_namespace.test.arn
}

output "peer_security_group_id" {
  value = aws_security_group.peer.id
}
