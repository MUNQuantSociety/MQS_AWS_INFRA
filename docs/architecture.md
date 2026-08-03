# Architecture

Two workloads share one container image, one ECS cluster, and one RDS instance.

```
GitHub Actions ──build──▶ ECR (livetradingbot)
                              │
                   ┌──────────┴──────────────────────────────────────────┐
                   ▼                                                     ▼
ECS Service mqsmaster-prod-nlp           EventBridge Scheduler ──▶ ECS RunTask mqsmaster-prod
  always-on Fargate                        cron @ 11:00 America/St_Johns   (market task, ephemeral)
  desired_count = 1                        Mon–Fri                         start.sh (NLP stripped)
  python NLP/main_NLP.py                                                   market scripts:
                                                                            src/main.py
                                                                            realtimeDataIngestor.py
                                                                            pnl_script.py
                                                                            refresh.py
                                                                            rbp_runner.py
                                                                          exits when market closes
                              │
                              ├── RDS PostgreSQL (private subnets, task SG only)
                              ├── SSM Parameter Store (db creds, API keys)
                              └── CloudWatch Logs (/ecs/mqsmaster-prod, streams: mqsmaster/*, nlp/*)
```

## Workloads

| Workload | Module | Lifecycle | Entrypoint |
|---|---|---|---|
| NLP service | `ecs-service-nlp` | Always-on ECS Service, restarts on crash | `python NLP/main_NLP.py` |
| Market task | `ecs-task-market` | Ephemeral, EventBridge-triggered Mon–Fri | `start.sh` (NLP block stripped at runtime) |

## Network topology

Both workloads run in a purpose-built VPC (`10.0.0.0/16`), not the default VPC.

```
VPC 10.0.0.0/16
├── public subnets  10.0.4-5.0/24   IGW + one NAT gateway. No workloads.
└── private subnets 10.0.1-2.0/24   Fargate tasks + RDS. No public IPs.
                                     └── 0.0.0.0/0 ──▶ NAT ──▶ IGW ──▶ internet
                                     └── S3 prefix ──▶ S3 gateway endpoint (free)
```

**Private does not mean isolated.** It means no inbound path and no public IP on
the task ENI. Outbound is unchanged from the operator's point of view:

| Destination | Path |
|---|---|
| FMP, Alpha Vantage, Apify (HTTPS) | private subnet → NAT → IGW |
| ECR image layers (S3-backed) | S3 gateway endpoint, bypasses NAT |
| SSM Parameter Store, CloudWatch Logs | private subnet → NAT → IGW |
| RDS | stays inside the VPC |

The task security group is **egress-only** — all protocols to `0.0.0.0/0`, zero
ingress rules. Adding a new data provider needs no VPC or SG change.

One behavioural change: outbound traffic now leaves from the NAT gateway's
Elastic IP rather than a per-task public IP. If a provider IP-allowlists you,
that EIP is the address to register, and it is stable across task restarts.

`modules/Livetrading/networking` owns the task SG and the S3 endpoint; the VPC itself comes
from `terraform-aws-modules/vpc` 6.6.0, composed in `main.tf`.

## Data flow

1. **Image** — GitHub Actions builds `MQSMaster/Dockerfile` and pushes to ECR. Both
   task definitions reference the same image URI.
2. **Secrets** — ECS pulls DB credentials and API keys from SSM Parameter Store
   (SecureString) at task start and injects them as container environment
   variables. The task *execution* role holds `ssm:GetParameters` scoped to the
   nine parameter ARNs; the task role does not.
3. **Database** — the RDS security group accepts Postgres traffic only from the
   Fargate task security group. There is no public endpoint.
4. **Logs** — both workloads write to `/ecs/mqsmaster-prod`, separated by stream
   prefix (`mqsmaster/*` vs `nlp/*`).

## Secret wiring

Each credential is its own SecureString parameter. Parameter Store has no
equivalent of the Secrets Manager `:json-key::` selector, so one parameter holds
exactly one value and its leaf name is the environment variable name:

```
/mqsmaster-prod/db/{db_user,password,host,port,database,sslmode}
/mqsmaster-prod/api/{FMP_API_KEY,ALPHA_KEY,APIFY_KEY}
```

`modules/Livetrading/ssm-parameters` owns the key lists (`local.db_keys`, `local.api_keys`)
and exports `parameter_arns`, a map of env var name => parameter ARN. `locals.tf`
turns that map straight into the ECS `secrets` block, so adding a credential in
the module propagates to both task definitions:

```hcl
container_secrets = [
  for name, arn in module.ssm_parameters.parameter_arns : {
    name      = name
    valueFrom = arn
  }
]
```

Parameters use the AWS-managed `alias/aws/ssm` key, which is why the execution
role needs no `kms:Decrypt`. Pointing the module's `kms_key_id` at a customer
managed key would require adding that grant, or tasks fail to start.

Credential values are never stored in Terraform state. Under the old Secrets
Manager arrangement `secret_string` sat in state in plaintext, readable by anyone
with access to the state file; `value_wo` removes that exposure entirely — the
provider explicitly nulls the `value` attribute on read whenever a write-only
value is in use.

The RDS master password gets the same treatment (`password_wo` /
`password_wo_version` in `modules/Livetrading/rds-postgres`), since the plain `password`
argument is also persisted to state. Its version counter is wired to
`db_parameter_version`, so a single bump rotates the database password and
`/mqsmaster-prod/db/password` together rather than letting them drift.

**What write-only does not cover.** Root variable values still appear in
cleartext inside *saved plan files* — `terraform plan -out=tf.plan` followed by
`terraform show -json tf.plan` exposes `.variables.db_secret_values.value`,
`sensitive = true` notwithstanding. That is inherent to Terraform variables, not
to these resources, and it applies to the API keys too. Treat any `-out` plan
file as secret material: don't commit one, don't attach one to a PR, delete it
after use. Plain `terraform plan` with no `-out` writes nothing to disk.

The DB `host`/`port` parameters are overwritten at apply time with the
provisioned RDS endpoint, so `db_secret_values.host` in `terraform.tfvars` is
ignored.

> Values are **write-only** (`value_wo`): sent to AWS but never persisted to
> state or plan files, and invisible to Terraform's differ. Updates fire only
> when `value_wo_version` changes, so console/CLI rotations survive
> `terraform apply` without needing `ignore_changes`. The trade-off: if RDS is
> ever **replaced** and gets a new endpoint, `/mqsmaster-prod/db/host` does not
> self-heal — bump `db_parameter_version`. See
> [operations.md](operations.md#rotating-secrets).

## Scheduling

Default path uses **EventBridge Scheduler** with the `America/St_Johns` IANA
timezone, so the trigger fires at the same local clock time year-round across the
NST/NDT transition. Setting `use_scheduler_timezone = false` falls back to a
classic EventBridge Rule evaluated in UTC, which drifts by an hour at DST
boundaries.

The scheduler targets the task definition **family** rather than a pinned
revision, so a CI-registered revision is picked up by the next scheduled run
without a Terraform apply.

### The trigger must not fire before the open

`start.sh` evaluates `is_market_open` on the **first** iteration of its monitor
loop, immediately after launching the market scripts. If the market is not open
at that moment it SIGTERMs every one of them and exits.

So the cron marks the market **open**, not a warm-up window. `cron(0 11 ? * MON-FRI *)`
in `America/St_Johns` is 09:30 ET, since Newfoundland runs ET+1:30. The earlier
08:00 default was 06:30 ET — three hours early — which ended the session seconds
after it started.

Container startup (image pull plus the `apt-get` curl/jq bootstrap) adds a couple
of minutes before that first check runs, comfortably clearing the open. Baking
curl and jq into the image removes that cushion; shift to 11:05 if you do.

## Image caveats

`MQSMaster/.dockerignore` excludes `scripts/`, `workflows/`, and `NLP/articles/`.
`NLP/` and `RBP/` are **no longer** wholesale-excluded, so the NLP service finds
its code — the earlier `FileNotFoundError` hazard is resolved. Nothing under
`src/`, `NLP/` or `RBP/` imports from `scripts/`, so that exclusion is safe.
`.env` is excluded too, which is correct: the market task writes a fresh one from
the ECS-injected secrets before `start.sh` runs.

The runtime stage (`python:3.12-slim`) ships without `curl` and `jq`, both
required by `start.sh`. The market task installs them at runtime via `apt-get`
(see `terraform/modules/Livetrading/ecs-task-market/main.tf`). Baking them into the image
removes that cold-start cost:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

## `.env` handling

`start.sh` sources `.env`, falling back to `.env.example`. Neither file holds real
values inside the container. The market task module writes a fresh `.env` from the
ECS-injected secret environment variables **before** `start.sh` runs, so the
source step picks up the correct credentials.
