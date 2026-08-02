# Terraform — ECS Fargate for the backtest visualizer API

Provisions the AWS side of this repo's FastAPI backend: an ECS Fargate service
behind an Application Load Balancer, with **no NAT gateway** and **no database**.
The market data Postgres is external to this stack.

> The repo README says infrastructure lives in a separate repository and that
> there is no Terraform directory here by design. That was overridden
> deliberately — this stack lives alongside the code it deploys. If it is later
> moved into `MQS_AWS_INFRA`, the module layout below transplants unchanged.

---

## What gets created

| Module | Resources |
| --- | --- |
| `networking` | VPC, internet gateway, 2 public subnets, route table, ALB + service security groups |
| `alb` | Application Load Balancer, target group, HTTP (and optional HTTPS) listeners |
| `ecr-repository` | ECR repository + lifecycle policy for the API image |
| `ssm-parameters` | SecureString parameters for the external DB and third-party credentials |
| `iam-roles` | ECS task execution role (image pull, SSM read, logs) and task role |
| `cloudwatch-logs` | Log group for container output |
| `ecs-cluster` | ECS cluster with FARGATE / FARGATE_SPOT capacity providers |
| `ecs-service-api` | Task definition + always-on Fargate service |

There is **no RDS module** and **no private subnet tier**.

---

## The two trade-offs to understand before applying

### 1. No NAT gateway means no stable egress IP

A NAT gateway costs ~$32/mo for a single gateway plus $0.045/GB of data
processing. This stack removes it. Tasks run in **public subnets** with
`assign_public_ip = true` and egress straight through the internet gateway.

The task's public IP is drawn from the Amazon pool. **It changes on every
deployment, scale event and crash restart.** There is nothing stable to hand to
a database that filters by source address.

That breaks in two concrete ways:

- **If the external DB is the MQSMaster RDS** provisioned by `MQS_AWS_INFRA`, it
  sits in *private* subnets with its security group scoped to that stack's task
  security group. It has no public endpoint at all. Nothing in this VPC reaches
  it over the internet — that needs VPC peering, `publicly_accessible = true`, or
  co-locating this service in the MQSMaster VPC.
- **If the external DB enforces an IP allowlist** (Supabase network
  restrictions, an RDS security group rule, `pg_hba.conf`), there is no address
  to allowlist.

Either case means adding a NAT gateway with an Elastic IP — the exact cost this
topology exists to avoid. **Confirm the external host is publicly reachable and
does not filter by source IP before applying.**

Security is not the trade-off here: the service security group accepts the
container port from the ALB security group only. The public IP is an egress
path, not a front door.

### 2. `assign_public_ip` is not a knob

With no NAT gateway, a task ENI without a public IP has **no route off the VPC**
— not to the external database, not to Supabase, and not to ECR. The apply still
succeeds and the tasks then fail forever with `CannotPullContainerError`.

`modules/ecs-service-api` carries a `precondition` that turns this into a
plan-time error instead of a silent runtime one.

---

## Layout

```
terraform/
├── environments/prod/     Root composition — the only place you run terraform
│   ├── main.tf            Wires the modules together
│   ├── variables.tf       Every input, with the reasoning on each
│   ├── locals.tf          name_prefix, image URI, env/secret assembly
│   ├── outputs.tf         api_base_url, ECR push target, service names
│   ├── backend.tf         State backend — UNCONFIGURED, see below
│   └── terraform.tfvars.example
└── modules/               One concern each; no cross-module references
```

## Usage

```bash
cd terraform/environments/prod

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # fill in every REPLACE_ME

terraform init
terraform plan
terraform apply
```

Requires Terraform >= 1.11 (write-only `value_wo` arguments) and valid AWS
credentials — `aws sts get-caller-identity` must succeed first.

### State backend

`backend.tf` is **commented out**, so state is local. That is deliberate: it
keeps `init`/`validate` runnable without credentials or an HCP token. Local state
is not acceptable for shared infrastructure — uncomment either the HCP Terraform
block (matching `MQS_AWS_INFRA`, needs a workspace created in the MQS org) or the
S3 block, then re-run `terraform init` to migrate.

### First deploy

`desired_count` defaults to **0**. The ECR repository this config creates is
empty — this repo has no Dockerfile and no CI build yet — so a non-zero count
would leave ECS retrying `CannotPullContainerError` after an otherwise clean
apply.

```bash
# 1. build and push
aws ecr get-login-password --region us-east-2 \
  | docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url | cut -d/ -f1)
docker build -t $(terraform output -raw ecr_repository_url):latest .
docker push $(terraform output -raw ecr_repository_url):latest

# 2. scale up
$(terraform output -raw first_deploy_command)
```

Scaling stays with `update-service` / CI from that point on. The service sets
`ignore_changes = [task_definition, desired_count]`, so both are read only at
create time — editing `desired_count` in `terraform.tfvars` afterwards is a
no-op, and CI can register new task definition revisions without Terraform
reverting them on the next apply.

---

## Secrets

One SSM SecureString parameter per credential, never a JSON blob — ECS injects a
Parameter Store value whole and has no equivalent of the Secrets Manager
`:json-key::` selector. The parameter's leaf name **is** the environment variable
name, so `src/core/config.py` reads them with no special casing.

```
/mqs-btv-prod/market-data/MARKET_DATA_{HOST,PORT,DB,USER,PASSWORD,SSLMODE}
/mqs-btv-prod/api/{FMP_API_KEY,SUPABASE_ANON_KEY}
```

Values use write-only arguments: **they never enter Terraform state or plan
output.** The consequence is that Terraform cannot diff them either — an update
fires only when the paired counter changes:

```hcl
market_data_parameter_version = 2   # push the new market_data values
api_parameter_version         = 2   # push the new api values
```

Bumping rewrites *every* parameter in that group, discarding out-of-band
rotations. To rotate one credential, prefer `aws ssm put-parameter --overwrite`.

Non-secret configuration (`APP_ENV`, `LOG_LEVEL`, `CORS_ORIGINS`, the Supabase
URLs) goes through plain container environment variables in `locals.tf`. Anything
put there is visible in the task definition and in state — credentials belong in
`ssm-parameters`.

`MARKET_DATA_USER` must be a **read-only** role. The visualizer reads bars and
must never write to `positions_book`, `cash_equity_book`, or
`trade_execution_logs`.

---

## Cost

Rough monthly floor in `us-east-2`, before data transfer:

| Item | ~Cost |
| --- | --- |
| ALB (hourly + minimal LCU) | ~$17 |
| Fargate, 1 × 0.5 vCPU / 1 GB, always on | ~$18 |
| CloudWatch Logs + Container Insights | a few $ |
| NAT gateway | **$0 — removed** |
| SSM Standard parameters, ECR (<1 GB), VPC, subnets, IGW | $0 |

Levers, cheapest first: `container_insights_enabled = false`; drop
`log_retention_days`; `enable_alb = false` (loses the stable endpoint);
`cpu_architecture = "ARM64"` (~20% off Fargate, requires an ARM image);
`FARGATE_SPOT` as the default capacity provider (~70% off, two-minute
reclaim notice).

---

## Not covered here

- **The worker.** The repo README's architecture separates the API from a
  backtest worker consuming a Redis/SQS queue. Only the API is provisioned. The
  worker is a second `ecs-service-api`-shaped module with no load balancer and
  more CPU.
- **The application-schema database** (users, runs, metrics). Only the external
  read-only `market_data` connection is modelled. Add it as a third group in
  `modules/ssm-parameters` rather than overloading the market-data one.
- **The artifact bucket.** `artifact_bucket_arn` grants the task role access to a
  bucket; it does not create one.
- **DNS.** `alb_dns_name` / `alb_zone_id` are exported for a Route 53 alias
  record; no zone or record is managed here.
