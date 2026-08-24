# State backend for the Backtest_Visualizer stack.
#
# State lives in S3, not HCP. The bucket is created out of band -- a backend
# cannot provision the bucket it stores its own state in, so it is a one-time
# manual step (see docs/operations.md#state-backend) rather than a resource in
# this configuration.
#
# use_lockfile = true is S3-native locking: Terraform writes a
# <key>.tflock object alongside the state and conditionally creates it, so two
# concurrent applies cannot both win. No DynamoDB table is involved;
# dynamodb_table is deprecated as of AWS provider 6.x.
#
# The key differs from Livetrading's, which is what keeps the two states
# independent -- the same job the separate HCP workspaces used to do. One key
# holds one state, so pointing both stacks at the same key would make each
# plan propose destroying the other's resources.

terraform {
  backend "s3" {
    bucket       = "mqs-terraform-state"
    key          = "mqs-backtest-visualizer/Backtest_Visualizer/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
