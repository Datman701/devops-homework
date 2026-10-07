output "bucket_name" {
  type        = string
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  type        = string
  description = "AWS region of the S3 bucket."
  value       = aws_s3_bucket.demo.region
}

output "bucket_domain" {
  type        = string
  description = "Global domain name of the bucket."
  value       = aws_s3_bucket.demo.bucket_domain_name
}

output "versioning_status" {
  type        = string
  description = "Versioning state of the bucket."
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}