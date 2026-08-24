###############################################################################
# Root composition for the prod environment: wires every module together.
###############################################################################

module "ecr_repository" {
  source = "../../modules/Livetrading/ecr-repository"

  repository_name = var.ecr_repository_name
}

###############################################################################
# Dedicated VPC. Subnet placement is driven by task_in_public_subnet:
#
#   true  (default) -- the Fargate task runs in the PUBLIC subnets with a public
#                      IP on its ENI and egresses straight out the IGW. RDS
#                      stays in the private subnets. No NAT gateway is created.
#   false           -- the task runs in the PRIVATE subnets alongside RDS and
#                      egresses through a NAT gateway.
#
# Either way there is NO INBOUND PATH: the task SG (modules/Livetrading/
# networking) has zero ingress rules, so a public IP on the ENI is an egress
# address, not a way in. RDS is never public in either mode -- it has no public
# endpoint and its SG accepts 5432 from the task SG only, which works across
# subnet tiers because the task reaches it by private IP inside the VPC.
#
# OUTBOUND INTERNET IS PRESERVED in both modes. ecs_task_market calls FMP,
# Alpha Vantage and Apify over HTTPS; the task SG allows all egress, so adding a
# data provider needs no VPC change. Only the path and the source address differ:
#
#   public  : public subnet  -> 0.0.0.0/0 -> IGW -> internet
#   private : private subnet -> 0.0.0.0/0 -> NAT gateway -> IGW -> internet
#
# THE TRADE. A Fargate task cannot hold an Elastic IP. In public mode its public
# IP is assigned at task start and differs on every run, so outbound traffic has
# no stable source address. If a data provider ever IP-allowlists this stack,
# set task_in_public_subnet = false: that restores the NAT gateway and its stable
# EIP, at ~$32/mo. Cost is the only reason the default is the other way.
#
# S3 (and therefore ECR image layers) takes the free S3 gateway endpoint in both
# modes -- the endpoint is associated with both tiers' route tables.
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = local.name_prefix
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # Only the private tier needs a NAT gateway, and in public mode the only thing
  # left there is RDS, which makes no outbound connections. Creating one anyway
  # would bill ~$32/mo to route nothing.
  enable_nat_gateway = !var.task_in_public_subnet
  single_nat_gateway = var.single_nat_gateway

  # Subnet-level auto-assign stays off even in public mode. Fargate sets
  # assignPublicIp on the ENI itself (see module.eventbridge_scheduler), which is
  # independent of this flag -- so anything else launched into these subnets does
  # not silently inherit a public IP.
  map_public_ip_on_launch = false

  # Flow logs bill per GB ingested; off by default to keep the floor low.
  enable_flow_log = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "networking" {
  source = "../../modules/Livetrading/networking"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  aws_region  = var.aws_region
  # Both tiers, so the S3 endpoint follows the task wherever task_in_public_subnet
  # puts it. In public mode the public RTs carry the real traffic (ECR layer pulls
  # off the task ENI) and the private half is inert -- RDS makes no S3 calls; in
  # private mode the roles swap.
  route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
}

module "rds_postgres" {
  source = "../../modules/Livetrading/rds-postgres"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  # Always private, whatever task_in_public_subnet says. The DB SG accepts 5432
  # from the task SG only, which holds across tiers.
  subnet_ids             = module.vpc.private_subnets
  task_security_group_id = module.networking.task_security_group_id

  db_username = var.db_secret_values.db_user
  db_password = var.db_secret_values.password
  db_name     = var.db_secret_values.database
  port        = tonumber(var.db_secret_values.port)

  # Same counter that versions /<prefix>/db/* in SSM: one bump rotates the RDS
  # master password and the parameter the containers read, together.
  db_password_version = var.db_parameter_version

  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  max_allocated_storage   = var.db_max_allocated_storage
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
}

module "ssm_parameters" {
  source = "../../modules/Livetrading/ssm-parameters"

  name_prefix           = local.name_prefix
  db_secret_values      = local.db_secret_values
  api_secret_values     = var.api_secret_values
  db_parameter_version  = var.db_parameter_version
  api_parameter_version = var.api_parameter_version
}

module "iam_roles" {
  source = "../../modules/Livetrading/iam-roles"

  name_prefix    = local.name_prefix
  parameter_arns = module.ssm_parameters.parameter_arn_list
}

module "cloudwatch_logs" {
  source = "../../modules/Livetrading/cloudwatch-logs"

  log_group_name    = local.log_group
  retention_in_days = var.log_retention_days
}

module "ecs_cluster" {
  source = "../../modules/Livetrading/ecs-cluster"

  name_prefix = local.name_prefix
}

module "ecs_task_market" {
  source = "../../modules/Livetrading/ecs-task-market"

  name_prefix             = local.name_prefix
  image_uri               = local.image_uri
  task_cpu                = var.market_task_cpu
  task_memory             = var.market_task_memory
  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
  container_secrets       = local.container_secrets
  log_group_name          = module.cloudwatch_logs.log_group_name
  aws_region              = var.aws_region
}

###############################################################################
# Always-on NLP service. Restored after being dropped in #14 ("single scheduled
# workload") for cost -- ~$18-20/mo for the default 512 CPU / 2048 MiB always-on
# task. Placement follows task_in_public_subnet, same as the market task and the
# scheduler: in the default (public) mode there is no NAT gateway at all
# (enable_nat_gateway = !var.task_in_public_subnet above), so a private-subnet,
# no-public-IP NLP task would have no route to the internet and could reach
# neither its API providers nor pull its image.
###############################################################################

module "ecs_service_nlp" {
  source = "../../modules/Livetrading/ecs-service-nlp"

  name_prefix             = local.name_prefix
  image_uri               = local.image_uri
  task_cpu                = var.nlp_task_cpu
  task_memory             = var.nlp_task_memory
  desired_count           = var.nlp_desired_count
  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
  cluster_id              = module.ecs_cluster.cluster_id
  subnet_ids              = var.task_in_public_subnet ? module.vpc.public_subnets : module.vpc.private_subnets
  security_group_id       = module.networking.task_security_group_id
  assign_public_ip        = var.task_in_public_subnet
  container_secrets       = local.container_secrets
  log_group_name          = module.cloudwatch_logs.log_group_name
  aws_region              = var.aws_region
}

###############################################################################
# CI/CD identity. The deploy workflow (.github/workflows/deploy.yml, which must
# live in the MQSMaster repo alongside its Dockerfile) assumes this role via
# OIDC -- no static AWS access keys anywhere. Feed the deploy_role_arn output
# into that repo's AWS_DEPLOY_ROLE_ARN secret.
#
# The deploy role grants ecs:UpdateService/DescribeServices scoped to the NLP
# service ARN, because unlike the scheduled market task (which the scheduler
# picks up by task-definition FAMILY, unpinned) an ECS Service pins a specific
# revision and only moves when told to.
###############################################################################

module "github_oidc" {
  source = "../../modules/Livetrading/github-oidc"

  name_prefix       = local.name_prefix
  github_repository = var.github_repository
  allowed_refs      = var.github_allowed_refs

  ecr_repository_arn      = module.ecr_repository.repository_arn
  nlp_service_arn         = module.ecs_service_nlp.service_arn
  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
}

module "eventbridge_scheduler" {
  source = "../../modules/Livetrading/eventbridge-scheduler"

  name_prefix                          = local.name_prefix
  schedule_expression                  = var.schedule_expression
  schedule_timezone                    = var.schedule_timezone
  use_scheduler_timezone               = var.use_scheduler_timezone
  cluster_arn                          = module.ecs_cluster.cluster_arn
  task_definition_arn_without_revision = module.ecs_task_market.task_definition_arn_without_revision
  task_execution_role_arn              = module.iam_roles.task_execution_role_arn
  task_role_arn                        = module.iam_roles.task_role_arn
  # A public-subnet task MUST take a public IP. Without one it has no route to
  # the internet at all -- the public route table points 0.0.0.0/0 at the IGW,
  # and the IGW drops traffic from an ENI with no public address. The task would
  # fail at image pull, before any of the application code runs.
  subnet_ids        = var.task_in_public_subnet ? module.vpc.public_subnets : module.vpc.private_subnets
  security_group_id = module.networking.task_security_group_id
  assign_public_ip  = var.task_in_public_subnet
}
