output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "security_group_id" {
  description = "ECS task security group ID. Pass this as one of ingress_security_group_ids on a sibling service to grant SG-to-SG access."
  value       = aws_security_group.ecs_tasks.id
}

output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = aws_ecs_task_definition.app.arn
}

# v0.3.0 additions
output "task_execution_role_arn" {
  description = "ECS task execution role ARN (extended with SSM/Secrets Manager perms when secrets is non-empty)"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "appautoscaling_target_resource_id" {
  description = "Application Auto Scaling resource ID for this service. Useful for attaching custom scaling policies outside the module."
  value       = aws_appautoscaling_target.ecs.resource_id
}

output "alarm_names" {
  description = "Names of CloudWatch alarms created by this module (when enable_alarms = true). Empty list when alarms disabled."
  value = var.enable_alarms ? compact(concat(
    [
      try(aws_cloudwatch_metric_alarm.cpu_high[0].alarm_name, ""),
      try(aws_cloudwatch_metric_alarm.memory_high[0].alarm_name, ""),
      try(aws_cloudwatch_metric_alarm.task_count_low[0].alarm_name, ""),
    ],
    var.target_group_arn != null ? [
      try(aws_cloudwatch_metric_alarm.alb_5xx_rate[0].alarm_name, ""),
      try(aws_cloudwatch_metric_alarm.alb_p95_latency[0].alarm_name, ""),
      try(aws_cloudwatch_metric_alarm.alb_unhealthy_targets[0].alarm_name, ""),
    ] : []
  )) : []
}
