###############################################################################
# Weekly refresh/backfill Fargate task definition.
#
# Runs src/orchestrator/backfill/update/refresh.py once a week, outside market
# hours, then exits.
#
# This needs its own task definition rather than reusing the market family:
# refresh.py is NOT in start.sh's market_scripts array, so the market task never
# runs it. It is a standalone CLI entrypoint with its own arguments.
#
# --threads defaults to 4 in refresh.py, bounded by MQSDBConnector's
# ThreadedConnectionPool(maxconn=6). Exposed as var.refresh_threads so the two
# can be kept in step if either changes.
###############################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-refresh"
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

      # Direct entrypoint -- no start.sh, so none of the curl/jq bootstrap or
      # .env materialisation the market task needs. refresh.py reads its config
      # from the environment ECS injects directly.
      entryPoint = ["/app/MQS/bin/python"]
      command = concat(
        ["src/orchestrator/backfill/update/refresh.py"],
        ["--threads", tostring(var.refresh_threads)],
        ["--exchange", var.refresh_exchange],
        var.refresh_extra_args,
      )

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
          awslogs-stream-prefix = "refresh"
        }
      }
    }
  ])

  lifecycle {
    # Matches the market and NLP families: deploy.yml re-registers this family on
    # every push with a :<sha> image tag, so Terraform must not clobber it.
    #
    # This block is only safe BECAUSE deploy.yml registers the refresh family
    # (see the "Register refresh task revision" step). Without that step the
    # family would be frozen at whatever image_tag existed on first apply, with
    # nothing able to move it -- and the weekly job would quietly run stale code.
    # If that CI step is ever removed, remove this block too.
    #
    # Consequence: changing refresh_threads / refresh_extra_args needs a
    # temporary removal of this block to take effect. See
    # docs/operations.md#changing-refresh-arguments.
    ignore_changes = [container_definitions]
  }
}
