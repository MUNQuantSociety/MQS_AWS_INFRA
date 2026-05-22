resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name_prefix}/db"
  description             = "MQSMaster Postgres credentials"
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode(var.db_secret_values)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "api" {
  name                    = "${var.name_prefix}/api-keys"
  description             = "MQSMaster third-party API keys (FMP, ALPHA, APIFY)"
  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "api" {
  secret_id     = aws_secretsmanager_secret.api.id
  secret_string = jsonencode(var.api_secret_values)

  lifecycle {
    ignore_changes = [secret_string]
  }
}
