###############################################################################
# Root composition: ECS Fargate for the backtest visualizer API.
#
# Shape of this stack, and what is deliberately absent:
#
#   - NO NAT GATEWAY. Tasks run in public subnets with a public IP on the ENI and
#     egress straight through the internet gateway. Saves ~$32/mo plus $0.045/GB
#     of data processing. The cost is that egress has no stable source IP --
#     see ./README.md before pointing this at an IP-filtered database.
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
  source = "../../modules/Backtest_Visualizer/ecr-repository"

  repository_name = var.ecr_repository_name
}

###############################################################################
# VPC, via the same registry module and pinned version Livetrading uses, rather
# than a hand-rolled one -- one VPC implementation to reason about across both
# stacks.
#
# The no-NAT shape is expressed entirely through its inputs:
#   enable_nat_gateway = false   no NAT gateway, and therefore no NAT bill
#   private_subnets    = []      no private tier -- nothing could route out of it
#   map_public_ip_on_launch      tasks take a public IP; that IS the egress path
#
# This is the inverse of Livetrading, which keeps every workload in private
# subnets behind a single NAT gateway.
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = local.name_prefix
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = var.public_subnet_cidrs
  private_subnets = []

  # The whole point of this stack: no NAT gateway (~$32/mo + $0.045/GB).
  enable_nat_gateway = false

  # Load-bearing. Fargate tasks run here and reach the internet through the IGW
  # using this public IP; without it they have no route to ECR or the external
  # database. See modules/Backtest_Visualizer/ecs-service-api.
  map_public_ip_on_launch = true

  # Flow logs bill per GB ingested; off by default to keep the floor low.
  enable_flow_log = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "security_groups" {
  source = "../../modules/Backtest_Visualizer/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id

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
  source = "../../modules/Backtest_Visualizer/ssm-parameters"

  name_prefix                   = local.name_prefix
  market_data_secret_values     = var.market_data_secret_values
  api_secret_values             = var.api_secret_values
  market_data_parameter_version = var.market_data_parameter_version
  api_parameter_version         = var.api_parameter_version
}

module "iam_roles" {
  source = "../../modules/Backtest_Visualizer/iam-roles"

  name_prefix         = local.name_prefix
  parameter_arns      = module.ssm_parameters.parameter_arn_list
  artifact_bucket_arn = var.artifact_bucket_arn
  enable_ecs_exec     = var.enable_execute_command
}

module "cloudwatch_logs" {
  source = "../../modules/Backtest_Visualizer/cloudwatch-logs"

  log_group_name    = local.log_group
  retention_in_days = var.log_retention_days
}

module "ecs_cluster" {
  source = "../../modules/Backtest_Visualizer/ecs-cluster"

  name_prefix                = local.name_prefix
  container_insights_enabled = var.container_insights_enabled
}

###############################################################################
# ALB. Optional, but on by default: a Fargate task's public IP is ephemeral and
# changes on every deployment, so without this there is no stable address to
# give the frontend repo.
###############################################################################

module "alb" {
  source = "../../modules/Backtest_Visualizer/alb"
  count  = var.enable_alb ? 1 : 0

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnets
  security_group_id = module.security_groups.alb_security_group_id

  container_port       = var.container_port
  health_check_path    = var.health_check_path
  enable_http_listener = var.enable_http_listener
  certificate_arn      = var.certificate_arn
}

module "ecs_service_api" {
  source = "../../modules/Backtest_Visualizer/ecs-service-api"

  name_prefix    = local.name_prefix
  image_uri      = local.image_uri
  container_port = var.container_port
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  desired_count  = var.desired_count

  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
  cluster_id              = module.ecs_cluster.cluster_id

  subnet_ids        = module.vpc.public_subnets
  security_group_id = module.security_groups.service_security_group_id

  # Not a knob. No NAT gateway means a private ENI has no route anywhere -- not
  # to ECR, not to the external database. has_nat_egress = false makes flipping
  # this to false a plan-time error instead of a runtime one.
  assign_public_ip = true
  has_nat_egress   = false

  # The readiness probe lives on the ALB target group, not in the container --
  # see module.alb above. Nothing about it reaches the task definition.
  target_group_arn = var.enable_alb ? module.alb[0].target_group_arn : null

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
