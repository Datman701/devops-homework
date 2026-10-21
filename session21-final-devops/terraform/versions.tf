terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # All state for this project lives in the single default local backend file.
  # Nothing remote is configured, so no credentials or workspace identifiers are
  # ever written into the repository. Swap this for an S3 backend only when the
  # stack is promoted beyond the demo account.
  backend "local" {}
}

provider "aws" {
  region = var.region

  # These three flags let the offline commands (init, validate, plan, graph)
  # run without an AWS account. They only suppress credential/account lookups;
  # `apply` still needs real credentials from the standard chain.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  # Tags applied to every resource that supports them, so anything created
  # here is identifiable in the console and easy to clean up.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "taskboard"
    }
  }
}

# Credentials are never declared in HCL. Terraform reads them from the standard
# AWS credential chain (AWS_PROFILE, environment variables, ~/.aws/credentials),
# so nothing secret is ever committed.