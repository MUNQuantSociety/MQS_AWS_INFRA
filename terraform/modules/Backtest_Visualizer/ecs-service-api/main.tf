###############################################################################
# Always-on FastAPI service on Fargate.
#
# THE ONE THING NOT TO CHANGE: assign_public_ip must stay true.
#
# This stack has no NAT gateway, so a task ENI without a public IP has NO route
# off the VPC at all. It cannot reach the external Postgres, Supabase's JWKS
# endpoint, or -- fatally -- ECR. The apply still "succeeds": Terraform creates
# the service, and the tasks then fail forever with CannotPullContainerError
# while the service loops trying to place them. There is a validation below that
# refuses the combination rather than letting it fail at runtime.
#
# Ingress is still closed: the service security group accepts the container port
# from the ALB security group only (see modules/Backtest_Visualizer/security-groups). The public IP is an
# egress path, not a front door.
###############################################################################

locals {
  # The .env.example contract, minus anything secret. Secrets arrive through the
  # `secrets` block below as SSM parameter references, so no credential is ever
  # visible in the task definition, the console, or Terraform state.
  base_environment = [
    { name = "PYTHONUNBUFFERED", value = "1" },
    { name = "PYTHONPATH", value = "/app:/app/src" },
    { name = "HOST", value = "0.0.0.0" },
    { name = "PORT", value = tostring(var.container_port) },
  ]

  environment = concat(
    local.base_environment,
    [for k, v in var.environment : { name = k, value = v }],
  )

  # Container-level health check, off by default.
  #
  # It is deliberately NOT hardcoded: a container health check runs INSIDE the
  # image, so it has to name an interpreter or binary that actually exists on
  # that image's PATH. The sibling MQSMaster task definition is the cautionary
  # case -- it invokes /app/MQS/bin/python, a venv interpreter that is not on the
  # default PATH -- and this repo has no Dockerfile yet to check against.
  #
  # If the command binary is missing, ECS marks the essential container unhealthy
  # and kills the task, forever, and it presents as an application bug. Worse,
  # ignore_changes on container_definitions means a later apply will not repair
  # it; you would have to force a new revision by hand.
  #
  # The ALB target group probe already covers liveness for a load-balanced
  # service, so this buys little until the image is known. Set
  # container_health_check_command once there is a Dockerfile to verify against.
  container_definition = merge(
    {
      name      = var.container_name
      image     = var.image_uri
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = local.environment
      secrets     = var.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    },
    var.container_health_check_command == null ? {} : {
      healthCheck = {
        command     = var.container_health_check_command
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = var.health_check_grace_period
      }
    },
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([local.container_definition])

  # CI/CD registers new revisions on deploy (see the repo's .github/workflows).
  # Without this, every Terraform apply would roll the task definition back to
  # whatever image_tag is pinned in tfvars.
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "this" {
  name            = "${var.name_prefix}-api"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Lets `aws ecs execute-command` open a shell in a running task. Requires the
  # matching SSM channel permissions on the task role (modules/Backtest_Visualizer/iam-roles).
  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [var.security_group_id]

    # Load-bearing. See the header comment: false means no internet route at all
    # in a no-NAT VPC, and the tasks cannot even pull their own image.
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Give the app time to boot before the ALB starts failing it. Only valid when
  # a load balancer is attached.
  health_check_grace_period_seconds = var.target_group_arn == null ? null : var.health_check_grace_period

  # Rolling deploy with headroom: 200% lets the replacement task come up and go
  # healthy before the old one is drained, so the API stays available. This is
  # the opposite of the MQSMaster NLP service (0/100), which is a single
  # background worker where a gap costs nothing.
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    # CI/CD bumps the revision via `aws ecs update-service`, and desired_count is
    # owned by whoever scales the service, not by tfvars.
    ignore_changes = [task_definition, desired_count]

    precondition {
      condition     = var.assign_public_ip || var.has_nat_egress
      error_message = "assign_public_ip = false requires a NAT gateway. This VPC has none, so the task ENI would have no route to ECR, the external database, or Supabase, and every task would fail with CannotPullContainerError."
    }
  }
}
