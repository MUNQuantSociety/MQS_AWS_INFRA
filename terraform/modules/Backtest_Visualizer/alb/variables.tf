variable "name_prefix" {
  description = "Prefix applied to load balancer and target group names. ALB names are capped at 32 characters."
  type        = string

  validation {
    condition     = length("${var.name_prefix}-alb") <= 32
    error_message = "name_prefix is too long: '<name_prefix>-alb' must be at most 32 characters."
  }
}

variable "target_group_name_prefix" {
  description = "Prefix for the generated target group name. AWS caps this at 6 characters."
  type        = string
  default     = "btv-"

  validation {
    condition     = length(var.target_group_name_prefix) <= 6
    error_message = "target_group_name_prefix must be at most 6 characters: AWS appends a generated suffix and caps the full name at 32."
  }
}

variable "vpc_id" {
  description = "VPC the target group is registered in."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets the ALB is placed in. Requires at least two AZs."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the ALB."
  type        = string
}

variable "container_port" {
  description = "Port the API container listens on."
  type        = number
}

variable "health_check_path" {
  description = "Path the target group probes. Must return 200 without authentication."
  type        = string
  default     = "/api/v1/health"
}

variable "idle_timeout" {
  description = "Seconds an idle connection is held open. Raise if any endpoint streams progress over a long-lived connection."
  type        = number
  default     = 60
}

variable "deregistration_delay" {
  description = "Seconds to drain a target before deregistering."
  type        = number
  default     = 30
}

variable "enable_http_listener" {
  description = "Create the port 80 listener. When certificate_arn is set this listener redirects to HTTPS instead of forwarding."
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. null serves plaintext HTTP only."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "ELB security policy for the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Block deletion of the load balancer. Set true once the frontend depends on this endpoint."
  type        = bool
  default     = false
}
