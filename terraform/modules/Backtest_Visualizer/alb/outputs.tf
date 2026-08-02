output "dns_name" {
  description = "Public DNS name of the load balancer. This is the API base host."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Route 53 hosted zone ID of the ALB, for an alias record."
  value       = aws_lb.this.zone_id
}

output "arn" {
  description = "Load balancer ARN."
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "Target group ARN the ECS service registers into."
  value       = aws_lb_target_group.this.arn
}

output "listener_arns" {
  description = "ARNs of every created listener."
  value       = concat(aws_lb_listener.http[*].arn, aws_lb_listener.https[*].arn)
}
