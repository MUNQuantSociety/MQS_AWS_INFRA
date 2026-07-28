# Architecture

Three workloads share one container image, one ECS cluster, and one RDS instance.

```
GitHub Actions ──build──▶ ECR (mqsmaster)
                              │
        ┌─────────────────────┼──────────────────────────────┐
        ▼                     ▼                              ▼
ECS Service              EventBridge Scheduler          EventBridge Scheduler
mqsmaster-prod-nlp         cron @ 11:00 Mon–Fri           cron @ 18:30 Fri
  always-on Fargate        America/St_Johns               America/St_Johns
  desired_count = 1        (= 09:30 ET open)              (= 1h after close)
  NLP/main_NLP.py                │                              │
                                 ▼                              ▼
                          RunTask mqsmaster-prod        RunTask mqsmaster-prod-refresh
                            start.sh, NLP stripped        refresh.py --threads 4
                            src/main.py                   exits when done
                            realtimeDataIngestor.py
                            pnl_script.py
                            rbp_runner.py
                            exits when market closes
        └─────────────────────┼──────────────────────────────┘
                              ├── RDS PostgreSQL (private, task SG only)
                              ├── Secrets Manager (db creds, API keys)
                              └── CloudWatch Logs (/ecs/mqsmaster-prod)
                                    streams: mqsmaster/*, nlp/*, refresh/*
```

## Workloads

| Workload | Module | Lifecycle | Entrypoint |
|---|---|---|---|
| NLP service | `ecs-service-nlp` | Always-on ECS Service, restarts on crash | `python NLP/main_NLP.py` |
| Market task | `ecs-task-market` | Ephemeral, EventBridge-triggered Mon–Fri | `start.sh` (NLP block stripped at runtime) |
| Refresh task | `ecs-task-refresh` | Ephemeral, weekly Friday after close | `refresh.py --threads 4` |

### Why `refresh.py` needs its own task definition

`refresh.py` is **not** in `start.sh`'s `market_scripts` array, so the market task
never runs it — before this module existed it was not scheduled anywhere. It lives
at `src/orchestrator/backfill/update/refresh.py` as a standalone CLI with its own
arguments, which is why `ecs-task-refresh` is a separate family rather than a
`RunTask` override on the market family.

`--threads` defaults to 4 and is bounded by `MQSDBConnector`'s
`ThreadedConnectionPool(maxconn=6)` — the script documents this constraint on the
argument itself. The module validates `refresh_threads` against that ceiling.

## Data flow

1. **Image** — GitHub Actions builds `MQSMaster/Dockerfile` and pushes to ECR. Both
   task definitions reference the same image URI.
2. **Secrets** — ECS pulls DB credentials and API keys from Secrets Manager at task
   start and injects them as container environment variables. The task *execution*
   role holds `secretsmanager:GetSecretValue`; the task role does not.
3. **Database** — the RDS security group accepts Postgres traffic only from the
   Fargate task security group. There is no public endpoint.
4. **Logs** — all three workloads write to `/ecs/mqsmaster-prod`, separated by
   stream prefix (`mqsmaster/*`, `nlp/*`, `refresh/*`).

### Connection budget

`MQSDBConnector` creates a `ThreadedConnectionPool(minconn=1, maxconn=6)` **per
process**. During market hours that is 4 market processes + 1 NLP process = up to
30 connections. The refresh task adds its own pool, but runs after the close when
the market processes are gone. `db.t4g.medium` (4 GB) gives `max_connections`
≈ 450, so there is ample room — worth rechecking if `db_instance_class` is ever
reduced.

## Secret wiring

`locals.tf` is the single source of truth for what ECS injects. Adding a key to
`container_secrets` propagates it to all three task definitions:

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
timezone, so triggers fire at the same local clock time year-round across the
NST/NDT transition. Setting `use_scheduler_timezone = false` falls back to
classic EventBridge Rules evaluated in UTC, which drift by an hour at DST
boundaries.

| Schedule | Default cron | Local time |
|---|---|---|
| `mqsmaster-prod-market-open` | `cron(0 11 ? * MON-FRI *)` | Mon–Fri 11:00 (= 09:30 ET open) |
| `mqsmaster-prod-refresh` | `cron(30 18 ? * FRI *)` | Friday 18:30 (= 1 h after close) |

**Why 18:30 for the refresh.** Newfoundland is ET+1:30, so the 16:00 ET close
lands at 17:30 local, and `start.sh`'s monitor loop polls `is_market_open` every
180 s — the market task exits within ~3 minutes of the close. 18:30 leaves roughly
an hour of margin, so the backfill never runs concurrently with live trading and
competes for neither DB connections nor API rate limits. **This offset is
timezone-specific**: changing `schedule_timezone` requires recomputing
`refresh_schedule_expression`.

Both schedules target the task definition **family** rather than a pinned
revision, so a CI-registered revision is picked up by the next scheduled run
without a Terraform apply.

The refresh schedule retries (2 attempts, 1 h window) where the market schedule
does not — a missed weekly job is otherwise seven days from its next attempt, and
a late start outside market hours is harmless.

### The market trigger must not fire before the open

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

`MQSMaster/.dockerignore` previously excluded `NLP/` and `RBP/`, which produced an
image that could not run either workload:

- `NLP/main_NLP.py` is the NLP service entrypoint — the service crash-looped.
- `RBP/` is imported by `src/orchestrator/rbp_runner.py` and
  `src/portfolios/portfolio_8/strategy.py`, with no `src/RBP` fallback. The import
  failed, and `start.sh` then took every other market script down with it.

Both exclusions have been removed. `NLP/articles/` stays excluded (~2.3 MB; the
article bodies are persisted to the database), while `NLP/fetch_state/` is kept —
the pipeline reads it to resume incremental fetches.

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

This applies only to the market task. The NLP service and the refresh task invoke
their Python entrypoints directly — no `start.sh`, so no `.env` materialisation
and no `curl`/`jq` bootstrap. They read the injected environment as-is.
