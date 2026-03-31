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

locals {
  dev_repository_name  = "${var.repository_name_prefix}-dev"
  prod_repository_name = "${var.repository_name_prefix}-prod"

  # Expected image lifecycle in app CI/CD:
  # - dev repository: sha-<commit>, dev-latest
  # - prod repository: vX.Y.Z (+ mirrored sha-<commit> after promotion)
}

data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = var.shared_state_bucket
    key    = var.shared_state_key
    region = var.aws_region
  }
}

module "ecr_repository_dev" {
  source = "../../modules/ecr-repository"

  repository_name         = local.dev_repository_name
  image_tag_mutability    = "MUTABLE"
  lifecycle_policy_type   = "dev_short"
  create_lifecycle_policy = true
  tags                    = var.tags
}

module "ecr_repository_prod" {
  source = "../../modules/ecr-repository"

  repository_name         = local.prod_repository_name
  image_tag_mutability    = "IMMUTABLE"
  lifecycle_policy_type   = "count"
  create_lifecycle_policy = false
  tags                    = var.tags
}

module "ecs_app" {
  source = "../../modules/ecs-app"

  app_name           = var.app_name
  ecr_repository_url = var.environment == "dev" ? module.ecr_repository_dev.repository_url : module.ecr_repository_prod.repository_url
  image_tag          = var.image_tag
  container_port     = var.container_port
  environment        = var.environment

  vpc_id          = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.shared.outputs.public_subnet_ids
  ecs_cluster_arn = data.terraform_remote_state.shared.outputs.ecs_cluster_arn

  desired_count = var.desired_count

  enable_cloudflare_tunnel           = var.enable_cloudflare_tunnel
  cloudflare_tunnel_token_secret_arn = var.cloudflare_tunnel_token_secret_arn

  tags = var.tags
}
