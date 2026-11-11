terraform {
  # 1.14 is the first release with Terraform actions (action / action_trigger),
  # used in place of CloudFormation custom resources for create/update hooks.
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
}
