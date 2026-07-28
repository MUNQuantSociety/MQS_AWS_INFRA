# MQSMaster AWS Infrastructure

Terraform that provisions ECS Fargate and a managed Postgres to run the
[`MQSMaster`](../MQSMaster) quantitative trading project.

- **NLP service** (always-on): runs `python NLP/main_NLP.py` 24/7. ECS restarts it on crash.
- **Market task** (scheduled, Mon–Fri): EventBridge fires at the 09:30 ET market open
  (11:00 `America/St_Johns`). The container runs `start.sh` and exits when the market
  closes. The trigger must not be moved earlier — `start.sh` shuts the session down if
  the market is not already open when it first checks.

## Documentation

| Doc | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Diagram, workload split, secret wiring, image caveats |
| [docs/operations.md](docs/operations.md) | Deploy, first image push, manual runs, logs, secret rotation |
| [docs/cost-model.md](docs/cost-model.md) | Monthly estimate and the levers that move it |

## Repo layout

```
MQS_AWS_INFRA/
├── README.md
├── .env.example
├── .github/workflows/deploy.yml            # CI/CD: build → ECR → register/deploy
├── docs/
│   ├── architecture.md
│   ├── operations.md
│   └── cost-model.md
└── terraform/
    ├── environments/
    │   └── prod/                           # One state file per environment
    │       ├── main.tf                     # Module composition
    │       ├── locals.tf                   # name_prefix, log group, secret wiring
    │       ├── variables.tf                # All input variables
    │       ├── outputs.tf                  # Top-level outputs
    │       ├── providers.tf                # AWS provider + default tags
    │       ├── terraform.tf                # Terraform + provider version pins
    │       ├── backend.tf                  # S3 + DynamoDB backend stub
    │       ├── moved.tf                    # State shims for the module rename
    │       └── terraform.tfvars.example    # Copy → terraform.tfvars
    └── modules/
        ├── networking/                     # Egress-only task SG + free S3 gateway endpoint
        ├── ecr-repository/                 # ECR repo + lifecycle policy
        ├── iam-roles/                      # Task execution + task roles, secrets policy
        ├── secrets-manager/                # DB credentials + API keys
        ├── cloudwatch-logs/                # Log group + retention
        ├── rds-postgres/                   # RDS instance, subnet group, DB SG
        ├── ecs-cluster/                    # Cluster + Fargate capacity providers
        ├── ecs-task-market/                # Market-hours task definition
        ├── ecs-service-nlp/                # Always-on task definition + ECS Service
        └── eventbridge-scheduler/          # Scheduler/Rule + RunTask IAM role
```

**Conventions.** Module directories are kebab-case and named for the AWS service
they own (`ecs-service-nlp`, not `nlp_service`). Terraform identifiers — module
labels, variables, outputs — stay snake_case per the HashiCorp style guide. Every
module has the same three files: `main.tf`, `variables.tf`, `outputs.tf`, and
exposes exactly one resource group.

Adding an environment is a directory copy — see
[operations.md](docs/operations.md#adding-a-new-environment).

## Prerequisites

1. AWS credentials with sufficient IAM permissions, configured locally
   (`aws configure` — requires an **access key**, not console sign-in credentials).
2. Terraform >= 1.5.
3. The MQSMaster repo on GitHub with a `Dockerfile` at the root.
4. GitHub OIDC provider configured in AWS (one-time). Create an IAM role trusted by
   `token.actions.githubusercontent.com` with ECR push plus
   `ecs:DescribeTaskDefinition` / `ecs:RegisterTaskDefinition` / `ecs:UpdateService`,
   then store its ARN in the repo secret `AWS_DEPLOY_ROLE_ARN`.

## Quickstart

```bash
cd terraform/environments/prod && cp terraform.tfvars.example terraform.tfvars && terraform init -upgrade && terraform plan
```

Full deploy steps in [docs/operations.md](docs/operations.md#deploy).

## AWS services used

| Service | Purpose |
|---|---|
| **ECS (Fargate)** | Runs both workloads — one long-lived Service, one scheduled task |
| **ECR** | Container image registry, with a lifecycle policy to expire old images |
| **RDS (PostgreSQL)** | Managed database, private, reachable only from the task SG |
| **EventBridge Scheduler** | Timezone-aware Mon–Fri cron that calls ECS `RunTask` |
| **Secrets Manager** | DB credentials and API keys, injected by ECS at task start |
| **CloudWatch Logs** | Single log group for both workloads, split by stream prefix |
| **IAM** | Task execution role, task role, scheduler invoke role |
| **VPC / EC2 networking** | Purpose-built VPC: private subnets for all workloads, public subnets for the IGW + a single NAT gateway, free S3 gateway endpoint, two managed security groups |

## Future work

- Move state to the S3 backend + DynamoDB lock (stub in `backend.tf`).
- Add a stop-task schedule as a safety net if `is_market_open` stays true past close.
- CloudWatch Alarm + SNS on `ECSTaskStateChange` failures.
- FARGATE_SPOT for the NLP service (~70% cheaper, tolerates restarts).
- Second NAT gateway for HA egress (`single_nat_gateway = false`, ~+$32/mo) if
  the batch workload ever becomes latency- or availability-critical.
