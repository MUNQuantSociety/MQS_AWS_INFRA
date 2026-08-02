terraform {
  # >= 1.11 is required for write-only arguments (aws_ssm_parameter.value_wo in
  # modules/ssm-parameters).
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}
