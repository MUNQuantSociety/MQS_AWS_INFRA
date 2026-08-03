variable "log_group_name" {
  description = "CloudWatch log group name."
  type        = string
}

variable "retention_in_days" {
  description = "Retention in days for the log group. Ingestion is billed per GB; retention keeps stored volume bounded."
  type        = number
  default     = 14
}
