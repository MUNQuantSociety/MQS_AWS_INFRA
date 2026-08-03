# Terraform — ECS Fargate for the backtest visualizer API (NO NAT; i.e. no stable egress IP for the external DB uses load balancer)

Provisions the AWS side of the `mqs-backtest-visualizer` FastAPI backend: an ECS
Fargate service behind an Application Load Balancer, with **no NAT gateway** and
**no database**. The market data Postgres is external to this stack.

This is one of two independent stacks in this repository:

| Stack | Workload | Network shape |
| --- | --- | --- |
| `environments/Livetrading` | MQSMaster trading bot + NLP service + RDS | Private subnets, single NAT gateway |
| `environments/Backtest_Visualizer` | This one — the visualizer API | Public subnets, **no NAT gateway** |

The two share no state, no VPC and no modules. Each consumes its own module
directory — `modules/Livetrading/` and `modules/Backtest_Visualizer/` — so a
change made for one stack cannot alter the other.

---

## What gets created

| Module | Resources |
| --- | --- |
| `terraform-aws-modules/vpc/aws` (registry, pinned `6.6.0`) | VPC, internet gateway, 2 public subnets, route tables |
| `security-groups` | ALB + service security groups |
| `alb` | Application Load Balancer, target group, HTTPS listener (and an optional HTTP redirect) |
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

- **If the external DB is the MQSMaster RDS** provisioned by
  `environments/Livetrading` in this same repository, it sits in *private*
  subnets with its security group scoped to that stack's task security group. It
  has no public endpoint at all. Nothing in this VPC reaches it over the internet
  — that needs VPC peering, `publicly_accessible = true`, or co-locating this
  service in the Livetrading VPC. Being in one repository does **not** put these
  two stacks on one network.
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

`modules/Backtest_Visualizer/ecs-service-api` carries a `precondition` that turns
this into a plan-time error instead of a silent runtime one.

---

## Layout

```
terraform/
├── environments/
│   ├── Livetrading/                    The other stack — untouched by this one
│   └── Backtest_Visualizer/            Root composition — run terraform here
│       ├── main.tf                     Wires the modules together
│       ├── variables.tf                Every input, with the reasoning on each
│       ├── locals.tf                   name_prefix, image URI, env/secret assembly
│       ├── outputs.tf                  api_base_url, ECR push target, service names
│       ├── backend.tf                  State backend — UNCONFIGURED, see below
│       └── terraform.tfvars.example
└── modules/
    ├── Livetrading/                    Consumed only by environments/Livetrading
    └── Backtest_Visualizer/            Consumed only by this stack
```

Modules are split by owning stack rather than pooled. Livetrading is live in HCP
Terraform, and a shared module edited for this stack would change resource
addresses in that stack's state — destroying and recreating production
resources. The split makes that impossible by construction. The cost is that
four small modules (`cloudwatch-logs`, `ecs-cluster`, `iam-roles`,
`ecr-repository`) exist in both trees and drift independently; that is the
intended trade.

## Usage

```bash
cd terraform/environments/Backtest_Visualizer

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # fill in every REPLACE_ME

terraform init
terraform plan
terraform apply
```

Requires Terraform >= 1.11 (write-only `value_wo` arguments) and valid AWS
credentials — `aws sts get-caller-identity` must succeed first.

### State backend

State lives in HCP Terraform. `terraform.tf` binds this stack to the workspace
**`MQS_AWS_INFRA_BTV`** in the `MQS` organization, which must exist before
`terraform init`. It does exist, with its working directory already set to
`/terraform/environments/Backtest_Visualizer`, and holds **no state** as of
2026-08-03 — zero resources and no run has ever executed, so the first apply
here is a full create.

That workspace is deliberately **separate** from Livetrading's
`MQS_AWS_INFRA_LIVE`. One workspace holds one state, so pointing both stacks at
a single workspace would make each one's plan propose destroying the other's
resources.

`backend.tf` holds no configuration — only a commented S3 alternative for taking
this stack off HCP.

`terraform.tf` carries this stack's `cloud` block and its provider requirements.
Both stacks declare their own — they were briefly shared through a symlinked
`../../shared/versions.tf`, which coupled each root module to a file outside its
own directory for the sake of six duplicated lines.

`required_version` is `>= 1.11.0`, because the SSM parameters use write-only
`value_wo` arguments introduced in that release. It is a floor, not a pin: the
workspace's own Terraform version still governs which release runs.

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
  `modules/Backtest_Visualizer/ssm-parameters` rather than overloading the market-data one.
- **The artifact bucket.** `artifact_bucket_arn` grants the task role access to a
  bucket; it does not create one.
- **DNS.** `alb_dns_name` / `alb_zone_id` are exported for a Route 53 alias
  record; no zone or record is managed here.
