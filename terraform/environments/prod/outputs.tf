###############################################################################
# Top-level outputs surfaced from modules.
###############################################################################

output "ecr_repository_url" {
  description = "Push images here. Used by CI/CD."
  value       = module.ecr_repository.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs_cluster.cluster_name
}

output "market_task_definition_family" {
  description = "Market task definition family. CI/CD registers new revisions here."
  value       = module.ecs_task_market.task_definition_family
}

output "market_task_definition_arn" {
  description = "Latest market task definition ARN."
  value       = module.ecs_task_market.task_definition_arn
}

output "market_container_name" {
  description = "Market container name (for CI/CD render step)."
  value       = module.ecs_task_market.container_name
}

output "refresh_task_definition_family" {
  description = "Weekly refresh task definition family. CI/CD registers new revisions here."
  value       = module.ecs_task_refresh.task_definition_family
}

output "refresh_container_name" {
  description = "Refresh container name (for CI/CD render step)."
  value       = module.ecs_task_refresh.container_name
}

output "nlp_task_definition_family" {
  description = "Always-on NLP task definition family."
  value       = module.ecs_service_nlp.task_definition_family
}

output "nlp_service_name" {
  description = "Always-on NLP ECS service name."
  value       = module.ecs_service_nlp.service_name
}

output "nlp_container_name" {
  description = "NLP container name (for CI/CD render step)."
  value       = module.ecs_service_nlp.container_name
}

output "log_group_name" {
  description = "CloudWatch log group for both tasks."
  value       = module.cloudwatch_logs.log_group_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials."
  value       = module.secrets_manager.db_secret_arn
}

output "api_secret_arn" {
  description = "Secrets Manager ARN for API keys."
  value       = module.secrets_manager.api_secret_arn
}

output "task_security_group_id" {
  description = "Security group attached to all Fargate tasks."
  value       = module.networking.task_security_group_id
}

output "task_subnet_ids" {
  description = "Subnets used by all Fargate tasks (default VPC)."
  value       = module.networking.subnet_ids
}

output "scheduler_role_arn" {
  description = "IAM role assumed by EventBridge to RunTask."
  value       = module.eventbridge_scheduler.scheduler_role_arn
}

output "market_schedule_name" {
  description = "Name of the daily market-open schedule."
  value       = module.eventbridge_scheduler.schedule_name
}

output "refresh_schedule_name" {
  description = "Name of the weekly backfill schedule."
  value       = module.eventbridge_scheduler.refresh_schedule_name
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint (host:port). Also written into the DB secret."
  value       = module.rds_postgres.db_endpoint
}

output "rds_address" {
  description = "RDS Postgres hostname."
  value       = module.rds_postgres.db_address
}

output "rds_instance_id" {
  description = "RDS instance identifier."
  value       = module.rds_postgres.db_instance_id
}

output "rds_security_group_id" {
  description = "Security group attached to the RDS instance."
  value       = module.rds_postgres.security_group_id
}
