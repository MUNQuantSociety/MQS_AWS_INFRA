###############################################################################
# Top-level outputs surfaced from modules.
###############################################################################

output "ecr_repository_url" {
  description = "Push images here. Used by CI/CD."
  value       = module.ecr_repository.repository_url
}

output "github_deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN secret on the repo running deploy.yml."
  value       = module.github_oidc.deploy_role_arn
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

output "db_parameter_path" {
  description = "SSM Parameter Store path holding the DB credentials."
  value       = module.ssm_parameters.db_parameter_path
}

output "api_parameter_path" {
  description = "SSM Parameter Store path holding the third-party API keys."
  value       = module.ssm_parameters.api_parameter_path
}

output "parameter_arns" {
  description = "Map of container environment variable name => SSM parameter ARN."
  value       = module.ssm_parameters.parameter_arns
}

output "task_security_group_id" {
  description = "Security group attached to all Fargate tasks."
  value       = module.networking.task_security_group_id
}

output "task_subnet_ids" {
  description = "Private subnets used by all Fargate tasks."
  value       = module.vpc.private_subnets
}

output "vpc_id" {
  description = "Dedicated VPC ID."
  value       = module.vpc.vpc_id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs providing egress for the private subnets."
  value       = module.vpc.natgw_ids
}

output "scheduler_role_arn" {
  description = "IAM role assumed by EventBridge to RunTask."
  value       = module.eventbridge_scheduler.scheduler_role_arn
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
