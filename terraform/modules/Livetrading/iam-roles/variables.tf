variable "name_prefix" {
  description = "Prefix applied to IAM role names."
  type        = string
}

variable "parameter_arns" {
  description = "SSM Parameter Store ARNs the task execution role may read."
  type        = list(string)
}
