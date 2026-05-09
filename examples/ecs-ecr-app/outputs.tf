output "frontend_ecr_repository_url" {
  description = "Frontend ECR repository URL — push the frontend image here as <url>:<tag>."
  value       = module.ecr_frontend.repository_url
}

output "api_ecr_repository_url" {
  description = "API ECR repository URL — push the API image here as <url>:<tag>."
  value       = module.ecr_api.repository_url
}

output "frontend_service_name" {
  description = "ECS service name for the frontend."
  value       = module.ecs_frontend.ecs_service_name
}

output "api_service_name" {
  description = "ECS service name for the API."
  value       = module.ecs_api.ecs_service_name
}

output "frontend_security_group_id" {
  description = "Frontend SG ID. Already granted ingress to the API's SG by this example; surfaced here for any sibling resource that needs to grant the frontend egress."
  value       = module.ecs_frontend.security_group_id
}

output "api_security_group_id" {
  description = "API SG ID. Ingress is restricted to the frontend SG and the shared ALB does not forward to it."
  value       = module.ecs_api.security_group_id
}

output "service_connect_namespace_arn" {
  description = "ARN of the per-app Service Connect namespace shared by the frontend and API."
  value       = aws_service_discovery_http_namespace.this.arn
}

output "frontend_target_group_arn" {
  description = "Target group ARN registered against the shared HTTPS listener for the frontend hostname."
  value       = aws_lb_target_group.frontend.arn
}

output "frontend_listener_rule_arn" {
  description = "Listener rule ARN that routes the frontend hostname to the frontend target group on the shared ALB."
  value       = aws_lb_listener_rule.frontend.arn
}

output "database_url_parameter_arn" {
  description = "SSM SecureString ARN for DATABASE_URL. Operator populates the value out-of-band; ECS pulls it at task start via the API's task execution role."
  value       = aws_ssm_parameter.database_url.arn
}

output "frontend_alarm_names" {
  description = "Names of the default CloudWatch alarms the frontend service emits when enable_alarms = true."
  value       = module.ecs_frontend.alarm_names
}

output "api_alarm_names" {
  description = "Names of the default CloudWatch alarms the API service emits when enable_alarms = true."
  value       = module.ecs_api.alarm_names
}
