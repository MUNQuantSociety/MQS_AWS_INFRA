output "vpc_id" {
  description = "Default VPC ID."
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "Default subnet IDs across AZs."
  value       = data.aws_subnets.default.ids
}

output "task_security_group_id" {
  description = "Egress-only security group ID for Fargate tasks."
  value       = aws_security_group.task.id
}
