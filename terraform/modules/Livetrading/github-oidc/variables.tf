variable "name_prefix" {
  description = "Prefix applied to IAM resource names."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, as \"owner/repo\". Must be the repo the workflow RUNS IN -- a fork's tokens carry a different value and are rejected."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in \"owner/repo\" form."
  }
}

variable "allowed_refs" {
  description = "GitHub OIDC subject suffixes permitted to assume the role, e.g. [\"ref:refs/heads/main\"]. Each is appended to \"repo:<owner>/<repo>:\". Widen with care -- \"*\" admits every branch, tag and pull request."
  type        = list(string)
  default     = ["ref:refs/heads/main", "ref:refs/heads/dev"]
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the workflow pushes images to."
  type        = string
}

variable "nlp_service_arn" {
  description = "ARN of the always-on NLP ECS service the workflow updates."
  type        = string
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN. Needed for iam:PassRole on RegisterTaskDefinition."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN. Needed for iam:PassRole on RegisterTaskDefinition."
  type        = string
}
