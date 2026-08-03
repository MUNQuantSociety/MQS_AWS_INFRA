locals {
  name_prefix = "${var.project_name}-${var.environment}"
  log_group   = "/ecs/${local.name_prefix}"
  image_uri   = "${module.ecr_repository.repository_url}:${var.image_tag}"

  # Two AZs is the floor: an ALB requires subnets in at least two of them.
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  # Secrets ECS injects into the task. Each SSM parameter holds exactly one
  # credential and its leaf name is the environment variable name, so valueFrom
  # is the bare parameter ARN -- Parameter Store has no equivalent of the Secrets
  # Manager `:json-key::` selector.
  #
  # The key list lives in modules/Backtest_Visualizer/ssm-parameters; adding a
  # credential there propagates into this list and into the NEXT task definition
  # revision Terraform writes.
  #
  # It does NOT reach a running task on its own. The task definition carries
  # ignore_changes = [container_definitions] and the service carries
  # ignore_changes = [task_definition], so after the first apply Terraform shows
  # no diff for a new credential and reports success while the service keeps
  # running the old revision. That is deliberate -- it exists so a CI deploy can
  # own the revision -- but this stack has no CI pipeline yet, so until one
  # exists a credential (or image_tag, or cors_origins) change has to be rolled
  # out by hand:
  #
  #   aws ecs update-service --cluster <name> --service <name> --force-new-deployment
  #
  # See modules/Backtest_Visualizer/ecs-service-api.
  container_secrets = [
    for name, arn in module.ssm_parameters.parameter_arns : {
      name      = name
      valueFrom = arn
    }
  ]

  # Non-secret configuration, mirroring .env.example. Anything with a credential
  # in it belongs in module.ssm_parameters instead -- values here are visible in
  # the task definition and in Terraform state.
  app_environment = merge(
    {
      APP_NAME                     = var.project_name
      APP_ENV                      = var.environment
      DEBUG                        = "false"
      LOG_LEVEL                    = var.log_level
      API_V1_PREFIX                = "/api/v1"
      CORS_ORIGINS                 = join(",", var.cors_origins)
      MARKET_TIMEZONE              = var.market_timezone
      MAX_CONCURRENT_RUNS_PER_USER = tostring(var.max_concurrent_runs_per_user)
      MAX_BACKTEST_WINDOW_DAYS     = tostring(var.max_backtest_window_days)
      RATE_LIMIT_PER_MINUTE        = tostring(var.rate_limit_per_minute)
      JWT_ALGORITHM                = "RS256"
      JWT_AUDIENCE                 = "authenticated"
      JWKS_CACHE_TTL_SECONDS       = "3600"
    },
    # Supabase URLs are public identifiers, not secrets -- only the anon key is
    # held in Parameter Store. Derived from the project ref so there is one place
    # to change when the project moves.
    var.supabase_project_ref == "" ? {} : {
      SUPABASE_URL         = "https://${var.supabase_project_ref}.supabase.co"
      SUPABASE_PROJECT_REF = var.supabase_project_ref
      SUPABASE_JWKS_URL    = "https://${var.supabase_project_ref}.supabase.co/auth/v1/.well-known/jwks.json"
      JWT_ISSUER           = "https://${var.supabase_project_ref}.supabase.co/auth/v1"
    },
    var.extra_environment,
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
