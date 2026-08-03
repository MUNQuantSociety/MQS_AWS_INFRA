###############################################################################
# Credential storage backed by SSM Parameter Store SecureString parameters.
#
# One parameter per credential, never a JSON blob: ECS injects a Parameter Store
# value whole and has no equivalent of the Secrets Manager `:json-key::` ARN
# suffix, so a blob would arrive as one env var containing JSON.
#
#   /<name_prefix>/market-data/{MARKET_DATA_HOST,_PORT,_DB,_USER,_PASSWORD,_SSLMODE}
#   /<name_prefix>/api/{FMP_API_KEY,SUPABASE_ANON_KEY}
#
# The leaf name is deliberately identical to the environment variable name in
# .env.example, so src/core/config.py reads them with no special casing.
#
# Values use WRITE-ONLY arguments (`value_wo`): they are sent to AWS but never
# written to state or plan files. Terraform therefore cannot diff them -- an
# update fires only when the paired `value_wo_version` counter changes. That is
# what makes an out-of-band rotation (console, `aws ssm put-parameter`) safe from
# being clobbered by the next apply. To deliberately re-seed from tfvars, bump
# the counter.
#
# Write-only arguments require Terraform >= 1.11 (see the stack terraform.tf).
#
# Standard-tier SecureString parameters carry no storage charge, and at standard
# throughput no per-API-call charge either.
#
# NOTE: only the MARKET_DATA (external, read-only) database is modelled here.
# When the application-schema database lands (users, runs, metrics -- see the
# repo README), add its credentials as a third group rather than overloading
# these.
###############################################################################

locals {
  # for_each cannot take a value derived from a sensitive variable, and both
  # credential objects are sensitive. These literal key sets keep the for_each
  # argument non-sensitive while the parameter *values* stay sensitive. They must
  # stay in sync with the object types in variables.tf.
  market_data_keys = toset([
    "MARKET_DATA_HOST",
    "MARKET_DATA_PORT",
    "MARKET_DATA_DB",
    "MARKET_DATA_USER",
    "MARKET_DATA_PASSWORD",
    "MARKET_DATA_SSLMODE",
  ])

  api_keys = toset([
    "FMP_API_KEY",
    "SUPABASE_ANON_KEY",
  ])
}

resource "aws_ssm_parameter" "market_data" {
  for_each = local.market_data_keys

  name        = "/${var.name_prefix}/market-data/${each.key}"
  description = "External MQS market_data Postgres connection: ${each.key}"
  type        = "SecureString"
  tier        = var.parameter_tier

  # Never written to state or plan. Bump market_data_parameter_version to push.
  value_wo         = var.market_data_secret_values[each.key]
  value_wo_version = var.market_data_parameter_version

  # null selects the AWS-managed alias/aws/ssm key, which needs no kms:Decrypt
  # grant on the task execution role. Setting a CMK here means adding that grant
  # (see modules/Backtest_Visualizer/iam-roles) or tasks fail to start.
  key_id = var.kms_key_id
}

resource "aws_ssm_parameter" "api" {
  for_each = local.api_keys

  name        = "/${var.name_prefix}/api/${each.key}"
  description = "Backtest visualizer third-party credential: ${each.key}"
  type        = "SecureString"
  tier        = var.parameter_tier
  key_id      = var.kms_key_id

  # Never written to state or plan. Bump api_parameter_version to push.
  value_wo         = var.api_secret_values[each.key]
  value_wo_version = var.api_parameter_version
}
