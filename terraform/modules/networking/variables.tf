variable "name_prefix" {
  description = "Prefix applied to resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the task security group and endpoints attach to."
  type        = string
}

variable "aws_region" {
  description = "AWS region, used to build the S3 endpoint service name."
  type        = string
}

variable "private_route_table_ids" {
  description = "Private route tables the S3 gateway endpoint is associated with."
  type        = list(string)
}
