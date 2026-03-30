output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "security_group_id" {
  description = "ECS task security group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.app.arn
}
