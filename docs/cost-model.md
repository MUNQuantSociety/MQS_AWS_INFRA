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

## Comparison

A single always-on `t3.large` running both workloads plus a local Postgres is
~$60/mo plus EBS — cheaper on paper, but with no per-workload scaling, no managed
backups, no failover, and manual lifecycle management.
