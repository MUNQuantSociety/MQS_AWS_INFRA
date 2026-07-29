###############################################################################
# Root composition for the prod environment: wires every module together.
###############################################################################

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  repository_name = var.ecr_repository_name
}

###############################################################################
# Dedicated VPC. Public subnets carry only the IGW + NAT gateway; every
# workload (Fargate tasks, RDS) lives in the private subnets.
#
# OUTBOUND INTERNET IS PRESERVED. "Private" here means no inbound path and no
# public IP on the task ENI -- it does NOT mean isolated. Both workloads still
# reach their third-party API hosts exactly as before:
#
#   - ecs_service_nlp (always-on) and ecs_task_market (scheduled) call out to
#     FMP, Alpha Vantage and Apify over HTTPS.
#   - Path: private subnet -> 0.0.0.0/0 route -> NAT instance -> IGW -> internet.
#   - The task SG (modules/networking) allows all egress, so no per-host
#     allowlisting is required; adding a new data provider needs no VPC change.
#
# The only traffic that does NOT take the NAT is S3 (and therefore ECR image
# layers), which is routed through the free S3 gateway endpoint instead.
#
# Egress is provided by a fck-nat NAT *instance*, not a managed NAT gateway --
# see module.fck_nat below for the cost reasoning.
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = local.name_prefix
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # No managed NAT gateway: module.fck_nat owns the private 0.0.0.0/0 route.
  # Leaving this true would create a competing default route.
  enable_nat_gateway = false

  # Tasks run in private subnets and never take a public IP.
  map_public_ip_on_launch = false

  # Flow logs bill per GB ingested; off by default to keep the floor low.
  enable_flow_log = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

###############################################################################
# NAT instance (fck-nat) instead of a managed NAT gateway.
#
# A NAT gateway is ~$33/mo of which ~97% is the fixed hourly charge -- this
# stack pushes roughly 1 GB/mo through it, because ECR image layers already
# bypass NAT via the S3 gateway endpoint. Paying gateway prices for kernel
# packet forwarding at that volume is the single worst line in the bill, so
# this runs the same masquerade on a t4g.nano for ~$7.40/mo all-in
# (instance ~$3.07 + 8 GB gp3 ~$0.64 + public IPv4 ~$3.65).
#
# Reliability: ha_mode puts the instance in an ASG of 1 behind a STATIC ENI.
# The private route table targets that ENI, not the instance, so an instance
# replacement does not invalidate the route. Expect ~2-3 min of no egress while
# the ASG replaces a failed instance -- acceptable for a batch/scheduled
# workload whose API calls retry, and the reason this is not appropriate for
# anything latency- or availability-critical.
#
# Operational cost: unlike a NAT gateway, this is an EC2 instance you own and
# must patch. auto_rollout can cycle instances onto refreshed AMIs.
# attach_ssm_policy (default true) gives Session Manager access, so no SSH key
# and no port 22.
#
# To revert to a managed NAT gateway: set enable_nat_gateway = true and
# single_nat_gateway = true above, and remove this module.
###############################################################################

// Without an explicit EIP, fck-nat launches with an *ephemeral* public IP, so
// the egress address changes every time the ASG replaces the instance. A NAT
// gateway has a stable address, and provider IP-allowlisting depends on that,
// so pin one here. No extra cost: AWS bills any in-use public IPv4 the same.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "~> 1.6"

  name      = "${local.name_prefix}-nat"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0] # must be public: this is the exit point

  ha_mode            = true
  instance_type      = var.nat_instance_type
  eip_allocation_ids = [aws_eip.nat.id]

  # route_tables_ids is a map(string), not a list -- the VPC module returns a
  # list, so it has to be projected into one keyed by index.
  update_route_tables = true
  route_tables_ids = {
    for idx, rt in module.vpc.private_route_table_ids : "private-${idx}" => rt
  }

  tags = {
    Name = "${local.name_prefix}-nat"
  }
}

module "networking" {
  source = "../../modules/networking"

  name_prefix             = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  aws_region              = var.aws_region
  private_route_table_ids = module.vpc.private_route_table_ids
}

module "rds_postgres" {
  source = "../../modules/rds-postgres"

  name_prefix            = local.name_prefix
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnets
  task_security_group_id = module.networking.task_security_group_id

  db_username = var.db_secret_values.db_user
  db_password = var.db_secret_values.password
  db_name     = var.db_secret_values.database
  port        = tonumber(var.db_secret_values.port)

  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  max_allocated_storage   = var.db_max_allocated_storage
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
}

module "secrets_manager" {
  source = "../../modules/secrets-manager"

  name_prefix       = local.name_prefix
  db_secret_values  = local.db_secret_values
  api_secret_values = var.api_secret_values
}

module "iam_roles" {
  source = "../../modules/iam-roles"

  name_prefix = local.name_prefix
  secret_arns = [module.secrets_manager.db_secret_arn, module.secrets_manager.api_secret_arn]
}

module "cloudwatch_logs" {
  source = "../../modules/cloudwatch-logs"

  log_group_name    = local.log_group
  retention_in_days = var.log_retention_days
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix = local.name_prefix
}

module "ecs_task_market" {
  source = "../../modules/ecs-task-market"

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

module "ecs_service_nlp" {
  source = "../../modules/ecs-service-nlp"

  name_prefix             = local.name_prefix
  image_uri               = local.image_uri
  task_cpu                = var.nlp_task_cpu
  task_memory             = var.nlp_task_memory
  desired_count           = var.nlp_desired_count
  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
  cluster_id              = module.ecs_cluster.cluster_id
  subnet_ids              = module.vpc.private_subnets
  security_group_id       = module.networking.task_security_group_id
  assign_public_ip        = false
  container_secrets       = local.container_secrets
  log_group_name          = module.cloudwatch_logs.log_group_name
  aws_region              = var.aws_region
}

module "eventbridge_scheduler" {
  source = "../../modules/eventbridge-scheduler"

  name_prefix                          = local.name_prefix
  schedule_expression                  = var.schedule_expression
  schedule_timezone                    = var.schedule_timezone
  use_scheduler_timezone               = var.use_scheduler_timezone
  cluster_arn                          = module.ecs_cluster.cluster_arn
  task_definition_arn_without_revision = module.ecs_task_market.task_definition_arn_without_revision
  task_execution_role_arn              = module.iam_roles.task_execution_role_arn
  task_role_arn                        = module.iam_roles.task_role_arn
  subnet_ids                           = module.vpc.private_subnets
  security_group_id                    = module.networking.task_security_group_id
  assign_public_ip                     = false
}
