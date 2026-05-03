output "news_bucket_name" {
  description = "News S3 bucket name"
  value       = aws_s3_bucket.news.bucket
}

output "news_bucket_arn" {
  description = "News S3 bucket ARN"
  value       = aws_s3_bucket.news.arn
}
