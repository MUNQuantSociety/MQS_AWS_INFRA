###############################################################################
# Top-level outputs surfaced from modules.
###############################################################################

output "ecr_repository_url" {
  description = "Push images here. Used by CI/CD."
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs_cluster.cluster_name
}

output "market_task_definition_family" {
  description = "Market task definition family. CI/CD registers new revisions here."
  value       = module.market_task.task_definition_family
}

output "market_task_definition_arn" {
  description = "Latest market task definition ARN."
  value       = module.market_task.task_definition_arn
}

output "market_container_name" {
  description = "Market container name (for CI/CD render step)."
  value       = module.market_task.container_name
}

output "nlp_task_definition_family" {
  description = "Always-on NLP task definition family."
  value       = module.nlp_service.task_definition_family
}

output "nlp_service_name" {
  description = "Always-on NLP ECS service name."
  value       = module.nlp_service.service_name
}

output "nlp_container_name" {
  description = "NLP container name (for CI/CD render step)."
  value       = module.nlp_service.container_name
}

output "log_group_name" {
  description = "CloudWatch log group for both tasks."
  value       = module.logging.log_group_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials."
  value       = module.secrets.db_secret_arn
}

output "api_secret_arn" {
  description = "Secrets Manager ARN for API keys."
  value       = module.secrets.api_secret_arn
}

output "task_security_group_id" {
  description = "Security group attached to all Fargate tasks."
  value       = module.network.task_security_group_id
}

output "task_subnet_ids" {
  description = "Subnets used by all Fargate tasks (default VPC)."
  value       = module.network.subnet_ids
}

output "scheduler_role_arn" {
  description = "IAM role assumed by EventBridge to RunTask."
  value       = module.scheduler.scheduler_role_arn
}
