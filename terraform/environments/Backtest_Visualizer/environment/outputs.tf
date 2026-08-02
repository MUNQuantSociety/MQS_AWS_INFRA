output "api_base_url" {
  description = "Base URL for the API. Hand this to the frontend repo. null when enable_alb = false."
  value = var.enable_alb ? (
    var.certificate_arn == null
    ? "http://${module.alb[0].dns_name}"
    : "https://${module.alb[0].dns_name}"
  ) : null
}

output "alb_dns_name" {
  description = "ALB DNS name, for a Route 53 alias record."
  value       = var.enable_alb ? module.alb[0].dns_name : null
}

output "alb_zone_id" {
  description = "ALB hosted zone ID, for a Route 53 alias record."
  value       = var.enable_alb ? module.alb[0].zone_id : null
}

output "ecr_repository_url" {
  description = "Push target for the API image: docker push <url>:<tag>."
  value       = module.ecr_repository.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs_cluster.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs_service_api.service_name
}

output "task_definition_family" {
  description = "Task definition family CI/CD registers new revisions against."
  value       = module.ecs_service_api.task_definition_family
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs holding the ALB and the tasks."
  value       = module.networking.public_subnet_ids
}

output "service_security_group_id" {
  description = "Task security group. Referenced when allowing this service through a database firewall, though a no-NAT stack has no stable egress IP to allowlist."
  value       = module.networking.service_security_group_id
}

output "log_group_name" {
  description = "CloudWatch log group carrying container logs."
  value       = module.cloudwatch_logs.log_group_name
}

output "market_data_parameter_path" {
  description = "SSM path holding the external database credentials."
  value       = module.ssm_parameters.market_data_parameter_path
}

output "first_deploy_command" {
  description = "Scale the service up after the first image push."
  value       = "aws ecs update-service --cluster ${module.ecs_cluster.cluster_name} --service ${module.ecs_service_api.service_name} --desired-count 1 --region ${var.aws_region}"
}
