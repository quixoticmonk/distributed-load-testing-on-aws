terraform {
  # Actions (aws_lambda_invoke, aws_cloudfront_create_invalidation) need Terraform >= 1.14.
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Configure a remote backend for anything shared, e.g.:
  # backend "s3" {
  #   bucket       = "<state-bucket>"
  #   key          = "dlt/hub/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}
