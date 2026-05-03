variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL (without https://)"
  type        = string
}

variable "news_bucket_arn" {
  description = "S3 news bucket ARN"
  type        = string
}

variable "secrets_arn_prefix" {
  description = "ARN prefix for Secrets Manager secrets"
  type        = string
}
