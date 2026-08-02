variable "name_prefix" {
  description = "Prefix used for task family and service name."
  type        = string
}

variable "container_name" {
  description = "Container name inside the NLP task definition."
  type        = string
  default     = "mqsmaster-nlp"
}

variable "image_uri" {
  description = "Full container image URI including tag."
  type        = string
}

variable "task_cpu" {
  description = "Fargate CPU units for the NLP task."
  type        = string
}

variable "task_memory" {
  description = "Fargate memory in MiB for the NLP task."
  type        = string
}

variable "desired_count" {
  description = "Always-on replica count."
  type        = number
  default     = 1
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN."
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID/ARN."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets used by the NLP task."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group used by the NLP task."
  type        = string
}

variable "assign_public_ip" {
  description = "Assign a public IP to the task ENI (required in public subnets)."
  type        = bool
  default     = true
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
