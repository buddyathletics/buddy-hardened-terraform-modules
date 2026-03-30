output "ecr_repository_url" {
  description = "ECR URL"
  value       = module.ecr_repository.repository_url
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs_app.ecs_service_name
}
