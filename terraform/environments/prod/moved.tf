###############################################################################
# State migration shims for the 2026-07 module rename (snake_case -> kebab-case
# directories, service-oriented module labels).
#
# Terraform silently ignores a `moved` block whose source address is absent from
# state, so these are safe on a fresh workspace. They exist so an operator who
# already applied this stack from a local state file does not get a
# destroy/recreate plan for every resource.
#
# Once every workspace has been applied at least once post-rename, this file can
# be deleted.
###############################################################################

moved {
  from = module.ecr
  to   = module.ecr_repository
}

moved {
  from = module.network
  to   = module.networking
}

moved {
  from = module.iam
  to   = module.iam_roles
}

moved {
  from = module.secrets
  to   = module.secrets_manager
}

moved {
  from = module.logging
  to   = module.cloudwatch_logs
}

moved {
  from = module.rds
  to   = module.rds_postgres
}

moved {
  from = module.market_task
  to   = module.ecs_task_market
}

moved {
  from = module.nlp_service
  to   = module.ecs_service_nlp
}

moved {
  from = module.scheduler
  to   = module.eventbridge_scheduler
}
