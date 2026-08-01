###############################################################################
# GitHub Actions -> AWS via OIDC. Replaces long-lived IAM user access keys:
# the workflow exchanges a short-lived GitHub-signed token for STS credentials.
#
# The provider is ACCOUNT-GLOBAL -- AWS permits exactly one
# token.actions.githubusercontent.com provider per account. If another project
# already created it, this resource fails with EntityAlreadyExists; import it
# instead of creating a second one:
#
#   terraform import module.github_oidc.aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com
#
# thumbprint_list is deliberately omitted. AWS now validates the GitHub OIDC
# endpoint against its own trusted root CAs, so the field is Optional+Computed
# and pinning a leaf thumbprint only creates a rotation liability.
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Trust is scoped on two claims:
#   aud -- must be sts.amazonaws.com, the audience configure-aws-credentials
#          requests. Without this, any GitHub token for any audience is accepted.
#   sub -- pins the exact repo AND ref. `ref:refs/heads/main` covers both of
#          deploy.yml's triggers (push to main, and workflow_dispatch run on
#          main). A fork's tokens carry a different repo in sub and are rejected.
#
# Widening sub to `repo:<owner>/<repo>:*` would let ANY branch, tag or pull
# request in the repo assume this role -- including a PR branch from a fork.
# That is the standard over-grant; keep the ref pin unless a release-tag or
# multi-branch deploy is actually needed.
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in var.allowed_refs : "repo:${var.github_repository}:${ref}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name_prefix}-github-deploy"
  description        = "Assumed by GitHub Actions in ${var.github_repository} to build and deploy."
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Every statement below maps to a specific step in .github/workflows/deploy.yml.
# Several ECR/ECS actions have NO resource-level support in IAM and can only be
# granted on "*" -- those are called out inline so they are not mistaken for
# sloppy scoping.
data "aws_iam_policy_document" "deploy" {
  # amazon-ecr-login. GetAuthorizationToken is account-wide by design; IAM
  # offers no resource form for it.
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # docker build / push, scoped to the one repository.
  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }

  # describe-task-definition (both families) and register-task-definition.
  # Neither action supports resource-level permissions: task definition ARNs
  # include a revision number that does not exist yet at register time, so AWS
  # only accepts "*" here.
  statement {
    sid = "ECSTaskDefinitions"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  # amazon-ecs-deploy-task-definition, incl. wait-for-service-stability which
  # polls DescribeServices.
  statement {
    sid = "ECSDeployNLPService"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [var.nlp_service_arn]
  }

  # RegisterTaskDefinition re-submits executionRoleArn and taskRoleArn from the
  # downloaded definition, which counts as passing those roles. Without this the
  # market and NLP register steps fail with an opaque AccessDenied. The
  # PassedToService condition means these roles can only be handed to ECS.
  statement {
    sid       = "PassECSTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [var.task_execution_role_arn, var.task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.name_prefix}-github-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
