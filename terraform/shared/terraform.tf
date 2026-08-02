###############################################################################
# Shared Terraform settings.
#
# THIS IS ONE FILE, SYMLINKED INTO EACH ENVIRONMENT as terraform.tf:
#
#   environments/Livetrading/terraform.tf         -> ../../shared/terraform.tf
#   environments/Backtest_Visualizer/terraform.tf -> ../../shared/terraform.tf
#
# Terraform reads every *.tf in the root module directory and follows symlinks,
# so each stack loads this file as if it were its own. Edit it here; both stacks
# pick the change up. `cloud` and `backend` blocks may only appear in a ROOT
# module, which is why this is symlinked rather than turned into a child module.
#
# ---------------------------------------------------------------------------
# required_version is deliberately omitted
# ---------------------------------------------------------------------------
# Nothing here pins the CLI/runtime version -- the HCP workspace's own Terraform
# version setting governs, which is the intent.
#
# The real floor is 1.11.0. Both stacks use write-only arguments
# (aws_ssm_parameter.value_wo in modules/*/ssm-parameters) and those were added
# in 1.11. If the workspace is set below that, every run fails with
# "Unsupported argument: value_wo" -- an unenforced requirement, not an absent
# one. Check the workspace's Terraform version before lowering it.
#
# ---------------------------------------------------------------------------
# !! ONE WORKSPACE HOLDS ONE STATE !!
# ---------------------------------------------------------------------------
# `workspaces { name = ... }` binds every stack that loads this file to the SAME
# workspace, and therefore to the SAME state file. These are two different root
# modules. Running apply in both is mutually destructive:
#
#   apply in Livetrading          -> state holds Livetrading's resources
#   apply in Backtest_Visualizer  -> Terraform sees resources that are not in
#                                    this configuration and plans to DESTROY
#                                    every one of them, then create its own
#   apply in Livetrading again    -> the same, in reverse
#
# To share this file safely across both stacks, swap `name` for `tags` so each
# stack binds to its own workspace while the configuration stays identical:
#
#   workspaces {
#     tags = ["mqs"]
#   }
#
# then select the workspace per stack at init time (TF_WORKSPACE, or the prompt
# `terraform init` gives you). See docs/operations.md.
###############################################################################

terraform {
  cloud {

    organization = "MQS"

    workspaces {
      name = "MQS_AWS_INFRA_LIVE"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}
