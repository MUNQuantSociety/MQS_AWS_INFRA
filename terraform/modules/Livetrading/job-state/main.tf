###############################################################################
# Plain (non-secret) SSM parameters holding operational job state -- e.g. the
# last successful run date of a periodic maintenance job. Deliberately NOT in
# modules/Livetrading/ssm-parameters: that module is purpose-built for
# SecureString credentials the app only ever reads, using write-only
# (value_wo) arguments. This is a plain String the app both reads AND writes
# at runtime, so Terraform only seeds the initial value and steps back.
###############################################################################

resource "aws_ssm_parameter" "market_data_prune_last_run" {
  name        = "/${var.name_prefix}/jobs/market_data_prune_last_run"
  description = "Last successful run date (YYYY-MM-DD) of the market_data retention prune. Written by the app at runtime via ssm:PutParameter; Terraform only seeds the initial value."
  type        = "String"
  tier        = "Standard"
  value       = var.seed_value

  lifecycle {
    # The app owns this value after creation -- a later apply must not stomp
    # a real run date back to the seed.
    ignore_changes = [value]
  }
}
