variable "name_prefix" {
  description = "Prefix applied to secret names (used as parent path)."
  type        = string
}

variable "recovery_window_in_days" {
  description = "Days secret remains recoverable after deletion. 0 disables recovery."
  type        = number
  default     = 7
}

variable "db_secret_values" {
  description = "Initial DB credentials. Console rotations are not overwritten."
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
  description = "Initial third-party API keys. Console rotations are not overwritten."
  type = object({
    FMP_API_KEY = string
    ALPHA_KEY   = string
    APIFY_KEY   = string
  })
  sensitive = true
}
