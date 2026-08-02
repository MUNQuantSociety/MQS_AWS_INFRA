# State backend.
#
# DECISION REQUIRED BEFORE THE FIRST APPLY.
#
# Left unconfigured on purpose: with no block here Terraform uses local state,
# which is what makes `terraform init` and `terraform validate` runnable without
# credentials or an HCP token. Local state is NOT acceptable for shared infra.
#
# Note the asymmetry with the sibling stack: environments/Livetrading declares a
# `cloud` block bound to the MQS_AWS_INFRA workspace, so it has remote state and
# remote runs. This stack does not, and the two must NOT share a workspace -- one
# workspace holds one state, and pointing both here would have each stack's plan
# propose destroying the other's resources.
#
# Option A -- HCP Terraform, matching Livetrading. Needs a SEPARATE workspace
# created in the MQS org first (e.g. MQS_BACKTEST_VISUALIZER), and
# `terraform login`. Note this must live in a `terraform` block; if you enable
# it, move it into terraform.tf or delete that file's duplicate settings.
#
# terraform {
#   cloud {
#     organization = "MQS"
#     workspaces {
#       name = "MQS_BACKTEST_VISUALIZER"
#     }
#   }
# }
#
# Option B -- S3 + native locking (no DynamoDB table needed on AWS provider 6.x).
#
# terraform {
#   backend "s3" {
#     bucket       = "mqs-terraform-state"
#     key          = "mqs-backtest-visualizer/Backtest_Visualizer/terraform.tfstate"
#     region       = "us-east-2"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
