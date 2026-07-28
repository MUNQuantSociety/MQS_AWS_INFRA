output "scheduler_role_arn" {
  description = "IAM role used by EventBridge to call RunTask."
  value       = aws_iam_role.this.arn
}

output "schedule_name" {
  description = "Name of the market schedule resource (Scheduler or Rule)."
  value       = var.use_scheduler_timezone ? aws_scheduler_schedule.this[0].name : aws_cloudwatch_event_rule.this[0].name
}

output "refresh_schedule_name" {
  description = "Name of the weekly refresh schedule resource (Scheduler or Rule)."
  value       = var.use_scheduler_timezone ? aws_scheduler_schedule.refresh[0].name : aws_cloudwatch_event_rule.refresh[0].name
}
