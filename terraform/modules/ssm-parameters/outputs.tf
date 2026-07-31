###############################################################################
# Outputs are ARNs and names only -- never parameter values.
#
# parameter_arns is keyed by the container environment variable name, which is
# what the root module needs to build the ECS `secrets` block. Keys are unique
# across the db/ and api/ paths, so the merge is collision-free.
###############################################################################

output "parameter_arns" {
  description = "Map of container environment variable name => SSM parameter ARN."
  value = merge(
    { for k, p in aws_ssm_parameter.db : k => p.arn },
    { for k, p in aws_ssm_parameter.api : k => p.arn },
  )
}

output "parameter_arn_list" {
  description = "Flat list of every parameter ARN, for scoping the task execution role policy."
  value = sort(concat(
    [for p in aws_ssm_parameter.db : p.arn],
    [for p in aws_ssm_parameter.api : p.arn],
  ))
}

output "db_parameter_path" {
  description = "Parent path holding the Postgres credential parameters."
  value       = "/${var.name_prefix}/db"
}

output "api_parameter_path" {
  description = "Parent path holding the third-party API key parameters."
  value       = "/${var.name_prefix}/api"
}
