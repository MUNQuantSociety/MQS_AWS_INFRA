variable "repository_name" {
  description = "ECR repository name. Must not already exist in the account/region."
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. IMMUTABLE blocks re-pushing an existing tag."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run a basic vulnerability scan on every push. No charge for basic scanning."
  type        = bool
  default     = true
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
