# Operations runbook

All commands assume `terraform/environments/prod` as the working directory and a
configured AWS profile in `us-east-2`.

## Deploy

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars   # fill real secret values
terraform init
terraform plan
terraform apply
```

Outputs after apply:

```
ecr_repository_url             = "<acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster"
ecs_cluster_name               = "mqsmaster-prod-cluster"
market_task_definition_family  = "mqsmaster-prod"
refresh_task_definition_family = "mqsmaster-prod-refresh"
nlp_task_definition_family     = "mqsmaster-prod-nlp"
nlp_service_name               = "mqsmaster-prod-nlp"
market_schedule_name           = "mqsmaster-prod-market-open"
refresh_schedule_name          = "mqsmaster-prod-refresh"
log_group_name                 = "/ecs/mqsmaster-prod"
rds_endpoint                   = "<id>.<region>.rds.amazonaws.com:5432"
```

## First image push

Terraform creates an empty ECR repo. Tasks fail with `CannotPullContainerError`
until the first image lands. Either merge to `main` and let CI push, or push
manually:

```bash
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <acct>.dkr.ecr.us-east-2.amazonaws.com
```

```bash
cd ../MQSMaster && docker build -t mqsmaster:latest . && docker tag mqsmaster:latest <acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster:latest && docker push <acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster:latest
```

## Manually trigger a scheduled task

Market task:

```bash
aws ecs run-task --cluster $(terraform output -raw ecs_cluster_name) --task-definition $(terraform output -raw market_task_definition_family) --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json task_subnet_ids | jq -r 'join(",")')],securityGroups=[$(terraform output -raw task_security_group_id)],assignPublicIp=ENABLED}"
```

Refresh task — useful for verifying the backfill without waiting for Friday:

```bash
aws ecs run-task --cluster $(terraform output -raw ecs_cluster_name) --task-definition $(terraform output -raw refresh_task_definition_family) --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json task_subnet_ids | jq -r 'join(",")')],securityGroups=[$(terraform output -raw task_security_group_id)],assignPublicIp=ENABLED}"
```

For a dry run that fetches but does not insert, override the command:

```bash
aws ecs run-task --cluster $(terraform output -raw ecs_cluster_name) --task-definition $(terraform output -raw refresh_task_definition_family) --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json task_subnet_ids | jq -r 'join(",")')],securityGroups=[$(terraform output -raw task_security_group_id)],assignPublicIp=ENABLED}" --overrides '{"containerOverrides":[{"name":"mqsmaster-refresh","command":["src/orchestrator/backfill/update/refresh.py","--threads","4","--dry-run"]}]}'
```

## Changing refresh arguments

`refresh_threads`, `refresh_exchange` and `refresh_extra_args` live inside
`container_definitions`, which carries `ignore_changes` so CI-registered
revisions are not clobbered. That block also suppresses these edits. To apply one:

1. Comment out the `lifecycle { ignore_changes = [container_definitions] }` block
   in `modules/ecs-task-refresh/main.tf`.
2. `terraform apply` — registers a new revision.
3. Restore the `lifecycle` block.

The schedule targets the family, so Friday's run picks up the new revision with no
further action.

## Logs

```bash
aws logs tail /ecs/mqsmaster-prod --since 1h --follow
```

Filter to one workload by stream prefix (`mqsmaster`, `nlp`, or `refresh`):

```bash
aws logs tail /ecs/mqsmaster-prod --log-stream-name-prefix nlp --since 1h --follow
```

Check last Friday's backfill:

```bash
aws logs tail /ecs/mqsmaster-prod --log-stream-name-prefix refresh --since 7d
```

## Rotating secrets

Initial values come from `terraform.tfvars`. After apply, the
`aws_secretsmanager_secret_version` resources carry `ignore_changes`, so console
or CLI rotations are **not** overwritten by a later `terraform apply`.

```bash
aws secretsmanager put-secret-value --secret-id mqsmaster-prod/db --secret-string '{"db_user":"mqsadmin","password":"<new>","host":"<rds-endpoint>","port":"5432","database":"mqsdb","sslmode":"prefer"}'
```

Running tasks keep the old value — secrets are read at task start. Force a
refresh of the always-on NLP service:

```bash
aws ecs update-service --cluster mqsmaster-prod-cluster --service mqsmaster-prod-nlp --force-new-deployment
```

## Changing the schedule

Override in `terraform.tfvars`:

```hcl
schedule_expression         = "cron(0 8 ? * MON-FRI *)"   # market open, Mon–Fri
refresh_schedule_expression = "cron(30 18 ? * FRI *)"     # weekly backfill, Friday
schedule_timezone           = "America/St_Johns"
use_scheduler_timezone      = true
```

The refresh default sits ~1 h after the 16:00 ET close (17:30 local in
Newfoundland), so the backfill never overlaps live trading. **If you change
`schedule_timezone`, recompute `refresh_schedule_expression`** — the offset is
timezone-specific.

To move the backfill to a different day, change `FRI` (e.g. `SAT` for Saturday
morning, when there is no market activity at all):

```hcl
refresh_schedule_expression = "cron(0 6 ? * SAT *)"
```

## Adding a new environment

The layout supports it without touching module code:

```bash
cp -r terraform/environments/prod terraform/environments/staging
# edit staging/terraform.tfvars: environment = "staging", smaller sizing
```

Each environment keeps its own state and `terraform.tfvars`. Module sources
(`../../modules/...`) resolve identically from any environment directory.

## Module rename note

The 2026-07 restructure renamed every module directory and label. State-migration
shims live in `environments/prod/moved.tf`. They are inert on a fresh workspace
and can be deleted once every workspace has applied at least once post-rename.
