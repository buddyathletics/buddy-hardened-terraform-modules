locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "ecr-repository"
  })

  dev_tagged_expire_rule = {
    rulePriority = 1
    description  = "Expire dev-tagged images older than configured age"
    selection = {
      tagStatus     = "tagged"
      tagPrefixList = var.dev_lifecycle_tag_prefixes
      countType     = "sinceImagePushed"
      countUnit     = "days"
      countNumber   = var.dev_tagged_expire_days
    }
    action = {
      type = "expire"
    }
  }

  dev_untagged_expire_rule = {
    rulePriority = 2
    description  = "Expire untagged images quickly in dev profile"
    selection = {
      tagStatus     = "untagged"
      tagPrefixList = []
      countType     = "sinceImagePushed"
      countUnit     = "days"
      countNumber   = var.untagged_expire_days
    }
    action = {
      type = "expire"
    }
  }

  count_tagged_rule = {
    rulePriority = 1
    description  = "Keep only the most recent tagged images"
    selection = {
      tagStatus     = "tagged"
      tagPrefixList = var.lifecycle_tag_prefixes
      countType     = "imageCountMoreThan"
      countUnit     = null
      countNumber   = var.max_tagged_image_count
    }
    action = {
      type = "expire"
    }
  }

  lifecycle_rules = var.lifecycle_policy_type == "dev_short" ? tolist([local.dev_tagged_expire_rule, local.dev_untagged_expire_rule]) : tolist([local.count_tagged_rule])
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = var.create_lifecycle_policy ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = local.lifecycle_rules
  })
}
