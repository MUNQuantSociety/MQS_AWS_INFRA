# State backend.
#
# Left unconfigured on purpose: with no block here Terraform uses local state,
# which is what makes `terraform init` and `terraform validate` runnable without
# credentials or an HCP token. Local state is NOT acceptable for shared infra --
# pick one of the options below before the first real apply, then re-run
# `terraform init` to migrate.
#
# Option A -- HCP Terraform, matching MQS_AWS_INFRA. Needs a workspace created in
# the MQS org first, and `terraform login`. Note this must live in a `terraform`
# block; if you enable it, move it into terraform.tf or delete that file's
# duplicate settings.
#
# terraform {
#   cloud {
#     organization = "MQS"
#     workspaces {
#       name = "mqs-backtest-visualizer"
#     }
#   }
# }
#
# Option B -- S3 + native locking (no DynamoDB table needed on AWS provider 6.x).
#
# terraform {
#   backend "s3" {
#     bucket       = "mqs-terraform-state"
#     key          = "mqs-backtest-visualizer/prod/terraform.tfstate"
#     region       = "us-east-2"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
