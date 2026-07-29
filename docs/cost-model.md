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
| NAT instance (fck-nat) | `t4g.nano`, $0.0042/h × 730 h | ~$3.07 |
| NAT instance root volume | 8 GB gp3 | ~$0.64 |
| Elastic IP | in-use public IPv4, $0.005/h | ~$3.65 |
| NAT data transfer | standard EC2 rates, ~1 GB/mo | ~$0.10 |
| S3 gateway endpoint | free — carries ECR image layer pulls | $0 |
| VPC, subnets, route tables, IGW | no hourly charge | $0 |
| **Subtotal** | | **~$7.50/mo** |

Egress runs on a **NAT instance, not a managed NAT gateway**. A gateway is
~$33/mo, and ~97% of that is the fixed hourly charge — this stack pushes on the
order of 1 GB/mo through it, because ECR image layers already bypass NAT via the
S3 gateway endpoint. At that volume you are paying gateway prices for kernel
packet forwarding, so the same masquerade runs on a `t4g.nano` for ~$7.50/mo.

What that trade costs:

- **You own an EC2 instance** — patching and AMI refresh are yours, where a
  gateway is fully managed. `auto_rollout` can cycle instances onto new AMIs.
- **~2–3 minutes of no egress** while the ASG replaces a failed instance. A
  gateway has no equivalent gap. Acceptable here because API calls retry; not
  acceptable for anything latency- or availability-critical.
- Throughput is capped by instance size rather than scaling to 100 Gbps.

What it does **not** cost: the egress IP is still stable (a pinned EIP, not the
ephemeral address fck-nat uses by default), and the topology is unchanged —
workloads stay in private subnets with no inbound path.

Two other choices hold the bill down:

- The **free S3 gateway endpoint** keeps ECR image layer pulls off the NAT.
  Without it, every task start would push a multi-GB image pull across a
  `t4g.nano` — this matters more with an instance than it did with a gateway.
- Interface endpoints for ECR/Secrets/Logs were considered and rejected: at
  ~$7.20/mo each **per AZ** they cost more than the NAT they would replace, and
  they cannot carry the third-party API traffic (FMP, Alpha Vantage, Apify) that
  is the actual reason egress exists.

Reverting to a managed NAT gateway is `enable_nat_gateway = true` +
`single_nat_gateway = true` on `module.vpc`, minus `module.fck_nat`.

## Database

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| RDS instance | `db.t4g.medium`, single-AZ | ~$50–60 |
| gp3 storage | 100 GB allocated | ~$12 |
| Backups | 7-day retention | ~$5–10 |
| **Subtotal** | | **~$67–82/mo** |

Setting `db_multi_az = true` roughly doubles the instance and storage lines.

## Total

**~$105–127/mo** at defaults (compute ~$30–37, networking ~$7.50, database
~$67–82). RDS dominates — it is roughly two-thirds of the bill.

Before the private-subnet migration this was ~$100–120/mo, with tasks running in
the default VPC on public IPs and no NAT at all. The ~$7.50/mo delta buys
workloads with no inbound path from the internet and a stable egress IP. Using a
managed NAT gateway instead would put the total at ~$130–152/mo.

## Levers

| Lever | Change | Saving |
|---|---|---|
| Smaller NLP task | `nlp_task_cpu = "256"` | ~$6/mo — FinBERT still fits, throughput drops |
| FARGATE_SPOT for NLP | capacity provider swap | ~70% of the NLP line, at the cost of occasional restarts |
| Smaller RDS | `db.t4g.small` | ~$25/mo, if the working set fits in 2 GB |
| Shorter log retention | `log_retention_days = 7` | ~$1/mo |
| Drop NAT entirely | public subnets + `assign_public_ip = true` | ~$4/mo net — the always-on task then pays its own public IPv4 charge, and you lose the stable egress IP |
| Disable storage autoscaling | `db_max_allocated_storage = db_allocated_storage` | caps unplanned growth |

## Comparison

A single always-on `t3.large` running both workloads plus a local Postgres is
~$60/mo plus EBS — cheaper on paper, but with no per-workload scaling, no managed
backups, no failover, and manual lifecycle management.
