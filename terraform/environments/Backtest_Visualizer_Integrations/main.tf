# Integration resources for the existing manually created backtest ECS service.
# Separate state deliberately avoids adopting/recreating its network or service.
terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }
  backend "s3" {
    bucket       = "mqs-terraform-state"
    key          = "mqs-backtest-visualizer/integrations/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "mqs-backtest-visualizer", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  name           = "mqs-backtest-visualizer"
  repository_arn = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${local.name}"
  cluster_arn    = "arn:aws:ecs:${var.aws_region}:${local.account_id}:cluster/${local.name}"
  service_arn    = "arn:aws:ecs:${var.aws_region}:${local.account_id}:service/${local.name}/${local.name}-api"
  ecs_trust = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_s3_bucket" "strategies" {
  bucket = "${local.name}-strategies-${local.account_id}-${var.aws_region}"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "strategies" {
  bucket                  = aws_s3_bucket.strategies.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "strategies" {
  bucket = aws_s3_bucket.strategies.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "strategies" {
  bucket = aws_s3_bucket.strategies.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "strategies" {
  bucket = aws_s3_bucket.strategies.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_policy" "strategies" {
  bucket = aws_s3_bucket.strategies.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RequireTLS", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.strategies.arn, "${aws_s3_bucket.strategies.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = local.ecs_trust
}

resource "aws_iam_role_policy" "strategy_access" {
  name = "production-strategies"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.strategies.arn
        Condition = { StringLike = { "s3:prefix" = ["production/strategies/*"] } }
      },
      {
        Effect   = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.strategies.arn}/production/strategies/*"
      }
    ]
  })
}

resource "aws_iam_role" "github_deploy" {
  name = "${local.name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        # GitHub's production environment MUST restrict deployment to main.
        "token.actions.githubusercontent.com:sub" = "repo:MUNQuantSociety/mqs-backtest-visualizer:environment:production"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "deploy-existing-api"
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages"]
        Resource = local.repository_arn
      },
      { Effect = "Allow", Action = ["ecs:DescribeServices", "ecs:UpdateService"], Resource = local.service_arn },
      { Effect = "Allow", Action = ["ecs:DescribeTaskDefinition"], Resource = "*" },
      { Effect = "Allow", Action = ["ecs:RegisterTaskDefinition"], Resource = "*" },
      {
        Effect    = "Allow", Action = ["ecs:TagResource"]
        Resource  = "arn:aws:ecs:${var.aws_region}:${local.account_id}:task-definition/${local.name}:*"
        Condition = { StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" } }
      },
      {
        Effect    = "Allow", Action = ["ecs:ListTasks", "ecs:DescribeTasks"], Resource = "*"
        Condition = { ArnEquals = { "ecs:cluster" = local.cluster_arn } }
      },
      {
        Effect    = "Allow", Action = ["iam:PassRole"]
        Resource  = [aws_iam_role.task.arn, var.execution_role_arn]
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      }
    ]
  })
}
