# Terraform version and provider requirements for alb-controller module
#
# NOTE: This module is currently disabled in infra/aws-core/terraform/environments/dev/main.tf
# due to a Helm provider circular dependency with the EKS cluster module.
# The module will be re-enabled pending GitOps migration (Issue #100) to use
# ArgoCD for declarative Helm deployments instead.
#
# See: infra/aws-core/terraform/environments/dev/providers.tf for detailed migration notes.

terraform {
  required_version = ">= 1.13.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.19.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}
