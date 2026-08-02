# Cloud backend for the Backtest_Visualizer stack.
#
# Provider requirements are shared with the other stack and live in
# ../../shared/versions.tf, symlinked into this directory as versions.tf.
# Terraform merges the two `terraform` blocks.
#
# required_version is omitted on purpose so this workspace's own Terraform
# version governs. The real floor is 1.11.0 (write-only `value_wo` arguments in
# modules/Backtest_Visualizer/ssm-parameters) -- see versions.tf.
#
# This workspace is separate from Livetrading's MQS_AWS_INFRA_LIVE, which is
# what keeps the two stacks' state files independent.

terraform {
  cloud {

    organization = "MQS"

    workspaces {
      name = "MQS_AWS_INFRA_BTV"
    }
  }
}
