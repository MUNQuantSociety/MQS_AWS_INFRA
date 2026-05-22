variable "name_prefix" {
  description = "Prefix applied to the cluster name."
  type        = string
}

variable "container_insights_enabled" {
  description = "Enable ECS Container Insights for the cluster."
  type        = bool
  default     = true
}

variable "capacity_providers" {
  description = "Capacity providers available to the cluster."
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
}

variable "default_capacity_provider" {
  description = "Default capacity provider for tasks that omit one."
  type        = string
  default     = "FARGATE"
}
