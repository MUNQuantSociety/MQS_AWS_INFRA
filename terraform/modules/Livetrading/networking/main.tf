###############################################################################
# Networking pieces the upstream terraform-aws-modules/vpc module does not
# provide: the egress-only task security group, and the free S3 gateway
# endpoint.
#
# The VPC itself (subnets, IGW, NAT, route tables) is built by module.vpc in the
# root composition; this module only decorates it.
###############################################################################

# Egress-only: no ingress rules at all, so nothing can reach the tasks, but the
# tasks can reach anything. This is what keeps the scheduled market task able to
# call FMP / Alpha Vantage / Apify, and adding a new data provider requires no
# change here.
#
# The zero-ingress rule is also what makes a public subnet safe for this task.
# With task_in_public_subnet = true the ENI carries a public IP, but no port is
# reachable from the internet: the address is an egress source, not a door. Do
# not add an ingress rule here without re-reading that assumption.
resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Egress-only SG for MQSMaster Fargate tasks"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound (DB, third-party APIs, ECR, SSM Parameter Store, logs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Gateway endpoints are free, and ECR stores image layers in S3. Routing those
# pulls through the endpoint keeps them off the NAT gateway in private mode,
# where NAT data processing ($0.045/GB) would otherwise be charged on every task
# start. In public mode the egress path is the IGW, which does not charge per GB,
# so the endpoint is a smaller win there -- but it still short-circuits the hop.
#
# Associated with both subnet tiers' route tables so the endpoint applies
# wherever task_in_public_subnet places the task. Same-region S3 only --
# cross-region requests fall back to the normal egress path.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
  }
}
