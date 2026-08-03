output "repository_url" {
  description = "ECR repository URL for docker push."
  value       = data.aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = data.aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "ECR repository name."
  value       = data.aws_ecr_repository.this.name
}
