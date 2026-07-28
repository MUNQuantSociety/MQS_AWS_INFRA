###############################################################################
# RDS PostgreSQL for MQSMaster.
#
# Provisions a managed Postgres instance in the default VPC's subnets, reachable
# only from the ECS Fargate tasks (ingress 5432 from the task security group).
# The instance endpoint + port are exported and wired into the DB secret so the
# market + NLP containers connect to this DB instead of an external host.
###############################################################################

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db"
  description = "Subnet group for MQSMaster RDS (default VPC subnets)"
  subnet_ids  = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db"
  description = "Postgres ingress from MQSMaster Fargate tasks only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from ECS tasks"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = [var.task_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage. gp3 under 400 GB runs at the fixed 3000 IOPS / 125 MBps baseline,
  # so iops/throughput are intentionally NOT set here (RDS rejects them < 400 GB).
  # max_allocated_storage > allocated_storage enables storage autoscaling.
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_period
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  # Safety. Defaults favour painless first setup/teardown; flip both for prod
  # (deletion_protection = true, skip_final_snapshot = false).
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-postgres-final"

  lifecycle {
    # Master password is managed via tfvars/Secrets Manager, not drift-corrected
    # on every apply if rotated out-of-band.
    ignore_changes = [password]
  }
}
