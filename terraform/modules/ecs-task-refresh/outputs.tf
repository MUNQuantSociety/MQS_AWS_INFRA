output "task_definition_arn" {
  description = "Refresh task definition ARN (revision pinned)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_arn_without_revision" {
  description = "Refresh task definition ARN without revision (family ref) so new revisions are picked up."
  value       = aws_ecs_task_definition.this.arn_without_revision
}

output "task_definition_family" {
  description = "Refresh task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Container name inside the refresh task definition."
  value       = var.container_name
}
