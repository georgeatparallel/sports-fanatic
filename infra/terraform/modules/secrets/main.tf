# Secrets Manager — application secrets
# These secrets are created with placeholder values.
# Populate them manually via AWS Console or CLI before deploying the app.

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${var.name_prefix}/app-secrets"
  description = "Sports Fanatic application secrets"

  tags = {
    Name = "${var.name_prefix}-app-secrets"
  }
}

# Initial secret value with DATABASE_URL constructed from RDS outputs
resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  secret_string = jsonencode({
    DATABASE_URL          = "ecto://${var.rds_username}:${var.rds_password}@${var.rds_endpoint}/${var.rds_db_name}"
    SECRET_KEY_BASE       = "CHANGE_ME_generate_with_mix_phx_gen_secret"
    FANTASY_NERDS_API_KEY = "CHANGE_ME"
    ANTHROPIC_API_KEY     = "CHANGE_ME"
    EXA_API_KEY           = "CHANGE_ME"
    STRIPE_SECRET_KEY     = "CHANGE_ME"
    STRIPE_WEBHOOK_SECRET = "CHANGE_ME"
    STRIPE_PRICE_MONTHLY  = "CHANGE_ME"
    STRIPE_PRICE_YEARLY   = "CHANGE_ME"
    OPENMETEO_API_KEY     = "CHANGE_ME"
  })

  lifecycle {
    # Don't overwrite secrets that have been manually updated
    ignore_changes = [secret_string]
  }
}
