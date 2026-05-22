data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task"
  description = "Egress-only SG for MQSMaster Fargate tasks"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound (DB, third-party APIs, ECR, Secrets Manager, logs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
