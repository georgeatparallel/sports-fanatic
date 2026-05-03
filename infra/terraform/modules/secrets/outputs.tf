output "secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secret_name" {
  description = "Secrets Manager secret name"
  value       = aws_secretsmanager_secret.app_secrets.name
}

output "secrets_arn_prefix" {
  description = "ARN prefix for all secrets (for IAM policies)"
  value       = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
