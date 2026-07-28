variable "name_prefix" {
  description = "Prefix used for scheduler/rule names."
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge cron/rate expression."
  type        = string
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
  description = "Task definition ARN without revision (family ref) so new revisions are picked up."
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
