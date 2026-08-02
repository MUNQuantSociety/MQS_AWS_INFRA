variable "name_prefix" {
  description = "Prefix applied to resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the RDS instance and its security group live in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (need >= 2 AZs)."
  type        = list(string)
}

variable "task_security_group_id" {
  description = "Security group of the Fargate tasks allowed to reach Postgres."
  type        = string
}

variable "db_username" {
  description = "Master username."
  type        = string
}

variable "db_password" {
  description = "Master password, passed as a write-only argument so it never lands in state. Min 8 chars; no /, @, \", or space."
  type        = string
  sensitive   = true
}

variable "db_password_version" {
  description = "Bump to push a new db_password to RDS. The password is write-only, so Terraform cannot detect that it changed -- only this counter triggers an update."
  type        = number
  default     = 1
}

variable "db_name" {
  description = "Initial database name created on the instance."
  type        = string
}

variable "port" {
  description = "Postgres port."
  type        = number
  default     = 5432
}

variable "engine_version" {
  description = "Postgres major (or major.minor) version."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class. db.t4g.medium = 2 vCPU / 4 GB (Graviton)."
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  description = "Initial gp3 storage in GB."
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Storage-autoscaling ceiling in GB. Set == allocated_storage to disable."
  type        = number
  default     = 300
}

variable "multi_az" {
  description = "Deploy a standby in a second AZ (doubles instance + storage cost)."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days. 0 disables backups."
  type        = number
  default     = 7
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of in the next maintenance window."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block terraform destroy / console delete. Set true for prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on delete. Set false for prod."
  type        = bool
  default     = true
}
