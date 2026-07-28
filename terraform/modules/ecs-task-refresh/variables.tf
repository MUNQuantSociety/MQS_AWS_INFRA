variable "name_prefix" {
  description = "Prefix for the refresh task definition family."
  type        = string
}

variable "container_name" {
  description = "Container name inside the refresh task definition."
  type        = string
  default     = "mqsmaster-refresh"
}

variable "image_uri" {
  description = "Full container image URI including tag."
  type        = string
}

variable "task_cpu" {
  description = <<EOT
Fargate CPU units. 1024 = 1 vCPU.

refresh.py is I/O bound (HTTP fetches plus DB inserts across --threads workers),
so 1 vCPU is ample; the job's duration is dominated by API and DB latency rather
than compute.
EOT
  type        = string
  default     = "1024"
}

variable "task_memory" {
  description = <<EOT
Fargate memory in MiB. Must form a valid Fargate CPU/memory pair -- 1024 CPU
permits 2048 through 8192 in 1024 increments.
EOT
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

  validation {
    condition     = var.refresh_threads > 0 && var.refresh_threads < 6
    error_message = "refresh_threads must be between 1 and 5 (MQSDBConnector pool maxconn = 6)."
  }
}

variable "refresh_exchange" {
  description = "Exchange code passed to refresh.py --exchange. The script defaults to NYSE."
  type        = string
  default     = "NYSE"
}

variable "refresh_extra_args" {
  description = <<EOT
Additional CLI arguments appended to the refresh.py invocation, e.g.
["--skip-backfill"] or ["--interval", "5"]. Empty by default so the script's own
defaults apply (last 30 days, 1-minute bars, --on-conflict ignore).
EOT
  type        = list(string)
  default     = []
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN."
  type        = string
}

variable "container_secrets" {
  description = "Secrets list injected into the container (ECS task definition `secrets` block)."
  type = list(object({
    name      = string
    valueFrom = string
  }))
}

variable "log_group_name" {
  description = "CloudWatch log group name."
  type        = string
}

variable "aws_region" {
  description = "AWS region for log driver."
  type        = string
}
