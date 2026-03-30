locals {
  app_container_name    = "${var.app_name}-container"
  tunnel_container_name = "${var.app_name}-cloudflared"

  common_tags = merge(var.tags, {
    App         = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  app_container = {
    name  = local.app_container_name
    image = "${var.ecr_repository_url}:${var.image_tag}"
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
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
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-ecs-service"
  })
}
