# Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-cache-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-cache-subnet"
  }
}

# Security Group
resource "aws_security_group" "elasticache" {
  name_prefix = "${var.name_prefix}-cache-"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-cache-sg"
  }
}

resource "aws_security_group_rule" "cache_ingress" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = var.eks_security_group_id
  security_group_id        = aws_security_group.elasticache.id
  description              = "Redis/Valkey from EKS nodes"
}

# ElastiCache Cluster (Valkey-compatible Redis)
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.name_prefix}-valkey"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  # Single node for ~100 users
  az_mode = "single-az"

  tags = {
    Name = "${var.name_prefix}-valkey"
  }
}
