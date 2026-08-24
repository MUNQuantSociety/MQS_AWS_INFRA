# Cost model

Estimates for `us-east-2` at the default sizing in `variables.tf`.

## Compute + supporting services

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| Market task (Fargate, scheduled) | 2 vCPU / 8 GB × ~7 h × 21 days ≈ 147 h | ~$11–15 |
| ECR storage | a few image revisions | ~$0.10 |
| SSM Parameter Store | 9 Standard SecureString params | $0 |
| CloudWatch Logs | volume-dependent | ~$1–2 |
| **Subtotal** | | **~$12–17/mo** |

There is no always-on ECS Service. Fargate bills only for the hours the
scheduled session actually runs, so the compute line scales with market days,
not wall-clock time. The removed NLP service was ~$14–18/mo on its own.

Credential storage is free. Standard-tier parameters carry no storage charge
regardless of type — `SecureString` included — and at standard throughput there
is no per-API-call charge either, so the ~2 `GetParameters` calls per task start
cost nothing. The AWS-managed `alias/aws/ssm` key adds nothing; a customer
managed key would add **$1/mo**, more than the two Secrets Manager secrets this
replaced ($0.40 each). Advanced tier would be $0.05/parameter/month — $0.45/mo
for these nine — and buys only >4 KB values and policies, neither of which
applies here.

## Networking

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| NAT gateway | none — `task_in_public_subnet = true` | $0 |
| Public IPv4 on the task ENI | $0.005/h, only while a task runs (~147 h) | ~$0.75 |
| S3 gateway endpoint | free | $0 |
| VPC, subnets, route tables, IGW | no hourly charge | $0 |
| **Subtotal** | | **~$1/mo** |

**The networking bill is now rounding error, and that is the whole point of
running the task in the public subnets.** The task egresses straight out the IGW,
which charges nothing hourly and nothing per GB inbound. The only line left is
the public IPv4 address, billed hourly but *only while a task is running* — a
scheduled workload holds one for ~147 h/mo, not 730.

What this costs, and it is not money: **there is no stable egress IP.** Fargate
cannot hold an Elastic IP, so the task's public address is fresh on every run. A
NAT gateway's Elastic IP was the only thing providing a stable source address.
Set `task_in_public_subnet = false` to get it back at ~$32/mo — necessary if a
data provider IP-allowlists this stack, and pointless otherwise.

In that private mode the old numbers apply: ~$32/mo for one NAT gateway
(`single_nat_gateway = true`, versus ~$97/mo for one per AZ) plus ~$1/mo of NAT
data processing on JSON API responses. The **free S3 gateway endpoint** mattered
most there, keeping multi-hundred-MB ECR image pulls off NAT data processing at
every task start. Interface endpoints for ECR/SSM/Logs were considered and
rejected: at ~$7.20/mo each **per AZ**, four across 2 AZs costs more than the NAT
they would replace.

`az_count` is not a cost lever. It defaults to **2**, the floor imposed by RDS
subnet groups, and raising it changes nothing on the bill: subnets, route tables
and the IGW carry no hourly charge, and in private mode `single_nat_gateway` caps
NAT at one gateway whatever the AZ count.

## Database

| Component | Sizing | Cost/mo |
|-----------|--------|---------|
| RDS instance | `db.t4g.small`, single-AZ | ~$25–30 |
| gp3 storage | 100 GB allocated, 200 GB ceiling | ~$12 |
| Backups | 7-day retention | ~$5–10 |
| **Subtotal** | | **~$42–52/mo** |

Setting `db_multi_az = true` roughly doubles the instance and storage lines.

Storage bills on **allocated**, not used, so the 200 GB autoscaling ceiling costs
nothing until RDS actually grows into it — and once it does, that growth is
permanent. Allocated storage can never be reduced in place; shrinking means a
dump/restore into a new instance.

## Total

**~$55–70/mo** at defaults (compute ~$12–17, networking ~$1, database ~$42–52).
RDS is now essentially the entire bill; compute is a distant second and
networking has stopped registering.

History: ~$100–120/mo originally (tasks in the default VPC, no dedicated
networking), then ~$87–102/mo after the private-subnet migration added a NAT
gateway, now ~$55–70/mo after moving the task to the public subnets and dropping
that gateway. The task keeps its zero-ingress security group throughout, so the
inbound posture is the same in all three; what the current layout gives up
against the middle one is the stable egress IP, not isolation.

## Levers

| Lever | Change | Saving |
|---|---|---|
| Smaller market task | `market_task_cpu = "1024"` | ~$5/mo — longer sessions if the scripts are CPU-bound |
| FARGATE_SPOT for the market task | capacity provider swap | ~70% of the compute line; a mid-session interruption loses the session |
| Larger RDS | `db.t4g.medium` | **costs** ~$25/mo more — the upgrade path if 2 GB stops holding the working set |
| Shorter log retention | `log_retention_days = 7` | ~$1/mo |
| Restore a stable egress IP | `task_in_public_subnet = false` | **costs** ~$32/mo — the NAT gateway comes back. Only needed if a provider IP-allowlists you |
| Disable storage autoscaling | `db_max_allocated_storage = db_allocated_storage` | caps unplanned growth |

## Comparison

A single always-on `t3.large` running both workloads plus a local Postgres is
~$60/mo plus EBS — cheaper on paper, but with no per-workload scaling, no managed
backups, no failover, and manual lifecycle management.
