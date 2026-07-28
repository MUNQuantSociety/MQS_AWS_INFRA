variable "name_prefix" {
  description = "Prefix used for scheduler/rule names."
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge cron/rate expression for the market task."
  type        = string
}

variable "refresh_schedule_expression" {
  description = <<EOT
EventBridge cron/rate expression for the weekly refresh task, evaluated in
schedule_timezone (or UTC when use_scheduler_timezone is false).

Default fires Friday 18:30 local. With the America/St_Johns default that is a
clear hour after the market closes: Newfoundland is ET+1:30, so the 16:00 ET
close is 17:30 local, and start.sh's monitor loop polls is_market_open every
180s -- the market task is gone within ~3 minutes of the close.

This offset is timezone-specific. Recompute it if schedule_timezone changes.
EOT
  type        = string
  default     = "cron(30 18 ? * FRI *)"
}

variable "schedule_timezone" {
  description = "IANA timezone for EventBridge Scheduler (e.g. America/St_Johns)."
  type        = string
  default     = "UTC"
}

variable "use_scheduler_timezone" {
  description = <<EOT
If true, use EventBridge Scheduler with the given IANA timezone (DST-aware).
If false, use a classic EventBridge Rule on the UTC schedule_expression.
EOT
  type        = bool
  default     = true
}

variable "cluster_arn" {
  description = "ECS cluster ARN to run the task in."
  type        = string
}

variable "task_definition_arn_without_revision" {
  description = "Market task definition ARN without revision (family ref) so new revisions are picked up."
  type        = string
}

variable "refresh_task_definition_arn_without_revision" {
  description = "Refresh task definition ARN without revision (family ref)."
  type        = string
}

variable "task_execution_role_arn" {
  description = "Task execution role ARN (needed for iam:PassRole)."
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN (needed for iam:PassRole)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets used by the scheduled task."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group used by the scheduled task."
  type        = string
}

variable "assign_public_ip" {
  description = "Assign a public IP to the task ENI."
  type        = bool
  default     = true
}
