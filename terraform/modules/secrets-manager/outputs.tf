output "db_secret_arn" {
  description = "ARN of the DB credentials secret."
  value       = aws_secretsmanager_secret.db.arn
}

output "api_secret_arn" {
  description = "ARN of the API keys secret."
  value       = aws_secretsmanager_secret.api.arn
}
