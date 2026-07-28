output "scheduler_role_arn" {
  description = "IAM role used by EventBridge to call RunTask."
  value       = aws_iam_role.this.arn
}

output "schedule_name" {
  description = "Name of the schedule resource (Scheduler or Rule)."
  value       = var.use_scheduler_timezone ? aws_scheduler_schedule.this[0].name : aws_cloudwatch_event_rule.this[0].name
}
