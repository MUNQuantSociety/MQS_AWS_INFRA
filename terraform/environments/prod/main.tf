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
#   - Path: private subnet -> 0.0.0.0/0 route -> NAT gateway -> IGW -> internet.
#   - The task SG (modules/networking) allows all egress, so no per-host
#     allowlisting is required; adding a new data provider needs no VPC change.
#
# The only traffic that does NOT take the NAT is S3 (and therefore ECR image
# layers), which is routed through the free S3 gateway endpoint instead.
#
# Cost: single_nat_gateway = true keeps this to ONE NAT gateway (~$32/mo)
# instead of one per AZ (~$97/mo). It is a single-AZ failure point for egress,
# which is the accepted trade for a batch/scheduled workload. API responses are
# JSON, so NAT data processing ($0.045/GB) on those calls is negligible.
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = local.name_prefix
  cidr = var.vpc_cidr
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Tasks run in private subnets and never take a public IP.
  map_public_ip_on_launch = false

  # Flow logs bill per GB ingested; off by default to keep the floor low.
  enable_flow_log = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "networking" {
  source = "../../modules/networking"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  aws_region  = var.aws_region
  # Private RTs are what actually matters: all task/RDS S3 traffic originates
  # there and takes the endpoint instead of the NAT. Public RTs are included for
  # completeness -- today nothing runs in the public subnets (they carry only the
  # IGW and NAT gateway), so that half is inert until something is placed there.
  route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
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
  source = "../../modules/ssm-parameters"

  name_prefix           = local.name_prefix
  db_secret_values      = local.db_secret_values
  api_secret_values     = var.api_secret_values
  db_parameter_version  = var.db_parameter_version
  api_parameter_version = var.api_parameter_version
}

module "iam_roles" {
  source = "../../modules/iam-roles"

  name_prefix    = local.name_prefix
  parameter_arns = module.ssm_parameters.parameter_arn_list
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

###############################################################################
# CI/CD identity. The deploy workflow (.github/workflows/deploy.yml, which must
# live in the MQSMaster repo alongside its Dockerfile) assumes this role via
# OIDC -- no static AWS access keys anywhere. Feed the deploy_role_arn output
# into that repo's AWS_DEPLOY_ROLE_ARN secret.
###############################################################################

module "github_oidc" {
  source = "../../modules/github-oidc"

  name_prefix       = local.name_prefix
  github_repository = var.github_repository
  allowed_refs      = var.github_allowed_refs

  ecr_repository_arn      = module.ecr_repository.repository_arn
  nlp_service_arn         = module.ecs_service_nlp.service_arn
  task_execution_role_arn = module.iam_roles.task_execution_role_arn
  task_role_arn           = module.iam_roles.task_role_arn
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
