###############################################################################
# Credential storage backed by SSM Parameter Store SecureString parameters.
#
# Previously this module created two Secrets Manager secrets holding JSON blobs,
# and ECS pulled individual fields out with the `:json-key::` ARN suffix. That
# suffix is a Secrets Manager feature only -- Parameter Store injects the whole
# parameter value with no key extraction -- so each credential is now its own
# parameter. Two secrets become nine parameters, laid out as:
#
#   /<name_prefix>/db/{db_user,password,host,port,database,sslmode}
#   /<name_prefix>/api/{FMP_API_KEY,ALPHA_KEY,APIFY_KEY}
#
# The leaf name is deliberately identical to the environment variable the
# container expects, so the app side (load_dotenv + os.getenv) is unchanged.
#
# Values are supplied as WRITE-ONLY arguments (`value_wo`): they are sent to AWS
# but never persisted to state or plan files. This is strictly better than the
# old Secrets Manager arrangement, where `secret_string` sat in state in
# plaintext for anyone who could read the state file.
#
# Because Terraform cannot see a write-only value, it cannot diff one either --
# an update fires only when the paired `value_wo_version` changes. That gives the
# rotation guarantee `ignore_changes = [value]` used to provide, for free: a
# console/CLI rotation is never clobbered by a later apply. To deliberately
# re-seed from terraform.tfvars, bump db_parameter_version / api_parameter_version.
#
# Write-only arguments require Terraform >= 1.11 (see environments/prod/terraform.tf).
#
# Standard-tier SecureString parameters carry no storage charge, and at standard
# throughput there is no per-API-call charge either.
###############################################################################

locals {
  # for_each cannot take a value derived from a sensitive variable, and both
  # credential objects are marked sensitive. These literal key sets keep the
  # for_each argument non-sensitive while the parameter *values* stay sensitive.
  # They must stay in sync with the object types in variables.tf.
  db_keys  = toset(["db_user", "password", "host", "port", "database", "sslmode"])
  api_keys = toset(["FMP_API_KEY", "ALPHA_KEY", "APIFY_KEY"])
}

resource "aws_ssm_parameter" "db" {
  for_each = local.db_keys

  name        = "/${var.name_prefix}/db/${each.key}"
  description = "MQSMaster Postgres credentials: ${each.key}"
  type        = "SecureString"
  tier        = var.parameter_tier

  # Never written to state or plan. Bump db_parameter_version to push a new value.
  value_wo         = var.db_secret_values[each.key]
  value_wo_version = var.db_parameter_version

  # null selects the AWS-managed alias/aws/ssm key, which needs no kms:Decrypt
  # grant on the task execution role. Setting a CMK here means adding that grant
  # (see modules/iam-roles) or tasks fail to start.
  key_id = var.kms_key_id
}

resource "aws_ssm_parameter" "api" {
  for_each = local.api_keys

  name        = "/${var.name_prefix}/api/${each.key}"
  description = "MQSMaster third-party API key: ${each.key}"
  type        = "SecureString"
  tier        = var.parameter_tier
  key_id      = var.kms_key_id

  # Never written to state or plan. Bump api_parameter_version to push a new value.
  value_wo         = var.api_secret_values[each.key]
  value_wo_version = var.api_parameter_version
}
