###############################################################################
# Root composition: wires every module together.
###############################################################################

module "ecr" {
  source = "./modules/ecr"

  repository_name = var.ecr_repository_name
}

module "network" {
  source = "./modules/network"

  name_prefix = local.name_prefix
}

module "rds" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.subnet_ids
  task_security_group_id = module.network.task_security_group_id

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

module "secrets" {
  source = "./modules/secrets"

  name_prefix       = local.name_prefix
  db_secret_values  = local.db_secret_values
  api_secret_values = var.api_secret_values
}

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  secret_arns = [module.secrets.db_secret_arn, module.secrets.api_secret_arn]
}

module "logging" {
  source = "./modules/logging"

  log_group_name    = local.log_group
  retention_in_days = var.log_retention_days
}

module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  name_prefix = local.name_prefix
}

module "market_task" {
  source = "./modules/market_task"

  name_prefix             = local.name_prefix
  image_uri               = local.image_uri
  task_cpu                = var.market_task_cpu
  task_memory             = var.market_task_memory
  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn
  container_secrets       = local.container_secrets
  log_group_name          = module.logging.log_group_name
  aws_region              = var.aws_region
}

module "nlp_service" {
  source = "./modules/nlp_service"

  name_prefix             = local.name_prefix
  image_uri               = local.image_uri
  task_cpu                = var.nlp_task_cpu
  task_memory             = var.nlp_task_memory
  desired_count           = var.nlp_desired_count
  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn
  cluster_id              = module.ecs_cluster.cluster_id
  subnet_ids              = module.network.subnet_ids
  security_group_id       = module.network.task_security_group_id
  container_secrets       = local.container_secrets
  log_group_name          = module.logging.log_group_name
  aws_region              = var.aws_region
}

module "scheduler" {
  source = "./modules/scheduler"

  name_prefix                          = local.name_prefix
  schedule_expression                  = var.schedule_expression
  schedule_timezone                    = var.schedule_timezone
  use_scheduler_timezone               = var.use_scheduler_timezone
  cluster_arn                          = module.ecs_cluster.cluster_arn
  task_definition_arn_without_revision = module.market_task.task_definition_arn_without_revision
  task_execution_role_arn              = module.iam.task_execution_role_arn
  task_role_arn                        = module.iam.task_role_arn
  subnet_ids                           = module.network.subnet_ids
  security_group_id                    = module.network.task_security_group_id
}
