output "task_definition_arn" {
  description = "Market task definition ARN (revision pinned)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_arn_without_revision" {
  description = "Market task definition ARN without revision (family ref)."
  value       = aws_ecs_task_definition.this.arn_without_revision
}

output "task_definition_family" {
  description = "Market task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Container name inside the task definition."
  value       = var.container_name
}
