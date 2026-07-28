###############################################################################
# Networking pieces the upstream terraform-aws-modules/vpc module does not
# provide: the egress-only task security group, and the free S3 gateway
# endpoint.
#
# The VPC itself (subnets, IGW, NAT, route tables) is built by module.vpc in the
# root composition; this module only decorates it.
###############################################################################

# Egress-only: no ingress rules at all, so nothing can reach the tasks, but the
# tasks can reach anything. This is what keeps the NLP service and the scheduled
# market task able to call FMP / Alpha Vantage / Apify from private subnets --
# their traffic leaves via the NAT gateway. Adding a new data provider requires
# no change here.
resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Egress-only SG for MQSMaster Fargate tasks"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound (DB, third-party APIs, ECR, Secrets Manager, logs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Gateway endpoints are free, and ECR stores image layers in S3. Routing those
# pulls through the endpoint instead of the NAT gateway removes the bulk of NAT
# data-processing charges ($0.045/GB) on every task start.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
  }
}
