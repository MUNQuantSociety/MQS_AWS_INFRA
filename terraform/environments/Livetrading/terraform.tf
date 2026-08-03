# Cloud backend for the Livetrading stack.
#
# Provider requirements are shared with the other stack and live in
# ../../shared/versions.tf, symlinked into this directory as versions.tf.
# Terraform merges the two `terraform` blocks.
#
# required_version is omitted on purpose so this workspace's own Terraform
# version governs. The real floor is 1.11.0 (write-only `value_wo` arguments in
# modules/Livetrading/ssm-parameters) -- see versions.tf.
#
# !! This stack's existing state lives in the workspace MQS_AWS_INFRA. Pointing
# it at MQS_AWS_INFRA_LIVE below binds it to a DIFFERENT workspace. Unless that
# state has already been migrated, the new workspace is empty and the next plan
# proposes creating a second copy of live infrastructure. Confirm the migration
# (or that MQS_AWS_INFRA_LIVE already holds this state) before running apply.

terraform {
  cloud {

    organization = "MQS"

    workspaces {
      name = "MQS_AWS_INFRA_LIVE"
    }
  }
}
