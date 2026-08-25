variable "name_prefix" {
  description = "Prefix applied to IAM role names."
  type        = string
}

variable "parameter_arns" {
  description = "SSM Parameter Store ARNs the task execution role may read."
  type        = list(string)
}

variable "job_state_parameter_arns" {
  description = "SSM ARNs the task role (application code, via boto3 at runtime) may Get/PutParameter. Distinct from parameter_arns, which scopes the task EXECUTION role's plural ssm:GetParameters used for ECS secrets injection."
  type        = list(string)
  default     = []
}
