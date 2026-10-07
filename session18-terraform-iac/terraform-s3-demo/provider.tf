terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Credentials are read from the standard AWS provider chain:
#   1. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY environment variables
#   2. ~/.aws/credentials profile
#   3. EC2 instance metadata
#
# The three skip_* flags below let `terraform init`, `validate` and `plan`
# run without live credentials. Remove them once real credentials are set,
# otherwise Terraform will happily plan against an account it cannot reach.
provider "aws" {
  region = var.aws_region

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}