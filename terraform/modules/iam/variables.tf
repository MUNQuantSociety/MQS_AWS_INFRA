variable "name_prefix" {
  description = "Prefix applied to IAM role names."
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the task execution role may read."
  type        = list(string)
}
