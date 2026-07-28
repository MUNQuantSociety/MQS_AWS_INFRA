output "db_address" {
  description = "RDS endpoint hostname (no port). Feeds the DB secret 'host'."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port. Feeds the DB secret 'port'."
  value       = aws_db_instance.this.port
}

output "db_endpoint" {
  description = "RDS endpoint host:port."
  value       = aws_db_instance.this.endpoint
}

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "security_group_id" {
  description = "Security group attached to the RDS instance."
  value       = aws_security_group.db.id
}
