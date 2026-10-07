variable "aws_region" {
  type        = string
  description = "AWS region where the S3 bucket will be created."
  default     = "ap-south-1"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket."
  default     = "devops-s18-demo-bucket"
}

variable "environment" {
  type        = string
  description = "Environment tag applied to the bucket."
  default     = "dev"
}

variable "force_destroy" {
  type        = bool
  description = "Allow terraform destroy to delete a bucket that still contains objects."
  default     = true
}