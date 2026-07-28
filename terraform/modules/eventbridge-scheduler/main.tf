###############################################################################
# Cron triggers for the scheduled tasks.
#
# Two schedules:
#   `this`    - market task, daily before the open; exits when the market closes.
#   `refresh` - weekly backfill, outside market hours; runs once and exits.
#
# (`this` keeps its original resource name rather than being renamed to `market`
# so that already-applied workspaces need no state-migration shims.)
#
# Two paths:
#   - use_scheduler_timezone = true  -> EventBridge Scheduler with IANA TZ
#     (DST-aware: fires at same local clock time year-round).
#   - use_scheduler_timezone = false -> EventBridge Rule on UTC cron.
###############################################################################

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com", "events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "run_task" {
  statement {
    actions = ["ecs:RunTask"]
    resources = [
      "${var.task_definition_arn_without_revision}:*",
      "${var.refresh_task_definition_arn_without_revision}:*",
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.cluster_arn]
    }
  }

  statement {
    actions   = ["iam:PassRole"]
    resources = [var.task_execution_role_arn, var.task_role_arn]
  }
}

resource "aws_iam_role_policy" "run_task" {
  name   = "${var.name_prefix}-scheduler-runtask"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.run_task.json
}

resource "aws_scheduler_schedule" "this" {
  count = var.use_scheduler_timezone ? 1 : 0

  name        = "${var.name_prefix}-market-open"
  description = "Start MQSMaster market task daily before market open."
  group_name  = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = var.cluster_arn
    role_arn = aws_iam_role.this.arn

    ecs_parameters {
      task_definition_arn = var.task_definition_arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1
      platform_version    = "LATEST"

      network_configuration {
        subnets          = var.subnet_ids
        security_groups  = [var.security_group_id]
        assign_public_ip = var.assign_public_ip
      }
    }

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 600
    }
  }
}

resource "aws_scheduler_schedule" "refresh" {
  count = var.use_scheduler_timezone ? 1 : 0

  name        = "${var.name_prefix}-refresh"
  description = "Weekly ticker refresh + backfill, outside market hours."
  group_name  = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.refresh_schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = var.cluster_arn
    role_arn = aws_iam_role.this.arn

    ecs_parameters {
      task_definition_arn = var.refresh_task_definition_arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1
      platform_version    = "LATEST"

      network_configuration {
        subnets          = var.subnet_ids
        security_groups  = [var.security_group_id]
        assign_public_ip = var.assign_public_ip
      }
    }

    # Unlike the market task, a missed refresh is worth retrying -- it is a
    # weekly job and the next natural attempt is seven days out. The window is
    # wide because it runs outside market hours, so a late start is harmless.
    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  count = var.use_scheduler_timezone ? 0 : 1

  name                = "${var.name_prefix}-market-open"
  description         = "Start MQSMaster market task daily before market open (UTC)."
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "this" {
  count = var.use_scheduler_timezone ? 0 : 1

  rule     = aws_cloudwatch_event_rule.this[0].name
  arn      = var.cluster_arn
  role_arn = aws_iam_role.this.arn

  ecs_target {
    task_definition_arn = var.task_definition_arn_without_revision
    launch_type         = "FARGATE"
    task_count          = 1
    platform_version    = "LATEST"

    network_configuration {
      subnets          = var.subnet_ids
      security_groups  = [var.security_group_id]
      assign_public_ip = var.assign_public_ip
    }
  }
}

resource "aws_cloudwatch_event_rule" "refresh" {
  count = var.use_scheduler_timezone ? 0 : 1

  name                = "${var.name_prefix}-refresh"
  description         = "Weekly ticker refresh + backfill (UTC)."
  schedule_expression = var.refresh_schedule_expression
}

resource "aws_cloudwatch_event_target" "refresh" {
  count = var.use_scheduler_timezone ? 0 : 1

  rule     = aws_cloudwatch_event_rule.refresh[0].name
  arn      = var.cluster_arn
  role_arn = aws_iam_role.this.arn

  ecs_target {
    task_definition_arn = var.refresh_task_definition_arn_without_revision
    launch_type         = "FARGATE"
    task_count          = 1
    platform_version    = "LATEST"

    network_configuration {
      subnets          = var.subnet_ids
      security_groups  = [var.security_group_id]
      assign_public_ip = var.assign_public_ip
    }
  }
}
