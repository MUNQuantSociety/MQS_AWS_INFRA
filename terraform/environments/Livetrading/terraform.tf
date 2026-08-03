# Terraform settings for the Livetrading stack.
#
# Provider requirements are declared inline here rather than shared with the
# Backtest_Visualizer stack. They were briefly held in a single
# terraform/shared/versions.tf symlinked into both directories; that saved one
# duplicated block at the cost of a root module whose configuration depended on
# a file outside its own directory. Two stacks that must be free to move their
# provider pins independently is the normal case, and duplicating six lines is
# cheaper than the coupling.
#
# The `cloud` block is per stack because the two bind to different workspaces --
# `workspaces { name = ... }` takes a literal string, and one workspace holds one
# state, so sharing it would make each stack's plan propose destroying the
# other's resources.
#
# This stack binds to MQS_AWS_INFRA_LIVE, which holds NO state as of 2026-08-03:
# zero resources, zero state versions, and no run has ever executed. An earlier
# local terraform.tfstate in this directory (serial=56) also tracks zero
# resources -- the stack was managed locally and then emptied, and nothing was
# ever migrated here. The first apply against this workspace is a full create of
# the whole stack, not an incremental change. See docs/operations.md.

terraform {
  # >= 1.11 is required for write-only arguments: aws_ssm_parameter.value_wo in
  # modules/Livetrading/ssm-parameters and aws_db_instance.password_wo in
  # modules/Livetrading/rds-postgres. This is a floor, not a pin -- the HCP
  # workspace's own Terraform version still governs which release runs, but a
  # workspace or local CLI below 1.11 now fails with a version error instead of
  # mid-plan with "Unsupported argument: value_wo".
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }

  cloud {

    organization = "MQS"

    workspaces {
      name = "MQS_AWS_INFRA_LIVE"
    }
  }
}
