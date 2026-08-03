variable "name_prefix" {
  description = "Prefix used for the task family and service name."
  type        = string
}

variable "container_name" {
  description = "Container name inside the task definition. Must match the name referenced by the ALB target group."
  type        = string
  default     = "api"
}

variable "image_uri" {
  description = "Full container image URI including tag."
  type        = string
}

variable "container_port" {
  description = "Port uvicorn binds inside the container."
  type        = number
  default     = 8000
}

variable "task_cpu" {
  description = "Fargate CPU units. 1024 = 1 vCPU. Must form a valid Fargate CPU/memory pair."
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate memory in MiB. Must form a valid Fargate CPU/memory pair."
  type        = string
  default     = "1024"
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. ARM64 (Graviton) is ~20% cheaper but the image must be built for it."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "desired_count" {
  description = "Replica count. Defaults to 0 so the first apply converges before any image exists; raise once an image has been pushed."
  type        = number
  default     = 0
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN."
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID/ARN."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the tasks run in. Public subnets in this stack, because there is no NAT gateway."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the task ENI."
  type        = string
}

variable "assign_public_ip" {
  description = <<EOT
Assign a public IP to the task ENI. MUST be true in this stack: with no NAT
gateway a task without a public IP has no route off the VPC and cannot pull its
image from ECR, reach the external database, or verify Supabase JWTs.

Set false only in combination with has_nat_egress = true.
EOT
  type        = bool
  default     = true
}

variable "has_nat_egress" {
  description = "Whether the subnets have NAT-based egress. false in this stack -- it is what makes assign_public_ip = false a hard error rather than a slow runtime failure."
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = <<EOT
ALB target group to register tasks into.

null runs the service with no load balancer, which also means NO INBOUND PATH:
the task security group's only ingress rule references the ALB security group,
so nothing reaches the task even though it holds a public IP. That IP is an
egress path only. In this mode the container is observable through CloudWatch
Logs and `aws ecs execute-command` (see enable_execute_command), not over HTTP.
EOT
  type        = string
  default     = null
}

variable "container_health_check_command" {
  description = <<EOT
ECS container health check command, e.g.
  ["CMD-SHELL", "curl -f http://127.0.0.1:8000/api/v1/health || exit 1"]

null (the default) omits the check entirely. Only set this once there is a
Dockerfile to verify against: the command runs INSIDE the container, so the
binary it names must exist on that image's PATH. If it does not, ECS marks the
essential container unhealthy and kills the task on a loop -- and because the
task definition sets ignore_changes on container_definitions, a later apply will
not repair it.

Redundant with the ALB target group probe for a load-balanced service; worth
setting for a service running without a load balancer.
EOT
  type        = list(string)
  default     = null
}

variable "health_check_grace_period" {
  description = "Seconds to let the app boot before health checks count against it."
  type        = number
  default     = 60
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower bound on running tasks during a deploy. 100 keeps the API continuously available."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Upper bound on running tasks during a deploy. 200 starts the replacement before draining the old task."
  type        = number
  default     = 200
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into running tasks. Pair with enable_ecs_exec on the IAM module."
  type        = bool
  default     = false
}

variable "container_secrets" {
  description = "Secrets injected into the container (ECS task definition `secrets` block)."
  type = list(object({
    name      = string
    valueFrom = string
  }))
}

variable "environment" {
  description = "Non-secret environment variables merged into the container definition."
  type        = map(string)
  default     = {}
}

variable "log_group_name" {
  description = "CloudWatch log group name."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the awslogs driver."
  type        = string
}
