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

variable "market_data_parameter_version" {
  description = "Bump to push market_data_secret_values to AWS. Values are write-only, so Terraform cannot detect a changed value on its own -- only a change to this number triggers an update. Bumping overwrites any out-of-band rotation of the /market-data/* parameters."
  type        = number
  default     = 1
}

variable "api_parameter_version" {
  description = "Bump to push api_secret_values to AWS. Same semantics as market_data_parameter_version, scoped to the /api/* parameters."
  type        = number
  default     = 1
}

variable "market_data_secret_values" {
  description = <<EOT
Connection details for the EXTERNAL MQS market_data Postgres. This stack does
not provision a database -- the host must already exist and be reachable from
the internet (see ../../README.md on the no-NAT egress trade-off).

Point MARKET_DATA_USER at a read-only role: the visualizer must never write to
the trading tables.

Written only when market_data_parameter_version changes. Never stored in state.
EOT
  type = object({
    MARKET_DATA_HOST     = string
    MARKET_DATA_PORT     = string
    MARKET_DATA_DB       = string
    MARKET_DATA_USER     = string
    MARKET_DATA_PASSWORD = string
    MARKET_DATA_SSLMODE  = string
  })
  sensitive = true
}

variable "api_secret_values" {
  description = "Third-party credentials, written only when api_parameter_version changes. Never stored in state."
  type = object({
    FMP_API_KEY       = string
    SUPABASE_ANON_KEY = string
  })
  sensitive = true
}
