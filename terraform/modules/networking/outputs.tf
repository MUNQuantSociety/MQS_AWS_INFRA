output "task_security_group_id" {
  description = "Egress-only security group ID for Fargate tasks."
  value       = aws_security_group.task.id
}

output "s3_vpc_endpoint_id" {
  description = "S3 gateway endpoint ID (keeps ECR layer pulls off the NAT gateway)."
  value       = aws_vpc_endpoint.s3.id
}
