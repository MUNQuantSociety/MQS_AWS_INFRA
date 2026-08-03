###############################################################################
# Core
###############################################################################

variable "aws_region" {
  description = "AWS region for all resources. Matches MQS_AWS_INFRA so the external market_data host is in-region."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Short project identifier used in resource names and tags. Kept short because ALB and target group names cap at 32 characters."
  type        = string
  default     = "mqs-btv"
}

variable "environment" {
  description = "Deployment environment. Only \"dev\" may run the ALB without a TLS certificate -- see certificate_arn."
  type        = string
  default     = "prod"

  # Closed set on purpose: certificate_arn's validation keys off this string, so
  # a typo ("prd", "Dev") must not silently land in the lenient branch and serve
  # plaintext. Anything unrecognised fails the plan instead.
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

###############################################################################
# Networking
#
# There is no NAT gateway and no private subnet tier. See modules/Backtest_Visualizer/security-groups and the vpc module in main.tf for
# why, and ./README.md for the egress-IP consequence.
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap the MQSMaster VPC (10.0.0.0/16) if the two are ever peered."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs. Both the ALB and the Fargate tasks live here. Two AZs minimum -- an ALB requires it."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]

  # locals.azs is sliced to this list's length, so one CIDR means one AZ. Without
  # this the apply gets as far as creating the VPC, subnets and security groups
  # and then fails at aws_lb.this with "At least two subnets in two different
  # Availability Zones must be specified", leaving a half-built stack. The old
  # hand-rolled networking module enforced this; the registry VPC module has no
  # equivalent, so it belongs here.
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "public_subnet_cidrs needs at least two entries: an Application Load Balancer requires subnets in at least two availability zones."
  }
}

variable "alb_ingress_cidr_blocks" {
  description = "Source CIDRs allowed to reach the ALB on 443 (and on 80 when enable_http_listener is true). World-open by default because the frontend is Vercel-hosted with no fixed egress range; narrow it if the API should not be world-reachable."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# Load balancer
###############################################################################

variable "enable_alb" {
  description = <<EOT
Create an Application Load Balancer (~$16/mo + LCUs) in front of the service.

On by default because a Fargate task's public IP changes on every deployment,
leaving no stable endpoint for the frontend.

Setting this false leaves the API with NO INBOUND PATH AT ALL -- it does not
fall back to reaching the task on its public IP. The task security group's only
ingress rule references the ALB security group, so with no ALB nothing can
connect; the public IP carries egress only. Use false when you want the task
running and observable through CloudWatch Logs / `aws ecs execute-command`
without exposing an endpoint, not as a cheaper way to serve traffic.
EOT
  type        = bool
  default     = true
}

variable "enable_http_listener" {
  description = <<EOT
Open port 80 on the ALB.

Off by default. With a certificate present a port 80 listener only issues a 301
to HTTPS -- it never serves plaintext -- so turning this on is a convenience for
visitors typing a bare hostname.

On environment = "dev" with no certificate this is the only way to serve at all,
and it must be set true explicitly: plaintext is never implicit.
EOT
  type        = bool
  default     = false

  # The ALB module refuses to build a load balancer with no listeners
  # (modules/Backtest_Visualizer/alb/main.tf). That combination is reachable
  # here only in the dev-without-cert case, so catch it with a message that
  # names the fix instead of letting the module's generic one surface.
  validation {
    condition     = !var.enable_alb || var.certificate_arn != null || var.enable_http_listener
    error_message = "The ALB would have no listeners: no certificate_arn, and enable_http_listener is false. On environment = \"dev\" set enable_http_listener = true to serve plaintext HTTP, or supply certificate_arn to serve HTTPS."
  }
}

variable "certificate_arn" {
  description = <<EOT
ACM certificate ARN for the HTTPS listener. Required when enable_alb = true,
unless environment = "dev".

The API carries Supabase JWTs, so a plaintext endpoint puts bearer tokens on the
wire in the clear. Rather than defaulting to HTTP and trusting an operator to
turn TLS on later, prod and staging refuse to plan an ALB without a certificate.
The cert must live in this stack's region (var.aws_region) and cover the
hostname the frontend will call.

dev is exempt so the stack can be stood up before a domain exists: an ACM cert
needs a domain you own and DNS validation, which is a hard blocker on work that
has nothing to do with TLS. A dev stack must then also set
enable_http_listener = true, since HTTP is its only remaining listener.

Leave null with enable_alb = false in any environment -- that builds no load
balancer and therefore no inbound path at all.
EOT
  type        = string
  default     = null

  validation {
    condition     = !var.enable_alb || var.certificate_arn != null || var.environment == "dev"
    error_message = "certificate_arn is required when enable_alb = true on environment prod or staging: the ALB serves HTTPS only there, and Supabase JWTs must not cross the wire in plaintext. Supply an ACM certificate ARN in this region, set enable_alb = false to build no load balancer, or use environment = \"dev\" for a pre-domain stack."
  }
}

variable "health_check_path" {
  description = "Unauthenticated path returning 200 when the app is ready. Must match the health route in src/api/v1/routes."
  type        = string
  default     = "/api/v1/health"
}

###############################################################################
# ECR / image
###############################################################################

variable "ecr_repository_name" {
  description = "ECR repository holding the API image. CREATED by this config -- if a repository of this name already exists, either rename or import it."
  type        = string
  default     = "mqs-backtest-visualizer"
}

variable "image_tag" {
  description = <<EOT
Image tag to deploy. Must be a tag that already exists in ecr_repository_name --
ECS resolves it at task start, so a missing tag surfaces as
CannotPullContainerError rather than a Terraform error.

The repository is empty until the first CI build pushes, which is why
desired_count defaults to 0.
EOT
  type        = string
  default     = "latest"
}

###############################################################################
# API service
###############################################################################

variable "container_port" {
  description = "Port uvicorn binds inside the container. Matches PORT in .env.example."
  type        = number
  default     = 8000
}

variable "task_cpu" {
  description = "Fargate CPU units for the API task. 1024 = 1 vCPU. The API stays small and warm; backtests belong in a separate worker task."
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate memory in MiB. Must form a valid Fargate CPU/memory pair with task_cpu."
  type        = string
  default     = "1024"
}

variable "desired_count" {
  description = <<EOT
Number of API replicas.

Defaults to 0 on purpose: no image has ever been pushed to the repository this
config creates, so a non-zero count would leave ECS retrying
CannotPullContainerError indefinitely after an otherwise successful apply.

After the first image lands:
  aws ecs update-service --cluster <cluster> --service <service> --desired-count 1
and then raise this value so Terraform and reality agree.
EOT
  type        = number
  default     = 0
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into running tasks. Off by default -- it is a live shell in production."
  type        = bool
  default     = false
}

variable "artifact_bucket_arn" {
  description = "S3 bucket ARN for run artifacts (CSV/parquet). null grants the task role no S3 access. The bucket itself is not created here."
  type        = string
  default     = null
}

###############################################################################
# Application configuration (non-secret -- visible in the task definition)
###############################################################################

variable "log_level" {
  description = "Application log level: DEBUG | INFO | WARNING | ERROR."
  type        = string
  default     = "INFO"
}

variable "cors_origins" {
  description = "Origins allowed to call the API. The frontend's deployed URL goes here."
  type        = list(string)
  default     = []
}

variable "market_timezone" {
  description = "Timezone every bar timestamp is normalized to. Do not change casually -- the engine assumes NY-zoned data end to end."
  type        = string
  default     = "America/New_York"
}

variable "supabase_project_ref" {
  description = "Supabase project ref. SUPABASE_URL, SUPABASE_JWKS_URL and JWT_ISSUER are derived from it. Empty string omits all four."
  type        = string
  default     = ""
}

variable "max_concurrent_runs_per_user" {
  description = "Concurrent backtest runs allowed per user."
  type        = number
  default     = 3
}

variable "max_backtest_window_days" {
  description = "Longest backtest window a user may request, in days."
  type        = number
  default     = 1825
}

variable "rate_limit_per_minute" {
  description = "Per-user request rate limit."
  type        = number
  default     = 60
}

variable "extra_environment" {
  description = "Additional non-secret environment variables merged into the container definition. Never put credentials here -- they would land in Terraform state."
  type        = map(string)
  default     = {}
}

###############################################################################
# Observability
###############################################################################

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}

variable "container_insights_enabled" {
  description = "ECS Container Insights. Bills as custom CloudWatch metrics."
  type        = bool
  default     = true
}

###############################################################################
# Secrets
#
# Values are write-only: they never enter Terraform state or plan output, which
# also means Terraform cannot detect that you changed one. After editing a value,
# BUMP the matching counter or the apply is a no-op. Bumping rewrites every
# parameter in that group, discarding out-of-band rotations -- to rotate a single
# credential, prefer `aws ssm put-parameter`.
###############################################################################

variable "market_data_parameter_version" {
  description = "Bump to push market_data_secret_values into SSM Parameter Store."
  type        = number
  default     = 1
}

variable "api_parameter_version" {
  description = "Bump to push api_secret_values into SSM Parameter Store."
  type        = number
  default     = 1
}

variable "market_data_secret_values" {
  description = <<EOT
Connection details for the EXTERNAL market_data Postgres. This stack provisions
no database -- the host must already exist and accept connections from the
internet.

MARKET_DATA_USER must be a READ-ONLY role: the visualizer must never write to
positions_book, cash_equity_book, or trade_execution_logs.

Set MARKET_DATA_SSLMODE to "require" or stronger for anything crossing the
public internet; "prefer" silently accepts an unencrypted connection.
EOT
  type = object({
    MARKET_DATA_HOST     = string
    MARKET_DATA_PORT     = string
    MARKET_DATA_DB       = string
    MARKET_DATA_USER     = string
    MARKET_DATA_PASSWORD = string
    MARKET_DATA_SSLMODE  = string
  })
  sensitive = true
  default = {
    MARKET_DATA_HOST     = "REPLACE_ME"
    MARKET_DATA_PORT     = "5432"
    MARKET_DATA_DB       = "REPLACE_ME"
    MARKET_DATA_USER     = "REPLACE_ME"
    MARKET_DATA_PASSWORD = "REPLACE_ME"
    MARKET_DATA_SSLMODE  = "require"
  }
}

variable "api_secret_values" {
  description = "Third-party credentials stored in SSM Parameter Store."
  type = object({
    FMP_API_KEY       = string
    SUPABASE_ANON_KEY = string
  })
  sensitive = true
  default = {
    FMP_API_KEY       = "REPLACE_ME"
    SUPABASE_ANON_KEY = "REPLACE_ME"
  }
}
