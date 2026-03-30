locals {
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "ecr-repository"
  })
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
    rules = [{
      rulePriority = 1
      description  = "Keep only the most recent tagged images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = var.lifecycle_tag_prefixes
        countType     = "imageCountMoreThan"
        countNumber   = var.max_tagged_image_count
      }
      action = {
        type = "expire"
      }
    }]
  })
}
