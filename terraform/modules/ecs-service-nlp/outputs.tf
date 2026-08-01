output "task_definition_arn" {
  description = "NLP task definition ARN (revision pinned)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "NLP task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "service_name" {
  description = "NLP ECS service name."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "NLP ECS service ARN. Uses .arn, not .id -- IAM policies (the github-oidc deploy role) match on the long-form ARN, and .id is only incidentally equal to it."
  value       = aws_ecs_service.this.arn
}

output "container_name" {
  description = "NLP container name inside the task definition."
  value       = var.container_name
}
