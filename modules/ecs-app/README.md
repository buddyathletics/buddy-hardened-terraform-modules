# `ecs-app` — Hardened ECS Fargate service

Reusable Terraform module that creates an ECS Fargate service with sensible-secure defaults: dedicated security group, scoped task execution role, awslogs-driver log group, and (since v0.3.0) optional ALB target group attach, ECS Service Connect, SSM-backed secrets, target-tracking autoscaling, FARGATE_SPOT capacity provider mix, deployment circuit breaker, and a default CloudWatch alarm set.

## Usage

Minimal:

```hcl
module "app" {
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//modules/ecs-app?ref=v0.3.0"

  app_name           = "my-app-${var.environment}"
  ecr_repository_url = aws_ecr_repository.this.repository_url
  image_tag          = var.image_tag
  container_port     = 80
  vpc_id             = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_ids         = data.terraform_remote_state.shared.outputs.public_subnet_ids
  ecs_cluster_arn    = data.terraform_remote_state.shared.outputs.ecs_cluster_arn
  environment        = var.environment
}
```

Full v0.3.0 surface (frontend behind shared ALB, internal API via Service Connect, SSM secrets, autoscaling, alarms):

```hcl
module "ecs_frontend" {
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//modules/ecs-app?ref=v0.3.0"

  app_name                      = "buddyMVP-Admin-frontend-${var.environment}"
  ecr_repository_url            = module.ecr_frontend.repository_url
  image_tag                     = var.image_tag_frontend
  container_port                = 80
  target_group_arn              = aws_lb_target_group.frontend.arn
  service_connect_namespace_arn = aws_service_discovery_http_namespace.this.arn
  service_connect_port_alias    = "frontend"
  ingress_security_group_ids    = [data.terraform_remote_state.shared.outputs.shared_alb_security_group_id]
  vpc_id                        = data.terraform_remote_state.shared.outputs.vpc_id
  subnet_ids                    = data.terraform_remote_state.shared.outputs.private_app_subnet_ids
  ecs_cluster_arn               = data.terraform_remote_state.shared.outputs.ecs_cluster_arn
  environment                   = var.environment

  autoscaling_min_capacity = var.environment == "prod" ? 2 : 1
  autoscaling_max_capacity = var.environment == "prod" ? 10 : 3
  autoscaling_cpu_target   = 70

  capacity_provider_strategy = var.environment == "prod" ? [
    { capacity_provider = "FARGATE",      base = 1, weight = 1 },
    { capacity_provider = "FARGATE_SPOT", base = 0, weight = 4 },
  ] : [
    { capacity_provider = "FARGATE_SPOT", base = 0, weight = 1 },
  ]

  enable_alarms       = true
  alarm_sns_topic_arn = data.terraform_remote_state.shared.outputs.alarm_sns_topic_arn
}

module "ecs_api" {
  source = "git::https://github.com/buddyathletics/buddy-hardened-terraform-modules.git//modules/ecs-app?ref=v0.3.0"

  app_name           = "buddyMVP-Admin-api-${var.environment}"
  ecr_repository_url = module.ecr_api.repository_url
  image_tag          = var.image_tag_api
  container_port     = 8006
  target_group_arn   = null # internal-only

  service_connect_namespace_arn = aws_service_discovery_http_namespace.this.arn
  service_connect_port_alias    = "api"
  ingress_security_group_ids    = [module.ecs_frontend.security_group_id]

  secrets = {
    DATABASE_URL = aws_ssm_parameter.database_url.arn
  }

  # ... vpc/subnet/cluster + autoscaling + alarms inputs as above
}
```

## Backwards compatibility

All v0.3.0 additions ship with defaults that preserve the v0.2.3 behavior. Existing callers see no plan diff after upgrading the `?ref=` pin.

## Testing

The module is verified end-to-end against a real AWS account by `scripts/test-integration.sh` at the repo root. See `tests/README.md` for the iteration discipline (must-always-destroy via bash trap).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_appautoscaling_policy.ecs_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.alb_5xx_rate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.alb_p95_latency](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.alb_unhealthy_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.cpu_high](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.memory_high](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.task_count_low](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_ecs_service.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.ecs_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.secrets_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.tunnel_secret_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_task_execution_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.ingress_from_peer_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_kms_alias.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Unique application name used in resource names | `string` | n/a | yes |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Container listening port | `number` | n/a | yes |
| <a name="input_ecr_repository_url"></a> [ecr\_repository\_url](#input\_ecr\_repository\_url) | ECR repository URL | `string` | n/a | yes |
| <a name="input_ecs_cluster_arn"></a> [ecs\_cluster\_arn](#input\_ecs\_cluster\_arn) | Shared ECS cluster ARN | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to deploy into | `string` | n/a | yes |
| <a name="input_alarm_5xx_error_rate_threshold"></a> [alarm\_5xx\_error\_rate\_threshold](#input\_alarm\_5xx\_error\_rate\_threshold) | 5xx-rate threshold (e.g. 0.01 for 1%) that triggers the alb\_5xx\_rate alarm. Only rendered when target\_group\_arn is set. | `number` | `0.01` | no |
| <a name="input_alarm_cpu_threshold"></a> [alarm\_cpu\_threshold](#input\_alarm\_cpu\_threshold) | Percent CPU utilization that triggers the cpu\_high alarm. Sustained at threshold for 15 minutes. | `number` | `85` | no |
| <a name="input_alarm_memory_threshold"></a> [alarm\_memory\_threshold](#input\_alarm\_memory\_threshold) | Percent memory utilization that triggers the memory\_high alarm. Sustained at threshold for 15 minutes. | `number` | `85` | no |
| <a name="input_alarm_p95_latency_threshold_seconds"></a> [alarm\_p95\_latency\_threshold\_seconds](#input\_alarm\_p95\_latency\_threshold\_seconds) | p95 latency threshold (seconds) for the alb\_p95\_latency alarm. Only rendered when target\_group\_arn is set. | `number` | `0.5` | no |
| <a name="input_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#input\_alarm\_sns\_topic\_arn) | SNS topic ARN to publish alarm state changes to. When null, alarms exist but don't route anywhere. | `string` | `null` | no |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Whether ECS tasks receive public IPs | `bool` | `true` | no |
| <a name="input_autoscaling_cpu_target"></a> [autoscaling\_cpu\_target](#input\_autoscaling\_cpu\_target) | Target average CPU utilization percent for the target-tracking scaling policy. | `number` | `70` | no |
| <a name="input_autoscaling_max_capacity"></a> [autoscaling\_max\_capacity](#input\_autoscaling\_max\_capacity) | Maximum task count for Application Auto Scaling. Sets the ceiling above which the service will not scale out. | `number` | `10` | no |
| <a name="input_autoscaling_min_capacity"></a> [autoscaling\_min\_capacity](#input\_autoscaling\_min\_capacity) | Minimum task count for Application Auto Scaling. Sets the floor under which the service will not scale in. | `number` | `1` | no |
| <a name="input_autoscaling_scale_in_cooldown"></a> [autoscaling\_scale\_in\_cooldown](#input\_autoscaling\_scale\_in\_cooldown) | Cooldown (seconds) after scaling in before another scale-in can occur. Higher values smooth out flapping. | `number` | `300` | no |
| <a name="input_autoscaling_scale_out_cooldown"></a> [autoscaling\_scale\_out\_cooldown](#input\_autoscaling\_scale\_out\_cooldown) | Cooldown (seconds) after scaling out before another scale-out can occur. | `number` | `60` | no |
| <a name="input_capacity_provider_strategy"></a> [capacity\_provider\_strategy](#input\_capacity\_provider\_strategy) | FARGATE / FARGATE\_SPOT mix. When empty, falls back to launch\_type = FARGATE (current behavior). Example: prod uses 1 on-demand baseline + 4x spot weight: [{ capacity\_provider = "FARGATE", base = 1, weight = 1 }, { capacity\_provider = "FARGATE\_SPOT", base = 0, weight = 4 }]. | <pre>list(object({<br/>    capacity_provider = string<br/>    base              = number<br/>    weight            = number<br/>  }))</pre> | `[]` | no |
| <a name="input_cloudflare_tunnel_token_secret_arn"></a> [cloudflare\_tunnel\_token\_secret\_arn](#input\_cloudflare\_tunnel\_token\_secret\_arn) | Secrets Manager ARN containing Cloudflare tunnel token | `string` | `""` | no |
| <a name="input_cloudflared_image"></a> [cloudflared\_image](#input\_cloudflared\_image) | Container image for cloudflared sidecar | `string` | `"cloudflare/cloudflared:latest"` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Fargate CPU units | `number` | `256` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Desired ECS task count | `number` | `1` | no |
| <a name="input_enable_alarms"></a> [enable\_alarms](#input\_enable\_alarms) | Render the default CloudWatch alarm set (CPU, memory, task count, plus ALB-derived alarms when target\_group\_arn is set). Consumers can override by setting this to false and creating their own alarms outside the module. | `bool` | `true` | no |
| <a name="input_enable_cloudflare_tunnel"></a> [enable\_cloudflare\_tunnel](#input\_enable\_cloudflare\_tunnel) | Whether to run cloudflared sidecar for Cloudflare Tunnel | `bool` | `false` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Container environment variables | `list(object({ name = string, value = string }))` | `[]` | no |
| <a name="input_health_check_grace_period_seconds"></a> [health\_check\_grace\_period\_seconds](#input\_health\_check\_grace\_period\_seconds) | Grace period before ALB health checks count toward task replacement. Only effective when target\_group\_arn is set. | `number` | `60` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Docker image tag to deploy | `string` | `"latest"` | no |
| <a name="input_ingress_cidr_blocks"></a> [ingress\_cidr\_blocks](#input\_ingress\_cidr\_blocks) | Optional CIDR blocks that may reach the app container port | `list(string)` | `[]` | no |
| <a name="input_ingress_security_group_ids"></a> [ingress\_security\_group\_ids](#input\_ingress\_security\_group\_ids) | Security group IDs allowed inbound on container\_port. Use this to grant the frontend's SG access to the API's SG without exposing the API publicly. Empty list when service is fronted by ALB only. | `list(string)` | `[]` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days | `number` | `30` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Fargate memory in MB | `number` | `512` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Map of env-var name to SSM parameter ARN (or Secrets Manager ARN). Rendered into the task definition's secrets field; the task execution role IAM policy is automatically extended with ssm:GetParameters and kms:Decrypt on those exact ARNs. | `map(string)` | `{}` | no |
| <a name="input_service_connect_namespace_arn"></a> [service\_connect\_namespace\_arn](#input\_service\_connect\_namespace\_arn) | Cloud Map HTTP namespace ARN for ECS Service Connect. When set, this service joins the namespace and can reach (or be reached by) sibling services without going through the public ALB. | `string` | `null` | no |
| <a name="input_service_connect_port_alias"></a> [service\_connect\_port\_alias](#input\_service\_connect\_port\_alias) | DNS alias for this service inside the Service Connect namespace (e.g. "api"). When set, sibling services in the same namespace reach this service at <alias>:<container\_port>. Leave null for client-only mode (this service can call others but isn't reachable by alias). | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags | `map(string)` | `{}` | no |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn) | Optional ALB target group ARN. When set, the service registers as a target on the shared ALB. When null, the service is internal-only (Service Connect required for sibling-service traffic). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_names"></a> [alarm\_names](#output\_alarm\_names) | Names of CloudWatch alarms created by this module (when enable\_alarms = true). Empty list when alarms disabled. |
| <a name="output_appautoscaling_target_resource_id"></a> [appautoscaling\_target\_resource\_id](#output\_appautoscaling\_target\_resource\_id) | Application Auto Scaling resource ID for this service. Useful for attaching custom scaling policies outside the module. |
| <a name="output_ecs_service_name"></a> [ecs\_service\_name](#output\_ecs\_service\_name) | ECS service name |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch log group name |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ECS task security group ID. Pass this as one of ingress\_security\_group\_ids on a sibling service to grant SG-to-SG access. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ECS task definition ARN |
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | ECS task execution role ARN (extended with SSM/Secrets Manager perms when secrets is non-empty) |
<!-- END_TF_DOCS -->
