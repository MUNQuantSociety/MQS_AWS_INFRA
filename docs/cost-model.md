# Cost model

Estimates for `us-east-2` at the default sizing in `variables.tf`.

## Compute + supporting services

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| Market task (Fargate, scheduled) | 2 vCPU / 8 GB × ~7 h × 21 days ≈ 147 h | ~$11–15 |
| NLP service (Fargate, always-on) | 0.5 vCPU / 2 GB × 730 h | ~$14–18 |
| NLP service (alt, smaller) | 0.25 vCPU / 2 GB × 730 h | ~$8–11 |
| ECR storage | a few image revisions | ~$0.10 |
| Secrets Manager | 2 secrets × $0.40 | $0.80 |
| CloudWatch Logs | volume-dependent | ~$2–3 |
| **Subtotal (default sizing)** | | **~$30–37/mo** |
| **Subtotal (smaller NLP)** | | **~$25–30/mo** |

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

## Comparison — standalone EC2 build

A single always-on EC2 instance running both workloads plus a self-hosted Postgres.
Recomputed 2026-07-28; the earlier `t3.large` / ~$60 figure in this doc was the raw
on-demand price of an **undersized** box and is superseded by the numbers below.

Unit rates **in this section** are `us-east-2` list prices verified 2026-07-28 (AWS
pricing calculator rate maps, EBS and VPC pricing pages), quoted inline next to each
line so the arithmetic is auditable. The Fargate and RDS sections above were not
re-verified in this pass.

### Sizing envelope

The box has to hold everything that is concurrently live during a market day:

| Workload | Requested | Source |
|---|---|---|
| Market task | 2 vCPU / 8 GB | `market_task_cpu` / `market_task_memory` |
| NLP service | 0.5 vCPU / 2 GB | `nlp_task_cpu` / `nlp_task_memory` |
| Postgres (replacing `db.t4g.medium`) | 2 vCPU / 4 GB | `db_instance_class` |
| OS + agents | — / ~1 GB | |
| **Peak concurrent** | **~4.5 vCPU / ~15 GB** | |

A `t3.large` is 2 vCPU / 8 GB — roughly **half** the required memory. The floor for a
genuine single-box build is a 4 vCPU / 16 GB instance. vCPU is mildly oversubscribed
(4.5 requested vs 4 available), which is tolerable because the Fargate values are
allocation ceilings rather than sustained draw.

### Instance options at that envelope

| Instance | Sizing | $/h | $/mo (730 h) | Note |
|---|---|---|---|---|
| `t3.xlarge` | 4 vCPU / 16 GB | $0.1664 | ~$121 | Burstable — see below |
| `m7g.xlarge` | 4 vCPU / 16 GB (Graviton) | $0.1632 | ~$119 | Needs an `arm64` image build |
| `m7i.xlarge` | 4 vCPU / 16 GB (x86) | $0.2016 | ~$147 | Matches today's `amd64` CI build |
| `m8g.xlarge` | 4 vCPU / 16 GB (Graviton) | $0.1795 | ~$131 | Newer gen, `arm64` |

On burstable: `t3.xlarge` baseline is 40% of 4 vCPU = 1.6 vCPU sustained. Average draw
is roughly 878 vCPU-h/mo (market 2 × 147 h, NLP 0.5 × 730 h, Postgres ~0.3 × 730 h)
against a 1,168 vCPU-h baseline allowance, and the idle overnight hours refill credits
faster than a 7-hour market run drains them. So T3 Unlimited should cost ~$0 in steady
state — but a long or heavy run that empties the balance bills the surcharge
($0.05/vCPU-h, Linux), and that is a real line item, not a footnote.

`m7g.xlarge` is the cheapest option that is not burstable, but `MQSMaster/Dockerfile`
is built `amd64` by CI today; Graviton requires a multi-arch build first. The costed
default below is therefore `m7i.xlarge`.

### Full standalone bill (`m7i.xlarge`)

| Component | Sizing | Rate | Cost/mo |
|---|---|---|---|
| EC2 on-demand | `m7i.xlarge`, 730 h — always-on, the NLP service means it can't be stopped | $0.2016/h | ~$147 |
| EBS gp3 — root | 30 GB | $0.08/GB-mo | ~$2.40 |
| EBS gp3 — Postgres data | 100 GB (matches `db_allocated_storage`) | $0.08/GB-mo | ~$8.00 |
| EBS snapshots | ~130–150 GB effective, 7-day retention | $0.05/GB-mo | ~$6–8 |
| Public IPv4 | 1 address × 730 h | $0.005/h | ~$3.65 |
| ECR storage | unchanged, if still container-based | | ~$0.10 |
| Secrets Manager | 2 secrets × $0.40 | | $0.80 |
| CloudWatch Logs | volume-dependent, plus CW agent on the box | | ~$2–3 |
| **Total** | | | **~$170–175/mo** |

gp3 includes 3,000 IOPS and 125 MB/s at no extra charge, so no provisioned-performance
line is needed at this size. The snapshot line assumes the data volume is largely full;
EBS snapshots bill incrementally on *used* blocks, so a mostly-empty 100 GB volume
snapshots for considerably less.

On Graviton (`m7g.xlarge`) the same build lands at **~$143/mo**; on `t3.xlarge`,
**~$145/mo** assuming the credit balance holds.

### The headline

**A standalone EC2 build is not cheaper.** ~$170/mo (or ~$143 on Graviton) against
**~$100–120/mo** for the current Fargate + RDS stack. The saving implied by the old
`t3.large` line only existed because the box was sized to about half the workload.
The structural reason: Fargate bills the market task for ~147 h/mo, while a single
box has to stay up 730 h/mo for the always-on NLP service.

### Where EC2 does win

Split the single box in two — a small always-on instance for NLP + Postgres, and a
larger instance started and stopped around the ~147 market hours:

| Component | Sizing | Cost/mo |
|---|---|---|
| Always-on box (NLP + Postgres) | `t3.large` (2 vCPU / 8 GB), 730 h @ $0.0832/h | ~$61 |
| Market box (start/stop) | `t3.xlarge` (4 vCPU / 16 GB), ~147 h @ $0.1664/h | ~$24 |
| EBS gp3 + snapshots | 130 GB + snapshots | ~$17 |
| IPv4 × 2, ECR, Secrets, Logs | | ~$11 |
| **Total** | | **~$113/mo** |

Apply the same sizing discipline here as above. The market task alone requests
2 vCPU / **8 GB**, so with ~1 GB of OS overhead a `t3.large` market box does not fit —
`t3.xlarge` is the honest floor, which is why that row is $24 and not $12. The
always-on box is also oversubscribed: NLP 0.5 + Postgres 2 = 2.5 vCPU on 2 vCPU, and
7 GB of 8 GB memory. Tolerable, but with no headroom. On Graviton an `r7g.large`
(2 vCPU / 16 GB, $0.1071/h) is a better market box at ~$16, at the cost of an `arm64`
build — and mixing arches across the two boxes means maintaining two image builds.

So even in its best variant the split lands **inside** the $100–120 Fargate + RDS range
rather than under it: EC2 does not beat the managed stack here, it matches it. It is
also no longer a standalone single-box build, and it adds start/stop orchestration that
EventBridge + Fargate gives for free.

### What you give up

Independent of price, the standalone build loses:

- **No per-workload scaling** — one box, one failure domain, one resize decision
- **No managed backups or PITR** — `pg_dump`/snapshots on a cron you own
- **No failover** — `db_multi_az` has no equivalent; an AZ loss is an outage
- **Manual lifecycle** — OS patching, Postgres upgrades, disk growth, log rotation
- **No task isolation** — a market-task OOM can take down the NLP service and the DB

### Levers on the standalone build

| Lever | Change | Saving |
|---|---|---|
| Graviton | multi-arch image, `m7g.xlarge` | ~$28/mo |
| 1-year Compute Savings Plan | commit to the always-on box | ~35–40% of the EC2 line (approximate — verify current SP rates) |
| | *Does not flip the comparison: Fargate has Compute Savings Plans and RDS has Reserved Instances, and the $100–120 baseline above includes neither.* | |
| SSM Parameter Store | replace Secrets Manager | ~$0.80/mo |
| Drop the public IPv4 | private subnet + SSM Session Manager | **negative** — needs a NAT gateway (~$33/mo) or interface endpoints (~$21/mo); the $3.65 public IP is the cheap path |
