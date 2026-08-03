# Terraform settings for the Backtest_Visualizer stack.
#
# Provider requirements are declared inline here rather than shared with the
# Livetrading stack. They were briefly held in a single
# terraform/shared/versions.tf symlinked into both directories; that saved one
# duplicated block at the cost of a root module whose configuration depended on
# a file outside its own directory. Two stacks that must be free to move their
# provider pins independently is the normal case, and duplicating six lines is
# cheaper than the coupling.
#
# This workspace is separate from Livetrading's MQS_AWS_INFRA_LIVE, which is what
# keeps the two stacks' state files independent. It must exist before the first
# `terraform init` here.

terraform {
  # >= 1.11 is required for write-only arguments (aws_ssm_parameter.value_wo in
  # modules/Backtest_Visualizer/ssm-parameters). This is a floor, not a pin --
  # the HCP workspace's own Terraform version still governs which release runs,
  # but a workspace or local CLI below 1.11 now fails with a version error
  # instead of mid-plan with "Unsupported argument: value_wo".
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
      name = "MQS_AWS_INFRA_BTV"
    }
  }
}
