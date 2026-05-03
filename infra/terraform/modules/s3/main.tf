# S3 Bucket for news article storage
resource "aws_s3_bucket" "news" {
  bucket = var.news_bucket_name

  tags = {
    Name = "${var.name_prefix}-news"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "news" {
  bucket = aws_s3_bucket.news.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning
resource "aws_s3_bucket_versioning" "news" {
  bucket = aws_s3_bucket.news.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "news" {
  bucket = aws_s3_bucket.news.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rule — transition old news to IA after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "news" {
  bucket = aws_s3_bucket.news.id

  rule {
    id     = "transition-old-news"
    status = "Enabled"

    filter {
      prefix = "news/raw/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}
