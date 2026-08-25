output "parameter_arn" {
  description = "ARN of the market_data prune last-run SSM parameter. Not sensitive -- a date, not a credential."
  value       = aws_ssm_parameter.market_data_prune_last_run.arn
}

output "parameter_name" {
  description = "Name (path) of the market_data prune last-run SSM parameter."
  value       = aws_ssm_parameter.market_data_prune_last_run.name
}
