terraform {
  # >= 1.11 is required for write-only arguments (aws_ssm_parameter.value_wo in
  # modules/ssm-parameters). The HCP Terraform workspace's Terraform version
  # setting must also be >= 1.11 or remote plans fail.
  required_version = ">= 1.11.0"

  cloud {
    organization = "MQS"
    workspaces {
      name = "MQS_AWS_INFRA"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
}
