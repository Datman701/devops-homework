# Simple S3 bucket
resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "Session18"
  }
}

# Bucket-level versioning, declared as its own resource in AWS provider v4+
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption, also its own resource in provider v4+
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access — the single most important S3 hardening setting
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}