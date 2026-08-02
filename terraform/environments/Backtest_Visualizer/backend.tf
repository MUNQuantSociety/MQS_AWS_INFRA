# State backend.
#
# There is no configuration in this file. The `cloud` block now comes from
# ../../shared/terraform.tf, symlinked into this directory as terraform.tf --
# a root module may declare only one, so it must not be repeated here.
#
# !! READ THIS BEFORE THE FIRST APPLY !!
#
# The shared file binds by workspace NAME, which means this stack and
# environments/Livetrading resolve to the SAME HCP workspace and therefore the
# same state file. They are two different root modules. Applying both in turn is
# mutually destructive: whichever runs second finds a state full of resources
# that its own configuration does not declare, and plans to destroy every one of
# them.
#
# The fix is one line in ../../shared/terraform.tf -- bind by tag instead of
# name, so the file stays shared while each stack gets its own workspace:
#
#   workspaces {
#     tags = ["mqs"]
#   }
#
# Then `terraform init` in each directory selects (or creates) that stack's own
# workspace.
#
# If you would rather keep this stack off HCP entirely, delete the symlinked
# terraform.tf here, give this directory its own copy without a `cloud` block,
# and uncomment the S3 backend below.
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
