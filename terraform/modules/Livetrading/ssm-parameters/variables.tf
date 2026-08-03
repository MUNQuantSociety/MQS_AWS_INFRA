variable "name_prefix" {
  description = "Prefix applied to parameter names (used as the parent path segment)."
  type        = string
}

variable "parameter_tier" {
  description = "Parameter Store tier. Standard is free and caps values at 4 KB; Advanced costs $0.05/parameter/month."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Advanced", "Intelligent-Tiering"], var.parameter_tier)
    error_message = "parameter_tier must be Standard, Advanced or Intelligent-Tiering."
  }
}

variable "kms_key_id" {
  description = "KMS key ID/ARN encrypting the SecureString parameters. null uses the AWS-managed alias/aws/ssm key. Setting a CMK requires granting kms:Decrypt to the task execution role."
  type        = string
  default     = null
}

variable "db_parameter_version" {
  description = "Bump to push db_secret_values to AWS. Values are write-only, so Terraform cannot detect a changed value on its own -- only a change to this number triggers an update. Bumping overwrites any out-of-band rotation of the six /db/* parameters."
  type        = number
  default     = 1
}

variable "api_parameter_version" {
  description = "Bump to push api_secret_values to AWS. Same semantics as db_parameter_version, scoped to the three /api/* parameters."
  type        = number
  default     = 1
}

variable "db_secret_values" {
  description = "DB credentials, written only when db_parameter_version changes. Never stored in state."
  type = object({
    db_user  = string
    password = string
    host     = string
    port     = string
    database = string
    sslmode  = string
  })
  sensitive = true
}

variable "api_secret_values" {
  description = "Third-party API keys, written only when api_parameter_version changes. Never stored in state."
  type = object({
    FMP_API_KEY = string
    ALPHA_KEY   = string
    APIFY_KEY   = string
  })
  sensitive = true
}
