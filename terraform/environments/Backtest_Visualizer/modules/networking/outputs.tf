output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs. Both the ALB and the Fargate tasks live here (no private tier, no NAT)."
  value       = aws_subnet.public[*].id
}

output "route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public.id
}

output "alb_security_group_id" {
  description = "Security group attached to the ALB."
  value       = aws_security_group.alb.id
}

output "service_security_group_id" {
  description = "Security group attached to the Fargate tasks. Ingress from the ALB only; open egress."
  value       = aws_security_group.service.id
}
