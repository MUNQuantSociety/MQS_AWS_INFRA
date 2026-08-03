###############################################################################
# Shared Terraform settings.
#
# THIS IS ONE FILE, SYMLINKED INTO EACH ENVIRONMENT as versions.tf:
#
#   environments/Livetrading/versions.tf         -> ../../shared/versions.tf
#   environments/Backtest_Visualizer/versions.tf -> ../../shared/versions.tf
#
# Terraform reads every *.tf in the root module directory and follows symlinks,
# so each stack loads this file as if it were its own. A root module may contain
# several `terraform` blocks across files and Terraform merges them, which is why
# the provider requirements can live here while each stack keeps its own `cloud`
# block in its own terraform.tf.
#
# ---------------------------------------------------------------------------
# What is NOT here, and why
# ---------------------------------------------------------------------------
# The `cloud` block is per stack, because the two bind to different workspaces:
#
#   environments/Livetrading          -> MQS_AWS_INFRA_LIVE
#   environments/Backtest_Visualizer  -> MQS_AWS_INFRA_BTV
#
# `workspaces { name = ... }` takes a literal string -- it cannot be a variable
# -- so two different workspace names cannot come from one shared file. Keeping
# them separate is also what stops the two stacks sharing a state file: one
# workspace holds one state, and pointing both root modules at the same one
# would make each stack's plan propose destroying the other's resources.
#
# (If you ever do want the `cloud` block shared too, bind by `tags = ["mqs"]`
# instead of `name` and select the workspace per stack at init time. That is the
# only arrangement where one file covers both without sharing state.)
#
# ---------------------------------------------------------------------------
# required_version is deliberately omitted
# ---------------------------------------------------------------------------
# Nothing here pins the CLI/runtime version -- each HCP workspace's own Terraform
# version setting governs, which is the intent.
#
# The real floor is 1.11.0. Both stacks use write-only arguments
# (aws_ssm_parameter.value_wo in modules/*/ssm-parameters) and those were added
# in 1.11. A workspace set below that fails every run with "Unsupported
# argument: value_wo" -- an unenforced requirement, not an absent one.
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}
