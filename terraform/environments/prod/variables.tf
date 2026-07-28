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
# RDS PostgreSQL
###############################################################################

variable "db_engine_version" {
  description = "Postgres major (or major.minor) version."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = <<EOT
RDS instance class. 4 GB RAM options (each pairs with 2 vCPU burstable):
  db.t4g.medium  (Graviton/ARM, cheapest 4 GB)  <- default
  db.t3.medium   (x86)
Bump to db.t4g.large / db.t3.large for 8 GB.
EOT
  type        = string
  default     = "db.t4g.medium"
}

variable "db_allocated_storage" {
  description = "Initial gp3 storage in GB (e.g. 100 or 300)."
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Storage-autoscaling ceiling in GB. Set == db_allocated_storage to disable autoscaling."
  type        = number
  default     = 300
}

variable "db_multi_az" {
  description = "Standby replica in a second AZ. Doubles instance + storage cost."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Automated backup retention in days. 0 disables backups."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Block destroy/delete of the DB. Set true for prod."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on delete. Set false for prod."
  type        = bool
  default     = true
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
# Refresh task (weekly backfill, outside market hours)
###############################################################################

variable "refresh_task_cpu" {
  description = <<EOT
Fargate refresh task CPU units. refresh.py is I/O bound (HTTP fetches plus DB
inserts), so 1 vCPU is ample.
EOT
  type        = string
  default     = "1024"
}

variable "refresh_task_memory" {
  description = "Fargate refresh task memory in MiB. Must form a valid Fargate CPU/memory pair."
  type        = string
  default     = "2048"
}

variable "refresh_threads" {
  description = <<EOT
Worker threads passed to refresh.py --threads.

Must stay below MQSDBConnector's ThreadedConnectionPool(maxconn=6) -- refresh.py
documents this constraint on the argument itself. 4 is the script's own default.
EOT
  type        = number
  default     = 4
}

variable "refresh_exchange" {
  description = "Exchange code passed to refresh.py --exchange."
  type        = string
  default     = "NYSE"
}

variable "refresh_extra_args" {
  description = <<EOT
Extra CLI arguments for refresh.py, e.g. ["--skip-backfill"]. Empty keeps the
script's defaults (last 30 days, 1-minute bars, --on-conflict ignore).
EOT
  type        = list(string)
  default     = []
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

variable "refresh_schedule_expression" {
  description = <<EOT
EventBridge cron expression for the weekly backfill, evaluated in
schedule_timezone (or UTC when use_scheduler_timezone is false).

Default fires Friday 18:30 local — a clear hour after the close. Newfoundland is
ET+1:30, so 16:00 ET is 17:30 local, and start.sh's monitor loop polls every 180s,
meaning the market task is gone within ~3 minutes of the close.

Recompute this offset if schedule_timezone changes.
EOT
  type        = string
  default     = "cron(30 18 ? * FRI *)"
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
  description = <<EOT
DB credentials stored in Secrets Manager and used to provision RDS.
  db_user / password / database -> become the RDS master user / password / db_name
  password  MUST be set in terraform.tfvars (min 8 chars; no /, @, ", or space)
  host      is IGNORED — overwritten with the RDS endpoint (see locals.tf)
  port      is the Postgres port RDS listens on (5432 standard)
EOT
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
    db_user  = "mqsadmin"
    password = "REPLACE_ME"
    host     = "" # ignored — RDS endpoint injected at apply time
    port     = "5432"
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
