###############################################################################
# Market-hours Fargate task definition. The only workload in this stack.
#
# Runs start.sh unmodified, so persistent_scripts (NLP/main_NLP.py) spawns
# alongside the market-hours scripts, for the duration of this session only --
# it is killed along with everything else when start.sh's watchdog shuts down
# at market close, and restarted fresh on the next scheduled run. There is no
# always-on NLP ECS Service in this stack (see #14/MQS_AWS_INFRA -- dropped for
# cost, and a later attempt to restore it as a separate Service was abandoned
# in favor of this folded-in approach instead).
#
# Previously this task's command stripped persistent_scripts=( ... ) out of
# start.sh via sed before exec'ing it, so NLP ran nowhere at all. That strip is
# gone now -- see git history if it ever needs to come back. Sizing note: NLP
# now shares task_cpu/task_memory with the market scripts in the SAME
# container, so if FinBERT starts contending for memory, raise task_memory
# (FinBERT wants roughly ~2 GB on top of whatever the market scripts alone
# need) rather than assuming it has headroom by default.
###############################################################################

locals {
  # Build the bash one-liner that materialises .env from ECS-injected env vars,
  # producing one `echo "NAME=$NAME"` per secret. Driven off var.container_secrets
  # so adding a secret in root flows through with no further edits here.
  #
  # format(), not a template string. The obvious spelling is a trap:
  #
  #   "echo \"${s.name}=$${s.name}\""   ->   echo "DB_HOST=${s.name}"
  #
  # `$$` escapes the interpolation, so the SECOND occurrence emits the literal
  # text `${s.name}` instead of the shell expansion `$DB_HOST` that was meant.
  # Every line of the generated .env then reads `NAME=${s.name}` and no real
  # credential ever lands in the file. format() has no template escaping, so the
  # `$` stays a plain character and bash does the expansion.
  env_writer = join("; ", [
    for s in var.container_secrets : format("echo \"%s=$%s\"", s.name, s.name)
  ])
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name_prefix
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

      # Dockerfile sets USER appuser; override to root so apt-get can install
      # curl+jq (required by start.sh) before exec'ing it. Cleaner long-term
      # fix: bake curl+jq into the Dockerfile runtime stage.
      user = "0"

      entryPoint = ["/bin/bash", "-c"]
      command = [
        join(" && ", [
          "apt-get update",
          "apt-get install -y --no-install-recommends curl jq ca-certificates",
          "rm -rf /var/lib/apt/lists/*",
          # start.sh sources .env (or falls back to empty .env.example which
          # would clobber the ECS-injected env vars). Materialise a real .env
          # from the secrets ECS already injected, so source preserves them.
          "{ ${local.env_writer}; } > .env",
          "exec ./start.sh",
        ])
      ]

      workingDirectory = "/app"

      environment = [
        { name = "PYTHONUNBUFFERED", value = "1" },
        { name = "PYTHON_VENV", value = "/app/MQS/bin/python" },
      ]

      secrets = var.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.container_name
        }
      }
    }
  ])

  lifecycle {
    # CI/CD updates the image tag via UpdateTaskDefinition. Avoid clobber on apply.
    ignore_changes = [container_definitions]
  }
}
