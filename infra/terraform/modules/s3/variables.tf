variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "news_bucket_name" {
  description = "S3 bucket name for news article storage"
  type        = string
}
