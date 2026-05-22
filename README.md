# MQSMaster AWS Infrastructure

Terraform that provisions ECS Fargate to run the
[`MQSMaster`](../MQSMaster) quantitative trading project.

- **NLP service** (always-on): runs `python NLP/main_NLP.py` 24/7. ECS Service restarts on crash.
- **Market task** (scheduled, Mon-Fri): EventBridge fires before market open in `America/St_Johns`. Container runs `start.sh` (NLP block stripped at runtime) and exits when the market closes.

## Architecture

```
GitHub Actions ──build──▶ ECR (mqsmaster)
                              │
                   ┌──────────┴──────────────────────────────────────────┐
                   ▼                                                     ▼
ECS Service mqsmaster-prod-nlp           EventBridge Scheduler ──▶ ECS RunTask mqsmaster-prod
  always-on Fargate                        cron @ 08:00 America/St_Johns   (market task, ephemeral)
  desired_count = 1                        Mon–Fri                         start.sh (NLP stripped)
  python NLP/main_NLP.py                                                   market scripts:
                                                                            src/main.py
                                                                            realtimeDataIngestor.py
                                                                            pnl_script.py
                                                                            refresh.py
                                                                            rbp_runner.py
                                                                          exits when market closes
                              │
                              ├── Secrets Manager (db creds, API keys)
                              └── CloudWatch Logs (/ecs/mqsmaster-prod, streams: mqsmaster/*, nlp/*)
```

## Repo layout

```
MQS_AWS_INFRA/
├── README.md
├── .gitignore
├── .github/workflows/deploy.yml         # CI/CD: build → ECR → register/deploy
└── terraform/
    ├── versions.tf                      # Terraform + provider version pins
    ├── providers.tf                     # AWS provider + default tags
    ├── backend.tf                       # Optional S3+DynamoDB backend stub
    ├── locals.tf                        # name_prefix, log_group, caller/region data
    ├── variables.tf                     # All input variables
    ├── main.tf                          # Module composition
    ├── outputs.tf                       # Top-level outputs
    ├── terraform.tfvars.example         # Copy → terraform.tfvars
    └── modules/
        ├── ecr/                         # ECR repo + lifecycle policy
        ├── network/                     # Default VPC data + egress-only SG
        ├── iam/                         # Task execution + task roles, secrets policy
        ├── secrets/                     # Secrets Manager (db creds, API keys)
        ├── logging/                     # CloudWatch log group
        ├── ecs_cluster/                 # ECS cluster + capacity providers
        ├── market_task/                 # Market-hours task definition
        ├── nlp_service/                 # Always-on NLP task def + ECS Service
        └── scheduler/                   # EventBridge Scheduler/Rule + IAM
```

Each module follows the same shape: `main.tf`, `variables.tf`, `outputs.tf`.

## Prerequisites

1. AWS account with admin (or sufficient IAM) credentials configured locally.
2. Terraform >= 1.5.
3. The MQSMaster repo on GitHub with a `Dockerfile` at the root (already exists).
4. GitHub OIDC provider configured in AWS (one-time). Create an IAM role trusted
   by `token.actions.githubusercontent.com` with permissions for ECR push +
   `ecs:DescribeTaskDefinition` / `ecs:RegisterTaskDefinition` /
   `ecs:UpdateService`, then store its ARN in the GitHub repo secret
   `AWS_DEPLOY_ROLE_ARN`.

### Dockerfile / .dockerignore caveats

`MQSMaster/.dockerignore` currently excludes `NLP/`, `RBP/`, `scripts/`. The NLP
service container needs `NLP/` inside the image — **remove those exclusions
before building** or the NLP task will fail with `FileNotFoundError`.

The Dockerfile runtime stage (`python:3.12-slim`) does not include `curl` or
`jq` (required by `start.sh`). The market task installs them at runtime via
`apt-get` (see `terraform/modules/market_task/main.tf`). For faster cold-starts,
bake them into the Dockerfile:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

### `.env` handling

`start.sh` sources `.env`, falling back to `.env.example` if missing. Inside the
container, neither file contains real values. The market task module writes a
fresh `.env` from ECS-injected secret env vars **before** `start.sh` runs, so
the source step picks up the correct credentials.

## Bootstrap

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: fill real secret values, choose schedule.

terraform init
terraform plan
terraform apply
```

Outputs after apply:

```
ecr_repository_url            = "<acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster"
ecs_cluster_name              = "mqsmaster-prod-cluster"
market_task_definition_family = "mqsmaster-prod"
nlp_task_definition_family    = "mqsmaster-prod-nlp"
nlp_service_name              = "mqsmaster-prod-nlp"
log_group_name                = "/ecs/mqsmaster-prod"
```

## First image push

Terraform creates an empty ECR repo. Scheduled tasks will fail with
`CannotPullContainerError` until the first image is pushed. Either let CI/CD
push (after merging to main) or push manually:

```bash
cd /Users/abhinav/Desktop/MQSMaster
aws ecr get-login-password --region us-east-2 \
  | docker login --username AWS --password-stdin <acct>.dkr.ecr.us-east-2.amazonaws.com
docker build -t mqsmaster:latest .
docker tag mqsmaster:latest <acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster:latest
docker push <acct>.dkr.ecr.us-east-2.amazonaws.com/mqsmaster:latest
```

## Secrets

Initial values come from `terraform.tfvars`. After apply, the
`aws_secretsmanager_secret_version` resources have `ignore_changes` set, so
future console rotations are not overwritten by Terraform.

```bash
aws secretsmanager put-secret-value \
  --secret-id mqsmaster-prod/db \
  --secret-string '{"db_user":"admin","password":"new","host":"...","port":"25060","database":"mqsdb","sslmode":"prefer"}'
```

## Schedule

Default uses **EventBridge Scheduler** with `America/St_Johns` timezone, so the
trigger fires at the same local clock time year-round despite NST/NDT. Override
`schedule_expression` (cron format) and `schedule_timezone` in
`terraform.tfvars`.

To fall back to a UTC EventBridge Rule, set `use_scheduler_timezone = false`
and pick a UTC cron in `schedule_expression`.

## Manually trigger the market task

```bash
cd terraform/
aws ecs run-task \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task-definition $(terraform output -raw market_task_definition_family) \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json task_subnet_ids | jq -r 'join(",")')],securityGroups=[$(terraform output -raw task_security_group_id)],assignPublicIp=ENABLED}"
```

## Logs

```bash
aws logs tail /ecs/mqsmaster-prod --since 1h --follow
```

## Cost notes

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| Market task (Fargate, scheduled) | 2 vCPU / 8 GB × ~7 h × 21 days ≈ 147 h | ~$11-15 |
| NLP service (Fargate, always-on) | 0.5 vCPU / 2 GB × 730 h | ~$14-18 |
| NLP service (alt, smaller) | 0.25 vCPU / 2 GB × 730 h | ~$8-11 |
| ECR storage | a few image revisions | ~$0.10 |
| Secrets Manager | 2 secrets × $0.40 | $0.80 |
| CloudWatch logs | volume-dependent | ~$2-3 |
| **Total (default sizing)** | | **~$30-37/mo** |
| **Total (smaller NLP)** | | **~$25-30/mo** |

Compare always-on `t3.large` (single instance running both workloads): ~$60/mo
plus EBS, with no per-workload scaling and manual lifecycle management.

To shrink NLP further set `nlp_task_cpu = "256"` in `terraform.tfvars`. FinBERT
inference still fits but throughput drops.

## Future work

- Move Terraform state to an S3 backend with DynamoDB lock (commented stub in `backend.tf`).
- Add a stop-task EventBridge schedule as a safety net in case `is_market_open`
  keeps returning true past close.
- Wire a CloudWatch Alarm + SNS to page on task failures (`ECSTaskStateChange`).
- Use FARGATE_SPOT for the NLP service to cut cost ~70% (tolerate occasional restarts).
- Promote `terraform/` into per-environment workspaces (`environments/prod`, `environments/dev`) once a non-prod environment exists.
