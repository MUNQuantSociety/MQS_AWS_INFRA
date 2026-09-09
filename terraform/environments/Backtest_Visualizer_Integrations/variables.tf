variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "execution_role_arn" {
  description = "Existing task execution role. No role policy is modified by this stack."
  type        = string
  default     = "arn:aws:iam::855603407903:role/service-role/ecsTaskExecutionRole"
}
