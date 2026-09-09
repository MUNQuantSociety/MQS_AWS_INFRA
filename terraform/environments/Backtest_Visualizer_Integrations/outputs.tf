output "strategy_bucket_name" { value = aws_s3_bucket.strategies.id }
output "strategy_task_role_arn" { value = aws_iam_role.task.arn }
output "github_deploy_role_arn" { value = aws_iam_role.github_deploy.arn }
