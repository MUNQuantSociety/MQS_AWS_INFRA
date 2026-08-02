###############################################################################
# Root composition: ECS Fargate for the backtest visualizer API.
#
# Shape of this stack, and what is deliberately absent:
#
#   - NO NAT GATEWAY. Tasks run in public subnets with a public IP on the ENI and
#     egress straight through the internet gateway. Saves ~$32/mo plus $0.045/GB
#     of data processing. The cost is that egress has no stable source IP --
#     see ../../README.md before pointing this at an IP-filtered database.
#
#   - NO DATABASE. The market_data Postgres is EXTERNAL to this stack; its
#     connection details are read from SSM Parameter Store. Nothing here creates
#     RDS, and nothing here can open a security group on a database it does not
#     manage.
#
#   - NO PRIVATE SUBNETS. There is no workload that needs one once the NAT is
#     gone: ingress is controlled by security group, not by subnet tier.
###############################################################################

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  repository_name = var.ecr_repository_name
}

module "networking" {
  source = "../../modules/networking"

  name_prefix         = local.name_prefix
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = local.azs

  container_port       = var.container_port
  ingress_cidr_blocks  = var.alb_ingress_cidr_blocks
  enable_http_listener = var.enable_http_listener
  certificate_arn      = var.certificate_arn
}

###############################################################################
# Credentials for the external database and third-party services.
#
# Values are write-only: they never enter state or plan output, which also means
# Terraform cannot tell when one changes. After editing a value in tfvars, bump
# the matching *_parameter_version counter or the apply is a no-op.
###############################################################################

module "ssm_parameters" {
  source = "../../modules/ssm-parameters"

  name_prefix                   = local.name_prefix
  market_data_secret_values     = var.market_data_secret_values
  api_secret_values             = var.api_secret_values
  market_data_parameter_version = var.market_data_parameter_version
  api_parameter_version         = var.api_parameter_version
}

module "iam_roles" {
  source = "../../modules/iam-roles"

  name_prefix         = local.name_prefix
  parameter_arns      = module.ssm_parameters.parameter_arn_list
  artifact_bucket_arn = var.artifact_bucket_arn
  enable_ecs_exec     = var.enable_execute_command
}

module "cloudwatch_logs" {
  source = "../../modules/cloudwatch-logs"

  log_group_name    = local.log_group
  retention_in_days = var.log_retention_days
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix                = local.name_prefix
  container_insights_enabled = var.container_insights_enabled
}

###############################################################################
# ALB. Optional, but on by default: a Fargate task's public IP is ephemeral and
# changes on every deployment, so without this there is no stable address to
# give the frontend repo.
###############################################################################

module "alb" {
  source = "../../modules/alb"
  count  = var.enable_alb ? 1 : 0

  name_prefix       = local.name_prefix
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.public_subnet_ids
  security_group_id = module.networking.alb_security_group_id

  container_port       = var.container_port
  health_check_path    = var.health_check_path
  enable_http_listener = var.enable_http_listener
  certificate_arn      = var.certificate_arn
}

module "ecs_service_api" {
  source = "../../modules/ecs-service-api"

  name_prefix    = local.name_prefix
  image_uri      = local.image_uri
  container_port = var.container_port
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  desired_count  = var.desired_count

  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
  cluster_id              = module.ecs_cluster.cluster_id

  subnet_ids        = module.networking.public_subnet_ids
  security_group_id = module.networking.service_security_group_id

  # Not a knob. No NAT gateway means a private ENI has no route anywhere -- not
  # to ECR, not to the external database. has_nat_egress = false makes flipping
  # this to false a plan-time error instead of a runtime one.
  assign_public_ip = true
  has_nat_egress   = false

  target_group_arn  = var.enable_alb ? module.alb[0].target_group_arn : null
  health_check_path = var.health_check_path

  enable_execute_command = var.enable_execute_command
  container_secrets      = local.container_secrets
  environment            = local.app_environment
  log_group_name         = module.cloudwatch_logs.log_group_name
  aws_region             = var.aws_region

  # The service registers into the target group, which the listener must already
  # be attached to -- otherwise ECS can report the target group as not associated
  # with a load balancer.
  depends_on = [module.alb]
}
