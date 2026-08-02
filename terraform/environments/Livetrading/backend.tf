# Uncomment and configure once an S3 backend bucket and DynamoDB lock table exist.
# terraform {
#   backend "s3" {
#     bucket         = "mqs-terraform-state"
#     key            = "mqsmaster/terraform.tfstate"
#     region         = "us-east-2"
#     dynamodb_table = "mqs-terraform-locks"
#     encrypt        = true
#   }
# }
