# Architecture

Two workloads share one container image, one ECS cluster, and one RDS instance.

```
GitHub Actions ──build──▶ ECR (mqsmaster)
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
                              ├── RDS PostgreSQL (private, task SG only)
                              ├── Secrets Manager (db creds, API keys)
                              └── CloudWatch Logs (/ecs/mqsmaster-prod, streams: mqsmaster/*, nlp/*)
```

## Workloads

| Workload | Module | Lifecycle | Entrypoint |
|---|---|---|---|
| NLP service | `ecs-service-nlp` | Always-on ECS Service, restarts on crash | `python NLP/main_NLP.py` |
| Market task | `ecs-task-market` | Ephemeral, EventBridge-triggered Mon–Fri | `start.sh` (NLP block stripped at runtime) |

## Data flow

1. **Image** — GitHub Actions builds `MQSMaster/Dockerfile` and pushes to ECR. Both
   task definitions reference the same image URI.
2. **Secrets** — ECS pulls DB credentials and API keys from Secrets Manager at task
   start and injects them as container environment variables. The task *execution*
   role holds `secretsmanager:GetSecretValue`; the task role does not.
3. **Database** — the RDS security group accepts Postgres traffic only from the
   Fargate task security group. There is no public endpoint.
4. **Logs** — both workloads write to `/ecs/mqsmaster-prod`, separated by stream
   prefix (`mqsmaster/*` vs `nlp/*`).

## Secret wiring

`locals.tf` is the single source of truth for what ECS injects. Adding a key to
`container_secrets` propagates it to both task definitions:

```hcl
container_secrets = concat(
  [for k in ["db_user", "password", "host", "port", "database", "sslmode"] : {
    name = k, valueFrom = "${module.secrets_manager.db_secret_arn}:${k}::"
  }],
  [for k in ["FMP_API_KEY", "ALPHA_KEY", "APIFY_KEY"] : {
    name = k, valueFrom = "${module.secrets_manager.api_secret_arn}:${k}::"
  }],
)
```

The DB secret's `host`/`port` are overwritten at apply time with the provisioned
RDS endpoint, so `db_secret_values.host` in `terraform.tfvars` is ignored.

> The secret version carries `ignore_changes = [secret_string]` so console
> rotations survive `terraform apply`. The trade-off: if RDS is ever **replaced**
> and gets a new endpoint, the secret must be updated by hand. See
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

`MQSMaster/.dockerignore` currently excludes `NLP/`, `RBP/`, and `scripts/`. The
NLP service needs `NLP/` inside the image — **remove those exclusions before
building** or the NLP task fails with `FileNotFoundError`.

The runtime stage (`python:3.12-slim`) ships without `curl` and `jq`, both
required by `start.sh`. The market task installs them at runtime via `apt-get`
(see `terraform/modules/ecs-task-market/main.tf`). Baking them into the image
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
