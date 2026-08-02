output "alb_security_group_id" {
  description = "Security group attached to the ALB."
  value       = aws_security_group.alb.id
}

output "service_security_group_id" {
  description = "Security group attached to the Fargate tasks. Ingress from the ALB only; open egress."
  value       = aws_security_group.service.id
}
