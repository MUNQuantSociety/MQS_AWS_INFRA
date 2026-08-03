variable "name_prefix" {
  description = "Prefix applied to security group names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups are created in. Supplied by the registry VPC module in the root composition."
  type        = string
}

variable "container_port" {
  description = "Port the API container listens on. Opened from the ALB group to the service group."
  type        = number
}

variable "ingress_cidr_blocks" {
  description = "Source CIDRs allowed to reach the ALB. Narrow this to campus/office ranges if the API should not be world-reachable."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_http_listener" {
  description = "Open port 80 on the ALB group. Set false once TLS is in place to force HTTPS."
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, port 443 is opened on the ALB group. null leaves HTTPS closed."
  type        = string
  default     = null
}
