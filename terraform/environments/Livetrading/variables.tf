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
# CI/CD (GitHub Actions OIDC)
###############################################################################

variable "github_repository" {
  description = "Repository running deploy.yml, as \"owner/repo\". This is the repo holding MQSMaster's Dockerfile, not this infra repo."
  type        = string
  default     = "MUNQuantSociety/MQSMaster"
}

variable "github_allowed_refs" {
  description = "OIDC subject suffixes allowed to assume the deploy role. Defaults to main and dev: deploy.yml now lands on dev, and each ref covers both the push and workflow_dispatch triggers on that branch."
  type        = list(string)
  default     = ["ref:refs/heads/main", "ref:refs/heads/dev"]
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to spread subnets across. 2 is the floor and the default: RDS subnet groups require two AZs, and AZ count does not affect cost (single_nat_gateway caps NAT at one; subnets/route tables/IGW are free)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2: RDS subnet groups require two AZs."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs. Fargate tasks and RDS live here. Must have az_count entries."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == var.az_count
    error_message = "private_subnet_cidrs must have exactly az_count entries; otherwise subnets silently wrap across AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs. Carry only the IGW + NAT gateway. Must have az_count entries."
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == var.az_count
    error_message = "public_subnet_cidrs must have exactly az_count entries; otherwise subnets silently wrap across AZs."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (~$32/mo) instead of one per AZ (~$97/mo). Set false for HA egress."
  type        = bool
  default     = true
}

###############################################################################
# ECR / image
###############################################################################

variable "ecr_repository_name" {
  description = <<EOT
Name of the existing ECR repository holding the MQSMaster container image.

The repository is NOT created by Terraform -- it predates this config and is
adopted via a data source (see modules/Livetrading/ecr-repository). It must already exist in
aws_region, or plan fails with RepositoryNotFoundException.
EOT
  type        = string
  default     = "livetradingbot"
}

variable "image_tag" {
  description = <<EOT
Image tag to deploy. Must be a tag that already exists in ecr_repository_name --
ECS resolves it at task start, so a missing tag surfaces as
CannotPullContainerError rather than a Terraform error.

Pinned to a semantic tag rather than "latest": the repository is tagged
1.0.5-<n> and carries no "latest" tag. Bump this on each release.
EOT
  type        = string
  default     = "1.0.5-4"
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

Default fires Mon-Fri at 11:00 local, which with the America/St_Johns default is
the 09:30 ET market open (Newfoundland is ET+1:30).

This MUST NOT be set earlier than the open. start.sh's monitor loop evaluates
is_market_open on its first iteration, immediately after launching the market
scripts -- if the market is not yet open it SIGTERMs them all and exits. The
previous 08:00 default was 06:30 ET, three hours early, so the session ended
seconds after it began.
EOT
  type        = string
  default     = "cron(0 11 ? * MON-FRI *)"
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

variable "db_parameter_version" {
  description = <<EOT
Bump to push db_secret_values into SSM Parameter Store.
Parameter values are write-only (never stored in state or plan), so Terraform
cannot detect that you changed a value here -- only a change to this number
triggers an update. Bumping overwrites out-of-band rotations of /db/*.
EOT
  type        = number
  default     = 1
}

variable "api_parameter_version" {
  description = "Bump to push api_secret_values into SSM Parameter Store. Same semantics as db_parameter_version, scoped to /api/*."
  type        = number
  default     = 1
}

variable "db_secret_values" {
  description = <<EOT
DB credentials stored in SSM Parameter Store and used to provision RDS.
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
  description = "API keys stored in SSM Parameter Store."
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
