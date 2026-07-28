###############################################################################
# Root composition for the prod environment: wires every module together.
###############################################################################

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  repository_name = var.ecr_repository_name
}

module "networking" {
  source = "../../modules/networking"

  name_prefix = local.name_prefix
}

module "rds_postgres" {
  source = "../../modules/rds-postgres"

  name_prefix            = local.name_prefix
  vpc_id                 = module.networking.vpc_id
  subnet_ids             = module.networking.subnet_ids
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
  subnet_ids              = module.networking.subnet_ids
  security_group_id       = module.networking.task_security_group_id
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
  subnet_ids                           = module.networking.subnet_ids
  security_group_id                    = module.networking.task_security_group_id
}
