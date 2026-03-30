output "ecr_repository_dev_url" {
  description = "Dev ECR URL"
  value       = module.ecr_repository_dev.repository_url
}

output "ecr_repository_prod_url" {
  description = "Prod ECR URL"
  value       = module.ecr_repository_prod.repository_url
}

output "selected_ecr_repository_url" {
  description = "Active environment ECR URL selected for ecs_app"
  value       = var.environment == "dev" ? module.ecr_repository_dev.repository_url : module.ecr_repository_prod.repository_url
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs_app.ecs_service_name
}
