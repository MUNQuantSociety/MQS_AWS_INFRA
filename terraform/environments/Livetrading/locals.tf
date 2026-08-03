locals {
  name_prefix = "${var.project_name}-${var.environment}"
  log_group   = "/ecs/${local.name_prefix}"
  image_uri   = "${module.ecr_repository.repository_url}:${var.image_tag}"

  # DB credentials written to Parameter Store. host/port are overridden with the
  # provisioned RDS endpoint so containers connect to our RDS, not an external
  # host. user/password/database/sslmode come from var.db_secret_values.
  # NOTE: parameter values are write-only, so Terraform cannot see that host
  # changed. If the RDS instance is ever replaced (new endpoint), this local
  # updates but nothing is pushed until db_parameter_version is bumped.
  db_secret_values = merge(var.db_secret_values, {
    host = module.rds_postgres.db_address
    port = tostring(module.rds_postgres.db_port)
  })

  # Secrets ECS injects into both task definitions. Each Parameter Store
  # parameter holds exactly one credential and its leaf name is the environment
  # variable name, so valueFrom is the bare parameter ARN -- Parameter Store has
  # no equivalent of the Secrets Manager `:json-key::` selector.
  #
  # The key list now lives in modules/Livetrading/ssm-parameters; adding a credential there
  # propagates here and into both task definitions automatically.
  container_secrets = [
    for name, arn in module.ssm_parameters.parameter_arns : {
      name      = name
      valueFrom = arn
    }
  ]
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
