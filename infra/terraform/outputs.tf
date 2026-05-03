# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# EKS
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ECR
output "ecr_web_repository_url" {
  description = "ECR repository URL for web image"
  value       = module.ecr.web_repository_url
}

output "ecr_python_bridge_repository_url" {
  description = "ECR repository URL for python-bridge image"
  value       = module.ecr.python_bridge_repository_url
}

# RDS
output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

# ElastiCache
output "elasticache_endpoint" {
  description = "ElastiCache endpoint"
  value       = module.elasticache.endpoint
}

output "elasticache_port" {
  description = "ElastiCache port"
  value       = module.elasticache.port
}

# DNS
output "nameservers" {
  description = "Route 53 nameservers (update your registrar)"
  value       = module.dns.nameservers
}

# S3
output "news_bucket_name" {
  description = "S3 bucket name for news storage"
  value       = module.s3.news_bucket_name
}

# IAM
output "web_service_account_role_arn" {
  description = "IAM role ARN for web service account (IRSA)"
  value       = module.iam.web_role_arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for External Secrets Operator (IRSA)"
  value       = module.iam.external_secrets_role_arn
}

# Secrets
output "secrets_arn_prefix" {
  description = "ARN prefix for Secrets Manager secrets"
  value       = module.secrets.secrets_arn_prefix
}
