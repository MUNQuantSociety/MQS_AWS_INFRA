locals {
  name_prefix = "${var.project_name}-${var.environment}"
  log_group   = "/ecs/${local.name_prefix}"
  image_uri   = "${module.ecr.repository_url}:${var.image_tag}"

  # DB secret written to Secrets Manager. host/port are overridden with the
  # provisioned RDS endpoint so containers connect to our RDS, not an external
  # host. user/password/database/sslmode come from var.db_secret_values.
  # NOTE: the secret version has ignore_changes = [secret_string]; if the RDS
  # instance is ever replaced (new endpoint), update the secret manually.
  db_secret_values = merge(var.db_secret_values, {
    host = module.rds.db_address
    port = tostring(module.rds.db_port)
  })

  # Single source of truth for the secrets ECS injects into both task
  # definitions. Adding a new key here propagates to both market + NLP tasks.
  container_secrets = concat(
    [for k in ["db_user", "password", "host", "port", "database", "sslmode"] : {
      name      = k
      valueFrom = "${module.secrets.db_secret_arn}:${k}::"
    }],
    [for k in ["FMP_API_KEY", "ALPHA_KEY", "APIFY_KEY"] : {
      name      = k
      valueFrom = "${module.secrets.api_secret_arn}:${k}::"
    }],
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
