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
# There is no `cloud` block. This stack was previously bound to the HCP
# workspace MQS_AWS_INFRA_BTV; state now lives in S3, configured in backend.tf
# under a different key from Livetrading's. That key separation is what keeps
# the two stacks' state independent, the job the separate workspaces used to do.
#
# A root module may declare only one backend or cloud block, so reinstating HCP
# means deleting the backend block in backend.tf, not adding a cloud block
# alongside it.

terraform {
  # >= 1.11 is required for write-only arguments (aws_ssm_parameter.value_wo in
  # modules/Backtest_Visualizer/ssm-parameters). A CLI below 1.11 fails with a
  # version error instead of mid-plan with "Unsupported argument: value_wo".
  #
  # backend.tf additionally relies on use_lockfile, which needs >= 1.10, so this
  # floor already covers it.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}
