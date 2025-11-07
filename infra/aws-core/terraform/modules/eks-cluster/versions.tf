# Terraform version and provider requirements for eks-cluster module

terraform {
  required_version = ">= 1.13.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.19.0"
    }
  }
}
