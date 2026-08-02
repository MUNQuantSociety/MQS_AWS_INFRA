# State backend.
#
# There is no configuration in this file. This stack's `cloud` block lives in
# terraform.tf, bound to the HCP workspace MQS_AWS_INFRA_BTV -- separate from
# Livetrading's MQS_AWS_INFRA_LIVE, which is what keeps the two stacks' state
# files independent. A root module may declare only one backend or cloud block,
# so it must not be repeated here.
#
# Kept as an alternative: to take this stack off HCP entirely, delete the cloud
# block from terraform.tf and uncomment the S3 backend below.
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
