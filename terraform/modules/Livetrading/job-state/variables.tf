variable "name_prefix" {
  description = "Prefix used for the parameter path."
  type        = string
}

variable "seed_value" {
  description = "Initial parameter value. \"1970-01-01\" makes the first-ever run prune immediately, establishing the retention window right away rather than deferring the first cleanup by a year."
  type        = string
  default     = "1970-01-01"
}
