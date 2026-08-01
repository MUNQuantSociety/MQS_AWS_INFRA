output "deploy_role_arn" {
  description = "ARN GitHub Actions assumes. Set as the AWS_DEPLOY_ROLE_ARN repository secret."
  value       = aws_iam_role.deploy.arn
}

output "deploy_role_name" {
  description = "Name of the GitHub Actions deploy role."
  value       = aws_iam_role.deploy.name
}

output "oidc_provider_arn" {
  description = "ARN of the account-global GitHub OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}
