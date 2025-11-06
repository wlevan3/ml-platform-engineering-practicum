# Provider configuration for AWS and Kubernetes
# Uses AWS OIDC authentication from GitHub Actions (see docs/AWS_OIDC_SETUP.md)

terraform {
  required_version = ">= 1.13.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.19.0"
    }

    # Kubernetes and Helm providers removed - see comment below for explanation
    # kubernetes = {
    #   source  = "hashicorp/kubernetes"
    #   version = "~> 2.23"
    # }

    # helm = {
    #   source  = "hashicorp/helm"
    #   version = "~> 2.11"
    # }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ml-platform-engineering-practicum"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "wlevan3"
    }
  }
}

# ============================================================================
# Kubernetes and Helm Providers - DISABLED
# ============================================================================
#
# These providers have been commented out to break the Terraform provider
# dependency cycle. The cycle occurs because:
# 1. Kubernetes provider requires EKS cluster outputs (cluster_endpoint, etc.)
# 2. terraform-aws-eks module internally creates Kubernetes resources
# 3. Those K8s resources require the Kubernetes provider to exist
#
# MIGRATION PLAN:
# - Kubernetes resources (ResourceQuotas, LimitRanges) in kubernetes-config.tf
#   have been preserved as .reference files for conversion to YAML manifests
# - Future K8s resource management will use ArgoCD (GitOps approach)
# - See GitHub issues for conversion roadmap
#
# WHEN TO RE-ENABLE:
# - Only if using separate Terraform roots (e.g., aws-infrastructure/ and
#   kubernetes-config/) where K8s root runs AFTER EKS cluster is created
# - Not recommended: Use ArgoCD/Flux for K8s resources instead
#
# ============================================================================

# Kubernetes provider - DISABLED (see header above)
# provider "kubernetes" {
#   host                   = module.eks_cluster.cluster_endpoint
#   cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
#
#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "aws"
#     args = [
#       "eks",
#       "get-token",
#       "--cluster-name",
#       module.eks_cluster.cluster_name,
#       "--region",
#       var.aws_region,
#     ]
#   }
# }

# Helm provider - DISABLED (see header above)
# provider "helm" {
#   kubernetes {
#     host                   = module.eks_cluster.cluster_endpoint
#     cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
#
#     exec {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "aws"
#       args = [
#         "eks",
#         "get-token",
#         "--cluster-name",
#         module.eks_cluster.cluster_name,
#         "--region",
#         var.aws_region,
#       ]
#     }
#   }
# }
