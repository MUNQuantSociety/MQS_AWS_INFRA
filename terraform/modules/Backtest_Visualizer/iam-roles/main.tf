data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

###############################################################################
# Execution role -- used by the ECS agent, not by application code. Pulls the
# image, resolves SSM parameters and writes the log stream.
###############################################################################

resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS injects Parameter Store values with ssm:GetParameters (plural) -- that is
# the only action the agent needs, and it is scoped to this stack's parameters
# rather than the account's. kms:Decrypt is NOT required while the parameters use
# the AWS-managed alias/aws/ssm key; it becomes required, scoped to the key ARN,
# if a CMK is configured via the ssm-parameters module's kms_key_id input.
data "aws_iam_policy_document" "task_execution_secrets" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = var.parameter_arns
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name   = "${var.name_prefix}-task-exec-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

###############################################################################
# Task role -- assumed by the application itself.
#
# Starts with no permissions. The README's architecture puts run artifacts
# (CSV/parquet) in object storage in production; when that bucket exists, grant
# it here by setting artifact_bucket_arn rather than by attaching a managed
# policy.
###############################################################################

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "task_artifacts" {
  count = var.artifact_bucket_arn == null ? 0 : 1

  statement {
    sid       = "ListArtifactBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.artifact_bucket_arn]
  }

  statement {
    sid       = "ReadWriteArtifacts"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.artifact_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "task_artifacts" {
  count = var.artifact_bucket_arn == null ? 0 : 1

  name   = "${var.name_prefix}-task-artifacts"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_artifacts[0].json
}

# ECS Exec (`aws ecs execute-command`) is how you get a shell in a task that has
# no inbound path of its own. Off by default: it is a live production shell.
data "aws_iam_policy_document" "task_exec_ssm" {
  count = var.enable_ecs_exec ? 1 : 0

  statement {
    sid = "ECSExecSSMChannel"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_ssm" {
  count = var.enable_ecs_exec ? 1 : 0

  name   = "${var.name_prefix}-task-ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec_ssm[0].json
}
