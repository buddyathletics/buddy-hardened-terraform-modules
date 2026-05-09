locals {
  app_container_name    = "${var.app_name}-container"
  tunnel_container_name = "${var.app_name}-cloudflared"
  port_name             = "app-${var.container_port}"

  common_tags = merge(var.tags, {
    App         = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # Cluster name parsed from cluster ARN tail (arn:aws:ecs:region:account:cluster/<name>)
  cluster_name = element(split("/", var.ecs_cluster_arn), length(split("/", var.ecs_cluster_arn)) - 1)

  app_container = {
    name  = local.app_container_name
    image = "${var.ecr_repository_url}:${var.image_tag}"
    portMappings = [{
      name          = local.port_name
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
      appProtocol   = "http"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "app"
      }
    }
    environment = var.environment_variables
    secrets = [
      for name, arn in var.secrets : {
        name      = name
        valueFrom = arn
      }
    ]
  }

  tunnel_container = {
    name       = local.tunnel_container_name
    image      = var.cloudflared_image
    essential  = true
    entryPoint = ["/bin/sh", "-c"]
    command    = ["cloudflared tunnel --no-autoupdate run --token \"$TUNNEL_TOKEN\""]
    secrets = [{
      name      = "TUNNEL_TOKEN"
      valueFrom = var.cloudflare_tunnel_token_secret_arn
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "tunnel"
      }
    }
  }
}

data "aws_region" "current" {}

# v0.3.0: AWS-managed KMS key alias for SSM SecureString decrypts.
# Task execution role gets kms:Decrypt on this key when var.secrets is non-empty.
data "aws_kms_alias" "ssm" {
  count = length(var.secrets) > 0 ? 1 : 0
  name  = "alias/aws/ssm"
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_name}-ecs-tasks-sg"
  description = "Security group for ${var.app_name} ECS tasks"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_cidr_blocks
    content {
      description = "Optional inbound on app port"
      from_port   = var.container_port
      to_port     = var.container_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-ecs-tasks-sg"
  })
}

# v0.3.0: SG-to-SG ingress rules. Lets a frontend's SG (or a shared ALB's SG)
# reach this service's container_port without opening any CIDR. Use this to
# keep the API service internal-only while still allowing the frontend to call it.
#
# for_each is keyed by stable list index (a string), not by SG id. Indexing
# by SG id would require those ids to be known at plan time, which fails when
# the caller passes a freshly-created peer SG via `module.frontend.security_group_id`.
resource "aws_security_group_rule" "ingress_from_peer_sg" {
  for_each = {
    for idx, sg_id in var.ingress_security_group_ids : tostring(idx) => sg_id
  }

  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.ecs_tasks.id
  description              = "Ingress on container_port from peer SG (Service Connect callers / ALB)"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.app_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "tunnel_secret_access" {
  count = var.enable_cloudflare_tunnel ? 1 : 0

  name = "${var.app_name}-tunnel-secret-access"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.cloudflare_tunnel_token_secret_arn
    }]
  })
}

# v0.3.0: SSM/Secrets Manager access for the secrets input.
# Granted on exactly the ARNs in var.secrets — least-privilege.
resource "aws_iam_role_policy" "secrets_access" {
  count = length(var.secrets) > 0 ? 1 : 0

  name = "${var.app_name}-secrets-access"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "secretsmanager:GetSecretValue",
        ]
        Resource = values(var.secrets)
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = data.aws_kms_alias.ssm[0].target_key_arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-logs"
  })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.app_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode(
    concat(
      [local.app_container],
      var.enable_cloudflare_tunnel ? [local.tunnel_container] : []
    )
  )

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-task-definition"
  })
}

resource "aws_ecs_service" "app" {
  name            = "${var.app_name}-service"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  # v0.3.0: launch_type stays default-FARGATE unless capacity_provider_strategy is set.
  # Setting both is a Terraform error — we omit launch_type whenever the strategy list is non-empty.
  launch_type = length(var.capacity_provider_strategy) == 0 ? "FARGATE" : null

  health_check_grace_period_seconds = var.target_group_arn != null ? var.health_check_grace_period_seconds : null

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # v0.3.0: FARGATE / FARGATE_SPOT mix when supplied.
  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      base              = capacity_provider_strategy.value.base
      weight            = capacity_provider_strategy.value.weight
    }
  }

  # v0.3.0: ALB target group attach (frontend services only — APIs leave target_group_arn null).
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = local.app_container_name
      container_port   = var.container_port
    }
  }

  # v0.3.0: ECS Service Connect — internal service mesh.
  # When namespace is set: this service joins the namespace.
  # When port_alias is also set: it registers under <alias>:<container_port> for sibling-service callers.
  dynamic "service_connect_configuration" {
    for_each = var.service_connect_namespace_arn != null ? [1] : []
    content {
      enabled   = true
      namespace = var.service_connect_namespace_arn

      log_configuration {
        log_driver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "service-connect"
        }
      }

      dynamic "service" {
        for_each = var.service_connect_port_alias != null ? [1] : []
        content {
          port_name      = local.port_name
          discovery_name = var.service_connect_port_alias
          client_alias {
            port     = var.container_port
            dns_name = var.service_connect_port_alias
          }
        }
      }
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  # v0.3.0: autoscaling adjusts desired_count out-of-band; ignore drift on subsequent applies.
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-ecs-service"
  })
}

# ----------------------------------------------------------------------------
# v0.3.0: Application Auto Scaling (CPU target tracking)
# ----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min_capacity
  max_capacity       = var.autoscaling_max_capacity
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.app_name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
  }
}

# ----------------------------------------------------------------------------
# v0.3.0: CloudWatch alarms (default set)
# ----------------------------------------------------------------------------

locals {
  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  # Parse target group "name" suffix for ALB-derived alarm dimensions
  # (TargetGroup dimension wants targetgroup/<name>/<id>; we get this from the ARN).
  target_group_arn_suffix = var.target_group_arn != null ? trimprefix(
    element(split(":", var.target_group_arn), 5),
    "targetgroup/"
  ) : null
  target_group_dim = var.target_group_arn != null ? "targetgroup/${local.target_group_arn_suffix}" : null
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.app_name}-cpu-high"
  alarm_description   = "ECS service CPU utilization sustained above ${var.alarm_cpu_threshold}% for 15 minutes."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  threshold           = var.alarm_cpu_threshold
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.app_name}-memory-high"
  alarm_description   = "ECS service memory utilization sustained above ${var.alarm_memory_threshold}% for 15 minutes."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  threshold           = var.alarm_memory_threshold
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "task_count_low" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.app_name}-task-count-low"
  alarm_description   = "ECS running task count below autoscaling_min_capacity for 5 minutes — service can't keep tasks alive."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = var.autoscaling_min_capacity
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = local.common_tags
}

# ALB-derived alarms — only rendered when target_group_arn is set.

resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  count = var.enable_alarms && var.target_group_arn != null ? 1 : 0

  alarm_name          = "${var.app_name}-alb-5xx-rate"
  alarm_description   = "Target 5xx rate above ${var.alarm_5xx_error_rate_threshold * 100}% over 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.alarm_5xx_error_rate_threshold

  metric_query {
    id          = "error_rate"
    expression  = "IF(requests > 0, errors / requests, 0)"
    label       = "5xx error rate"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        TargetGroup = local.target_group_dim
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        TargetGroup = local.target_group_dim
      }
    }
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_p95_latency" {
  count = var.enable_alarms && var.target_group_arn != null ? 1 : 0

  alarm_name          = "${var.app_name}-alb-p95-latency"
  alarm_description   = "ALB target response time p95 above ${var.alarm_p95_latency_threshold_seconds}s over 10 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.alarm_p95_latency_threshold_seconds
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p95"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup = local.target_group_dim
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  count = var.enable_alarms && var.target_group_arn != null ? 1 : 0

  alarm_name          = "${var.app_name}-alb-unhealthy-targets"
  alarm_description   = "One or more ALB targets unhealthy for 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup = local.target_group_dim
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = local.common_tags
}
