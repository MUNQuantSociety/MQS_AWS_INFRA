###############################################################################
# Core
###############################################################################

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Short project identifier used in resource names and tags."
  type        = string
  default     = "mqsmaster"
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)."
  type        = string
  default     = "prod"
}

###############################################################################
# ECR / image
###############################################################################

variable "ecr_repository_name" {
  description = "Name of the ECR repository for the MQSMaster container image."
  type        = string
  default     = "mqsmaster"
}

variable "image_tag" {
  description = "Image tag to deploy. CI/CD bumps this; Terraform ignores drift via lifecycle."
  type        = string
  default     = "latest"
}

###############################################################################
# Market task (scheduled)
###############################################################################

variable "market_task_cpu" {
  description = "Fargate market task CPU units. 1024 = 1 vCPU."
  type        = string
  default     = "2048"
}

variable "market_task_memory" {
  description = "Fargate market task memory in MiB."
  type        = string
  default     = "8192"
}

###############################################################################
# NLP service (always-on)
###############################################################################

variable "nlp_task_cpu" {
  description = <<EOT
Fargate NLP task CPU units. 512 = .5 vCPU is the practical floor for FinBERT;
256 also works (cheaper, slower batches).
EOT
  type        = string
  default     = "512"
}

variable "nlp_task_memory" {
  description = <<EOT
Fargate NLP task memory in MiB. FinBERT-base loaded ≈ 1-2 GB; 2048 is the
practical floor. Must form a valid Fargate CPU/memory pair.
EOT
  type        = string
  default     = "2048"
}

variable "nlp_desired_count" {
  description = "Number of always-on NLP service replicas."
  type        = number
  default     = 1
}

###############################################################################
# Logging
###############################################################################

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}

###############################################################################
# Schedule
###############################################################################

variable "schedule_expression" {
  description = <<EOT
EventBridge cron expression. When use_scheduler_timezone is true, this is
evaluated in schedule_timezone; otherwise in UTC.
Default fires Mon-Fri at 8:00 AM local in schedule_timezone.
EOT
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  description = "IANA timezone for EventBridge Scheduler (DST-aware)."
  type        = string
  default     = "America/St_Johns"
}

variable "use_scheduler_timezone" {
  description = "If true, use EventBridge Scheduler with IANA TZ. Otherwise UTC EventBridge Rule."
  type        = bool
  default     = true
}

###############################################################################
# Secrets (initial values — rotate via console after apply)
###############################################################################

variable "db_secret_values" {
  description = "Initial DB credentials stored in Secrets Manager."
  type = object({
    db_user  = string
    password = string
    host     = string
    port     = string
    database = string
    sslmode  = string
  })
  sensitive = true
  default = {
    db_user  = "admin"
    password = "REPLACE_ME"
    host     = "munquant.cair.mun.ca"
    port     = "25060"
    database = "mqsdb"
    sslmode  = "prefer"
  }
}

variable "api_secret_values" {
  description = "Initial API keys stored in Secrets Manager."
  type = object({
    FMP_API_KEY = string
    ALPHA_KEY   = string
    APIFY_KEY   = string
  })
  sensitive = true
  default = {
    FMP_API_KEY = "REPLACE_ME"
    ALPHA_KEY   = "REPLACE_ME"
    APIFY_KEY   = "REPLACE_ME"
  }
}
