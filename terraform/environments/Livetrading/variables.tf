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
  description = "Private subnet CIDRs. RDS always lives here; the Fargate task joins it when task_in_public_subnet is false. Must have az_count entries."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == var.az_count
    error_message = "private_subnet_cidrs must have exactly az_count entries; otherwise subnets silently wrap across AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs. Carry the IGW, and the Fargate task itself when task_in_public_subnet is true. Must have az_count entries."
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == var.az_count
    error_message = "public_subnet_cidrs must have exactly az_count entries; otherwise subnets silently wrap across AZs."
  }
}

variable "task_in_public_subnet" {
  description = <<EOT
Run the scheduled Fargate task in the public subnets with a public IP on its
ENI, egressing straight out the internet gateway. RDS stays private either way.

true (default) creates NO NAT gateway -- the private tier would then hold only
RDS, which makes no outbound connections, so a gateway there routes nothing for
~$32/mo. Security is unchanged: the task SG has zero ingress rules, so the public
IP is an egress address and not an inbound path, and RDS keeps no public
endpoint.

THE COST OF true IS THE SOURCE ADDRESS. Fargate cannot hold an Elastic IP; a
public-subnet task gets a fresh public IP at every start, so outbound calls to
FMP / Alpha Vantage / Apify have no stable source. Set this false if any provider
IP-allowlists this stack -- that puts the task back in the private subnets behind
a NAT gateway with a stable EIP, and restores the ~$32/mo.

Flipping this replaces nothing durable: the task definition is unchanged and the
scheduler is updated in place, so the next scheduled run picks up the new
placement. There is no data to migrate.
EOT
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (~$32/mo) instead of one per AZ (~$97/mo). Set false for HA egress. Only has an effect when task_in_public_subnet is false -- otherwise no NAT gateway is created at all."
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
RDS instance class. All t-family classes are 2 vCPU burstable; they differ in RAM:
  db.t4g.small   (Graviton/ARM, 2 GB)  <- default
  db.t3.small    (x86, 2 GB)
  db.t4g.medium  (Graviton/ARM, 4 GB)
  db.t4g.large   (Graviton/ARM, 8 GB)

2 GB is the floor that still leaves Postgres a usable shared_buffers after the
engine's own overhead. If pg_stat_database shows the cache hit ratio dropping or
queries start spilling to disk, move to db.t4g.medium -- an instance class change
is an in-place modify with one reboot, not a replacement, so it is cheap to undo.
EOT
  type        = string
  default     = "db.t4g.small"
}

variable "db_allocated_storage" {
  description = "Initial gp3 storage in GB. Storage can be grown in place but NEVER shrunk -- reducing it later means a dump/restore into a new instance, so start low and let autoscaling raise it."
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Storage-autoscaling ceiling in GB. Set == db_allocated_storage to disable autoscaling."
  type        = number
  default     = 200

  validation {
    condition     = var.db_max_allocated_storage >= var.db_allocated_storage
    error_message = "db_max_allocated_storage must be >= db_allocated_storage. RDS rejects an autoscaling ceiling below the allocated size."
  }
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
  description = <<EOT
Block destroy/delete of the DB instance.

Defaults to true because this stack's `environment` defaults to "prod" and the
safe value must not live only in terraform.tfvars.example -- deploying via
TF_VAR_* environment variables (see .env.example) never reads that file, and an
unprotected production database is not an acceptable default.

Consequence, and the point: `terraform destroy` FAILS until this is set false
and applied. Invert it, with db_skip_final_snapshot, for a throwaway environment.
EOT
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = <<EOT
Skip the final snapshot when the DB instance is deleted.

Defaults to false (i.e. a snapshot IS taken) for the same reason as
db_deletion_protection. The snapshot is named <name_prefix>-postgres-final; that
name is fixed, so delete or rename an old one before a second teardown or RDS
rejects the delete.
EOT
  type        = bool
  default     = false
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
# NLP task (always-on)
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

  # The REPLACE_ME default exists so the module parses without credentials. It
  # must never reach AWS: without this check a forgotten terraform.tfvars
  # applies cleanly and provisions RDS with the literal master password
  # "REPLACE_ME", plus six SSM parameters holding placeholder text that the
  # containers then fail against at runtime. Fail at plan time instead.
  # host is exempt — "" is its correct value, overwritten in locals.tf.
  validation {
    condition = !contains(
      [for k, v in var.db_secret_values : v if k != "host"],
      "REPLACE_ME"
    )
    error_message = "db_secret_values still holds REPLACE_ME. Set real values via terraform.tfvars or TF_VAR_db_secret_values before applying."
  }

  validation {
    condition     = length(var.db_secret_values.password) >= 8
    error_message = "db_secret_values.password must be at least 8 characters — the RDS master password minimum."
  }

  validation {
    condition     = !can(regex("[/@\" ]", var.db_secret_values.password))
    error_message = "db_secret_values.password must not contain /, @, \" or a space. RDS rejects those characters."
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

  # All three are required by the object type, so none can be omitted — but a
  # forgotten tfvars would store the placeholder string as the API key and the
  # failure would only surface as a 401 from the vendor at runtime.
  validation {
    condition = !contains([
      var.api_secret_values.FMP_API_KEY,
      var.api_secret_values.ALPHA_KEY,
      var.api_secret_values.APIFY_KEY,
    ], "REPLACE_ME")
    error_message = "api_secret_values still holds REPLACE_ME. Set real values via terraform.tfvars or TF_VAR_api_secret_values before applying."
  }
}
