variable "repository_name" {
  description = "ECR repository name."
  type        = string
}

variable "tagged_image_retention_count" {
  description = "Number of tagged images to keep before expiry."
  type        = number
  default     = 10
}

variable "untagged_image_retention_days" {
  description = "Days to keep untagged images before expiry."
  type        = number
  default     = 7
}
