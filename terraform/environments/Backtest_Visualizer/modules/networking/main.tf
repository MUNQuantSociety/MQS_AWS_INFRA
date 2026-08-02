###############################################################################
# Public-only VPC. There is deliberately NO NAT gateway and no private subnet
# tier.
#
# WHY: a NAT gateway is ~$32/mo for a single gateway before any data processing
# ($0.045/GB), and this workload has no inbound-facing reason to sit in private
# subnets -- the only thing that must be reachable from the internet is the ALB,
# and the only thing the tasks need is OUTBOUND access (external Postgres,
# Supabase JWKS, FMP, ECR image pulls, CloudWatch Logs).
#
# HOW EGRESS WORKS WITHOUT NAT: Fargate tasks run in these public subnets with
# assign_public_ip = true. The task ENI gets a public IP from the Amazon pool and
# routes 0.0.0.0/0 straight at the internet gateway. That is the entire reason
# assign_public_ip is NOT optional here -- see modules/ecs-service-api.
#
# WHAT THIS COSTS YOU: the task's public IP is ephemeral. It is drawn from the
# Amazon pool on every task start and changes on every deployment, scale event
# and crash restart. There is no stable egress IP to hand to a database that
# filters by source address. If the external Postgres enforces an IP allowlist
# (Supabase network restrictions, RDS SG rules, pg_hba.conf), this topology
# cannot satisfy it -- you would need a NAT gateway with an Elastic IP, which is
# the cost this module exists to avoid. See ../../README.md.
#
# SECURITY: "public subnet" does not mean "publicly reachable". The service
# security group below accepts ingress ONLY from the ALB security group, so the
# task's public IP is an egress path, not a front door.
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Two AZs minimum: an Application Load Balancer requires subnets in at least two
# availability zones. Subnets and route tables carry no hourly charge, so AZ
# count is a spread lever, not a cost lever.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# One route table for every public subnet -- they all take the same default
# route to the IGW, so per-subnet tables would differ only in name.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Security groups
#
# Note there is no S3 gateway endpoint here, unlike the MQSMaster config. That
# endpoint exists to keep ECR layer pulls off a metered NAT gateway. With no NAT
# gateway, image layers already leave via the IGW at no per-GB charge, so the
# endpoint would buy nothing.
###############################################################################

# Internet-facing: this is the only thing users talk to.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public ingress for the backtest visualizer ALB"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count = var.enable_http_listener ? length(var.ingress_cidr_blocks) : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${var.ingress_cidr_blocks[count.index]}"
  cidr_ipv4         = var.ingress_cidr_blocks[count.index]
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.certificate_arn == null ? 0 : length(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${var.ingress_cidr_blocks[count.index]}"
  cidr_ipv4         = var.ingress_cidr_blocks[count.index]
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to the API tasks on the container port"
  referenced_security_group_id = aws_security_group.service.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# The tasks. Ingress is ALB-only despite living in a public subnet with a public
# IP -- the public IP exists solely so egress can reach the internet without a
# NAT gateway.
resource "aws_security_group" "service" {
  name        = "${var.name_prefix}-service-sg"
  description = "Backtest visualizer Fargate tasks: ALB ingress, open egress"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-service-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "Container port from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# Open egress. The task must reach the external Postgres, Supabase's JWKS
# endpoint, FMP, ECR and CloudWatch Logs; per-host allowlisting here would break
# every time a provider rotated an IP. Adding a new data provider needs no
# change to this module.
resource "aws_vpc_security_group_egress_rule" "service_all" {
  security_group_id = aws_security_group.service.id
  description       = "All outbound (external DB, Supabase, third-party APIs, ECR, logs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
