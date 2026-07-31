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
ecr_repository_url            = "<acct>.dkr.ecr.us-east-2.amazonaws.com/livetradingbot"
ecs_cluster_name              = "mqsmaster-prod-cluster"
market_task_definition_family = "mqsmaster-prod"
nlp_task_definition_family    = "mqsmaster-prod-nlp"
nlp_service_name              = "mqsmaster-prod-nlp"
log_group_name                = "/ecs/mqsmaster-prod"
rds_endpoint                  = "<id>.<region>.rds.amazonaws.com:5432"
```

## First image push

Terraform adopts the existing `livetradingbot` repo rather than creating it, so
images already present stay put. Tasks still fail with `CannotPullContainerError`
if `image_tag` names a tag that is not in the repo — the tag is resolved by ECS at
task start, not by Terraform, so a bad value applies cleanly and only breaks at
runtime.

Either merge to `main` and let CI push, or push manually:

```bash
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <acct>.dkr.ecr.us-east-2.amazonaws.com
```

```bash
cd ../MQSMaster && docker build -t livetradingbot:1.0.5-5 . && docker tag livetradingbot:1.0.5-5 <acct>.dkr.ecr.us-east-2.amazonaws.com/livetradingbot:1.0.5-5 && docker push <acct>.dkr.ecr.us-east-2.amazonaws.com/livetradingbot:1.0.5-5
```

Then set `image_tag` in `terraform.tfvars` to the tag you just pushed
(`1.0.5-5` above) and re-apply. It is currently pinned to `1.0.5-4`; pushing a
new tag without bumping this deploys the old image.

Note this only governs the *first* revision of each task definition — both the
market and NLP families carry `ignore_changes = [container_definitions]`, so
after that CI re-registration is what moves the image.

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

Initial values come from `terraform.tfvars`. Values are passed as **write-only**
arguments (`value_wo`), so they are sent to AWS but never written to state or
plan files, and Terraform cannot diff them. An update fires only when the paired
`value_wo_version` changes — which means console or CLI rotations are **not**
overwritten by a later `terraform apply`.

**Preferred: rotate directly in AWS.** Each credential is a separate SecureString
parameter, so rotate them one at a time rather than rewriting a JSON blob.

> **Do not paste secrets on the command line.** `--value '<new>'` lands the
> credential in `~/.zsh_history` (and in the process list while it runs). Read it
> from a mode-600 file instead and delete the file afterwards, or rotate in the
> AWS console.

```bash
umask 077 && printf '%s' '<new>' > /tmp/rot.$$   # not world-readable
aws ssm put-parameter --name /mqsmaster-prod/db/password \
  --type SecureString --value "file:///tmp/rot.$$" --overwrite
shred -u /tmp/rot.$$ 2>/dev/null || rm -P /tmp/rot.$$
```

The parameter keeps whatever KMS key it was created with, so `--key-id` is not
needed on rotation. It is only required when **changing** the key — the default
is the AWS-managed `alias/aws/ssm`; pass the CMK explicitly if the module's
`kms_key_id` has been pointed at a customer managed key:

```bash
aws ssm put-parameter --name /mqsmaster-prod/db/password \
  --type SecureString --key-id 'alias/mqsmaster-prod' \
  --value "file:///tmp/rot.$$" --overwrite
```

List what exists (metadata only, no values):

```bash
aws ssm describe-parameters --parameter-filters 'Key=Path,Option=Recursive,Values=/mqsmaster-prod'
```

**Alternative: re-seed from Terraform.** Edit the value in `terraform.tfvars`,
then bump the matching version counter in the same file — editing the value alone
does nothing, because Terraform cannot see it:

```hcl
db_secret_values     = { ... }   # new password here
db_parameter_version = 2         # <- without this bump, apply is a no-op
```

`terraform.tfvars` holds live credentials in plaintext. It is gitignored
(`.gitignore:5`) and must stay that way; keep it mode 600 and never copy it into
a shared location. Only `terraform.tfvars.example`, which contains placeholders,
is tracked.

Bumping `db_parameter_version` rewrites **all six** `/db/*` parameters **and the
RDS master password** — they share the counter deliberately, so the database and
the credential the containers read cannot drift apart. `api_parameter_version`
covers the three `/api/*` keys. Either way the whole group is rewritten,
discarding out-of-band rotations of the others, so prefer `put-parameter` when
rotating a single credential.

This is also the mechanism for fixing `/mqsmaster-prod/db/host` if RDS is ever
replaced and gets a new endpoint — bump `db_parameter_version` and apply.

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
