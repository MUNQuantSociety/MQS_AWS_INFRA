# State backend for the Livetrading stack.
#
# State lives in S3, not HCP. The bucket is created out of band -- a backend
# cannot provision the bucket it stores its own state in, so it is a one-time
# manual step (see docs/operations.md#state-backend) rather than a resource in
# this configuration.
#
# use_lockfile = true is S3-native locking: Terraform writes a
# <key>.tflock object alongside the state and conditionally creates it, so two
# concurrent applies cannot both win. This replaces the DynamoDB lock table the
# earlier stub called for -- dynamodb_table is deprecated as of AWS provider
# 6.x, and the table was a second resource to create, pay for and keep in sync.
#
# The key is stack-specific. Backtest_Visualizer writes to a different key in
# the same bucket, which is what keeps the two states independent -- the same
# job the separate HCP workspaces used to do. Never point both at one key: one
# key holds one state, so each stack's plan would propose destroying the other's
# resources.

terraform {
  backend "s3" {
    bucket       = "mqs-terraform-state"
    key          = "mqsmaster/Livetrading/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
