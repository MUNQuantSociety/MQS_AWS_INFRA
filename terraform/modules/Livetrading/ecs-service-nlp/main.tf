###############################################################################
# Always-on NLP Fargate service.
#
# Runs `python NLP/main_NLP.py` 24/7. ECS Service handles crash restarts.
###############################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-nlp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.image_uri
      essential = true

      entryPoint = ["/app/MQS/bin/python"]
      command    = ["NLP/main_NLP.py"]

      workingDirectory = "/app"

      environment = [
        { name = "PYTHONUNBUFFERED", value = "1" },
        { name = "PYTHONPATH", value = "/app:/app/src" },
      ]

      secrets = var.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nlp"
        }
      }
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "this" {
  name            = "${var.name_prefix}-nlp"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  lifecycle {
    # CI/CD bumps revision via aws ecs update-service.
    ignore_changes = [task_definition, desired_count]
  }
}
