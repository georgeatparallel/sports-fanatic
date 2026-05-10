environment  = "prod"
aws_region   = "us-east-1"
project_name = "sports-fanatic"
domain_name  = "sports-fan-agent.com"

# VPC
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1b", "us-east-1c", "us-east-1d"]

# EKS — production for ~100 users
eks_cluster_version    = "1.29"
eks_node_instance_type = "t3.medium"
eks_node_desired_count = 2
eks_node_min_count     = 2
eks_node_max_count     = 3

# RDS — small but production-ready
rds_instance_class    = "db.t3.small"
rds_allocated_storage = 50
rds_db_name           = "sports_fanatic"
rds_username          = "sports_fanatic"

# ElastiCache
elasticache_node_type = "cache.t3.micro"

# S3
news_s3_bucket_name = "sports-fanatic-news"
