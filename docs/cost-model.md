# Cost model

Estimates for `us-east-2` at the default sizing in `variables.tf`.

## Compute + supporting services

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| Market task (Fargate, scheduled) | 2 vCPU / 8 GB × ~7 h × 21 days ≈ 147 h | ~$11–15 |
| NLP service (Fargate, always-on) | 0.5 vCPU / 2 GB × 730 h | ~$14–18 |
| NLP service (alt, smaller) | 0.25 vCPU / 2 GB × 730 h | ~$8–11 |
| Refresh task (Fargate, weekly) | 1 vCPU / 2 GB × ~1 h × 4.3 runs ≈ 4.3 h | ~$0.20 |
| ECR storage | a few image revisions | ~$0.10 |
| Secrets Manager | 2 secrets × $0.40 | $0.80 |
| CloudWatch Logs | volume-dependent | ~$2–3 |
| **Subtotal (default sizing)** | | **~$30–37/mo** |
| **Subtotal (smaller NLP)** | | **~$25–30/mo** |

The weekly refresh is rounding error — it runs roughly 4 times a month and is
billed per second. The ~1 h estimate is a guess; check actual duration in the
`refresh/*` log streams after the first few runs and adjust if the backfill window
is much longer.

## Database

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| RDS instance | `db.t4g.medium`, single-AZ | ~$50–60 |
| gp3 storage | 100 GB allocated | ~$12 |
| Backups | 7-day retention | ~$5–10 |
| **Subtotal** | | **~$67–82/mo** |

Setting `db_multi_az = true` roughly doubles the instance and storage lines.

## Total

**~$100–120/mo** at defaults. RDS dominates — it is roughly two-thirds of the bill.

## Levers

| Lever | Change | Saving |
|---|---|---|
| Smaller NLP task | `nlp_task_cpu = "256"` | ~$6/mo — FinBERT still fits, throughput drops |
| FARGATE_SPOT for NLP | capacity provider swap | ~70% of the NLP line, at the cost of occasional restarts |
| Smaller RDS | `db.t4g.small` | ~$25/mo, if the working set fits in 2 GB |
| Shorter log retention | `log_retention_days = 7` | ~$1/mo |
| Disable storage autoscaling | `db_max_allocated_storage = db_allocated_storage` | caps unplanned growth |

## Comparison — self-managed EC2

**Settled: EC2 is not cheaper. Stay on Fargate + RDS.**

An earlier version of this doc claimed a single `t3.large` would run everything for
~$60/mo. That figure was wrong — it was the raw on-demand price of a box sized to
roughly **half** the workload. Peak concurrent demand is ~4.5 vCPU / ~15 GB (market
task 2 vCPU / 8 GB, NLP 0.5 vCPU / 2 GB, Postgres 2 vCPU / 4 GB, plus ~1 GB of OS
overhead), so 4 vCPU / 16 GB is the honest floor.

Costed properly at `us-east-2` list prices:

| Build | Cost/mo |
|---|---|
| **Fargate + RDS (current)** | **~$100–120** |
| Single EC2 box, `m7i.xlarge` + self-hosted Postgres | ~$170–175 |
| Same on Graviton, `m7g.xlarge` (needs an `arm64` image) | ~$143 |
| Split: small always-on box + start/stop market box | ~$113 |

**The structural reason:** Fargate bills the market task for only the ~147 h/mo it
actually runs, while any single box must stay up 730 h/mo for the always-on NLP
service. Even the best split variant lands *inside* the Fargate range rather than
under it — and it reintroduces start/stop orchestration that EventBridge gives for
free here.

Savings Plans don't flip this either: Fargate has Compute Savings Plans and RDS has
Reserved Instances, and the ~$100–120 baseline above includes neither.

Beyond price, self-managing gives up per-workload scaling, managed backups and PITR,
`db_multi_az` failover, task isolation (a market-task OOM would take down NLP and the
DB), and hands you OS patching and Postgres upgrades.

> Full working — instance-by-instance rates, EBS and IPv4 lines, the burstable-credit
> analysis — is on the `worktree-ec2-standalone-costmodel` branch. It is kept for
> reference; the conclusion above is what governs.
