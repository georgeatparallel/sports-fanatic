output "endpoint" {
  description = "ElastiCache endpoint"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "port" {
  description = "ElastiCache port"
  value       = aws_elasticache_cluster.main.cache_nodes[0].port
}

output "security_group_id" {
  description = "ElastiCache security group ID"
  value       = aws_security_group.elasticache.id
}
