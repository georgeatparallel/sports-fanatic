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

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
    description     = "Redis/Valkey from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-cache-sg"
  }
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
