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

## Networking

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| NAT gateway | 1 × $0.045/h × 730 h (`single_nat_gateway = true`) | ~$32 |
| NAT data processing | $0.045/GB — JSON API responses only | ~$1 |
| S3 gateway endpoint | free — carries ECR image layer pulls | $0 |
| VPC, subnets, route tables, IGW | no hourly charge | $0 |
| **Subtotal** | | **~$33/mo** |

The NAT gateway is the whole networking bill. Two choices hold it down:

- `single_nat_gateway = true` — one NAT for all AZs instead of one per AZ, which
  would be ~$97/mo. The trade is a single-AZ failure point for egress.
- The **free S3 gateway endpoint** keeps ECR image layer pulls off the NAT.
  Without it, every task start would push a multi-hundred-MB image pull through
  NAT data processing. Interface endpoints for ECR/Secrets/Logs were considered
  and rejected: at ~$7.20/mo each **per AZ**, four of them across 3 AZs costs
  more than the NAT they would replace.

## Database

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| RDS instance | `db.t4g.medium`, single-AZ | ~$50–60 |
| gp3 storage | 100 GB allocated | ~$12 |
| Backups | 7-day retention | ~$5–10 |
| **Subtotal** | | **~$67–82/mo** |

Setting `db_multi_az = true` roughly doubles the instance and storage lines.

## Total

**~$133–153/mo** at defaults (compute ~$30–37, networking ~$33, database ~$67–82).
RDS still dominates at roughly half the bill; the NAT gateway is the next single
largest line.

Before the private-subnet migration this was ~$100–120/mo, with tasks running in
the default VPC on public IPs and no NAT. The ~$33/mo delta buys workloads with
no inbound path from the internet and a single stable egress IP.

## Levers

| Lever | Change | Saving |
|---|---|---|
| Smaller NLP task | `nlp_task_cpu = "256"` | ~$6/mo — FinBERT still fits, throughput drops |
| FARGATE_SPOT for NLP | capacity provider swap | ~70% of the NLP line, at the cost of occasional restarts |
| Smaller RDS | `db.t4g.small` | ~$25/mo, if the working set fits in 2 GB |
| Shorter log retention | `log_retention_days = 7` | ~$1/mo |
| Drop NAT entirely | public subnets + `assign_public_ip = true` | ~$33/mo, at the cost of a public IP on every task |
| Disable storage autoscaling | `db_max_allocated_storage = db_allocated_storage` | caps unplanned growth |

## Comparison

A single always-on `t3.large` running both workloads plus a local Postgres is
~$60/mo plus EBS — cheaper on paper, but with no per-workload scaling, no managed
backups, no failover, and manual lifecycle management.
