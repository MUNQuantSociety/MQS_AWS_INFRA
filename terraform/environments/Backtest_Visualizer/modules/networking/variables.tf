variable "name_prefix" {
  description = "Prefix applied to resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs. Must be the same length as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnets are required: an ALB needs subnets in two AZs."
  }
}

variable "availability_zones" {
  description = "AZ names, one per public subnet CIDR."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == length(var.public_subnet_cidrs)
    error_message = "availability_zones and public_subnet_cidrs must have the same length; otherwise subnets silently wrap across AZs."
  }
}

variable "container_port" {
  description = "Port the API container listens on. Opened from the ALB SG to the service SG."
  type        = number
}

variable "ingress_cidr_blocks" {
  description = "Source CIDRs allowed to reach the ALB. Narrow this to campus/office ranges if the API should not be world-reachable."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_http_listener" {
  description = "Open port 80 on the ALB. Set false once TLS is in place to force HTTPS."
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, port 443 is opened on the ALB security group. null leaves HTTPS closed."
  type        = string
  default     = null
}
