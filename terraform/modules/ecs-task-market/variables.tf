variable "name_prefix" {
  description = "Task definition family / name."
  type        = string
}

variable "container_name" {
  description = "Container name inside the task definition."
  type        = string
  default     = "mqsmaster"
}

variable "image_uri" {
  description = "Full container image URI including tag."
  type        = string
}

variable "task_cpu" {
  description = "Fargate CPU units. 1024 = 1 vCPU."
  type        = string
}

variable "task_memory" {
  description = "Fargate memory in MiB."
  type        = string
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN."
  type        = string
}

variable "container_secrets" {
  description = "Secrets list injected into the container (ECS task definition `secrets` block)."
  type = list(object({
    name      = string
    valueFrom = string
  }))
}

variable "log_group_name" {
  description = "CloudWatch log group name."
  type        = string
}

variable "aws_region" {
  description = "AWS region for log driver."
  type        = string
}
