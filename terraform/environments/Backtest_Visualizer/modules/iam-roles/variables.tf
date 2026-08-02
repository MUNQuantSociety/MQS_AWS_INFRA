variable "name_prefix" {
  description = "Prefix applied to IAM role names."
  type        = string
}

variable "parameter_arns" {
  description = "SSM Parameter Store ARNs the task execution role may read."
  type        = list(string)
}

variable "artifact_bucket_arn" {
  description = "S3 bucket ARN for run artifacts (CSV/parquet). null grants the task role no S3 access."
  type        = string
  default     = null
}

variable "enable_ecs_exec" {
  description = "Grant the task role the SSM channel actions needed by `aws ecs execute-command`. Must be paired with enable_execute_command on the service."
  type        = bool
  default     = false
}
