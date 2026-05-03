locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# --- VPC ---
module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
}

# --- ECR ---
module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  environment = var.environment
}

# --- EKS ---
module "eks" {
  source = "./modules/eks"

  name_prefix        = local.name_prefix
  environment        = var.environment
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_instance_type = var.eks_node_instance_type
  node_desired_count = var.eks_node_desired_count
  node_min_count     = var.eks_node_min_count
  node_max_count     = var.eks_node_max_count
}

# --- RDS (PostgreSQL 16) ---
module "rds" {
  source = "./modules/rds"

  name_prefix           = local.name_prefix
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  db_name               = var.rds_db_name
  username              = var.rds_username
  eks_security_group_id = module.eks.node_security_group_id
}

# --- ElastiCache (Valkey) ---
module "elasticache" {
  source = "./modules/elasticache"

  name_prefix           = local.name_prefix
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  node_type             = var.elasticache_node_type
  eks_security_group_id = module.eks.node_security_group_id
}

# --- S3 (News Storage) ---
module "s3" {
  source = "./modules/s3"

  name_prefix      = local.name_prefix
  environment      = var.environment
  news_bucket_name = var.news_s3_bucket_name
}

# --- DNS (Route 53) ---
module "dns" {
  source = "./modules/dns"

  domain_name = var.domain_name
  environment = var.environment
}

# --- Secrets Manager ---
module "secrets" {
  source = "./modules/secrets"

  name_prefix  = local.name_prefix
  environment  = var.environment
  rds_endpoint = module.rds.endpoint
  rds_db_name  = var.rds_db_name
  rds_username = var.rds_username
  rds_password = module.rds.password
}

# --- IAM (IRSA roles for EKS pods) ---
module "iam" {
  source = "./modules/iam"

  name_prefix           = local.name_prefix
  environment           = var.environment
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_provider_url = module.eks.oidc_provider_url
  news_bucket_arn       = module.s3.news_bucket_arn
  secrets_arn_prefix    = module.secrets.secrets_arn_prefix
}
