###############################################################################
# Security groups for the backtest visualizer API.
#
# The VPC itself is built by the terraform-aws-modules/vpc/aws registry module in
# the root composition -- the same module and pinned version Livetrading uses.
# This module only decorates it, which mirrors how modules/Livetrading/networking
# relates to that stack's VPC.
#
# The pairing that matters: tasks sit in PUBLIC subnets with a public IP, because
# with no NAT gateway that public IP is their only route to ECR, the external
# Postgres and Supabase. "Public subnet" is not "publicly reachable" -- the
# service group below accepts the container port from the ALB group and nothing
# else, so the public IP is an egress path, not a front door.
#
# There is deliberately no S3 gateway endpoint here, unlike modules/Livetrading/
# networking. That endpoint exists to keep ECR layer pulls off a metered NAT
# gateway; with no NAT, image layers already leave via the IGW at no per-GB
# charge, so it would buy nothing.
###############################################################################

# Internet-facing: this is the only thing users talk to.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public ingress for the backtest visualizer ALB"
  vpc_id      = var.vpc_id

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
  vpc_id      = var.vpc_id

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
