output "web_repository_url" {
  description = "ECR repository URL for web image"
  value       = aws_ecr_repository.web.repository_url
}

output "python_bridge_repository_url" {
  description = "ECR repository URL for python-bridge image"
  value       = aws_ecr_repository.python_bridge.repository_url
}

output "web_repository_arn" {
  description = "ECR repository ARN for web image"
  value       = aws_ecr_repository.web.arn
}

output "python_bridge_repository_arn" {
  description = "ECR repository ARN for python-bridge image"
  value       = aws_ecr_repository.python_bridge.arn
}
