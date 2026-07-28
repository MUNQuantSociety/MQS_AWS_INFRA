# Operations runbook

All commands assume `terraform/environments/prod` as the working directory and a
configured AWS profile in `us-east-2`.

## Deploy

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars   # fill real secret values
terraform init -upgrade                        # -upgrade required: AWS provider is now ~> 6.28
terraform plan
terraform apply
```

> The AWS provider constraint moved from `~> 5.60` to `~> 6.28` when the VPC
> module was adopted. A workspace initialised before that has a lockfile pinned
> to 5.x and `plan` will refuse until `terraform init -upgrade` is run once.

Outputs after apply:

```
ecr_repository_url            = "<acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster"
ecs_cluster_name              = "mqsmaster-prod-cluster"
market_task_definition_family = "mqsmaster-prod"
nlp_task_definition_family    = "mqsmaster-prod-nlp"
nlp_service_name              = "mqsmaster-prod-nlp"
log_group_name                = "/ecs/mqsmaster-prod"
rds_endpoint                  = "<id>.<region>.rds.amazonaws.com:5432"
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

## Manually trigger the market task

```bash
aws ecs run-task --cluster $(terraform output -raw ecs_cluster_name) --task-definition $(terraform output -raw market_task_definition_family) --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json task_subnet_ids | jq -r 'join(",")')],securityGroups=[$(terraform output -raw task_security_group_id)],assignPublicIp=DISABLED}"
```

`assignPublicIp` **must be `DISABLED`**. `task_subnet_ids` now returns private
subnets, and Fargate rejects a task that asks for a public IP in a subnet with no
route to an internet gateway. Egress still works — it goes out via the NAT
gateway.

## Logs

```bash
aws logs tail /ecs/mqsmaster-prod --since 1h --follow
```

Filter to one workload by stream prefix:

```bash
aws logs tail /ecs/mqsmaster-prod --log-stream-name-prefix nlp --since 1h --follow
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
schedule_expression    = "cron(0 11 ? * MON-FRI *)"
schedule_timezone      = "America/St_Johns"
use_scheduler_timezone = true
```

**Do not move this earlier than the market open.** `start.sh` evaluates
`is_market_open` on the first iteration of its monitor loop, immediately after
launching the market scripts — if the market is not open yet it SIGTERMs all of
them and exits. 11:00 `America/St_Johns` is the 09:30 ET open, since Newfoundland
runs ET+1:30.

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
