# Main Terraform configuration for dev environment
# Orchestrates VPC, EKS cluster, ECR, and supporting infrastructure

locals {
  cluster_name = var.cluster_name

  tags = merge(
    var.tags,
    {
      Environment = var.environment
      Cluster     = local.cluster_name
    }
  )
}

# ===================================================================
# Networking Module - VPC foundation for EKS cluster
# ===================================================================

module "networking" {
  source = "../../modules/networking"

  vpc_name             = "${local.cluster_name}-vpc"
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs

  # EKS integration - enables Kubernetes subnet tagging
  cluster_name = local.cluster_name

  # NAT Gateway for private subnet egress (cost optimization for dev)
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  tags = local.tags
}

# ===================================================================
# EKS Cluster Module - Managed Kubernetes cluster with node groups
# ===================================================================

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  #tfsec:ignore:aws-eks-encrypt-secrets EKS uses AWS-owned KMS keys; Sentinel policy prohibits customer-managed CMKs.
  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  putin_khuylo = true

  # Networking from networking module
  vpc_id                   = module.networking.vpc_id
  vpc_cidr                 = var.vpc_cidr
  subnet_ids               = module.networking.private_subnet_ids
  control_plane_subnet_ids = module.networking.public_subnet_ids

  # Cluster endpoint access configuration
  # Pattern: Public endpoint + IAM authentication (production-grade for CI/CD environments)
  #
  # Security model:
  # - Public endpoint: Accessible from internet BUT requires AWS IAM credentials
  # - IAM authentication: aws-auth ConfigMap maps IAM principals to K8s RBAC roles
  # - Defense in depth: IAM (who can auth) + RBAC (what they can do) + CloudTrail (audit)
  # - GitHub Actions: Uses OIDC (no long-lived credentials) with scoped IAM role
  #
  # Why no CIDR restrictions:
  # - IAM is the primary security control (attacker needs valid AWS creds + mapped role)
  # - CIDR adds ops complexity: GitHub Actions IPs change, remote work, shared cloud IPs
  # - Threat model: If AWS creds compromised, IP allowlist won't help
  #
  # Alternative: Private endpoint requires VPN/bastion or self-hosted runners in VPC
  # Trade-off: More secure for insider threats, but adds cost/complexity for CI/CD
  #
  # Refs: https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
  cluster_endpoint_public_access  = true # Required for GitHub Actions + kubectl
  cluster_endpoint_private_access = true # Required for nodes to join cluster

  # Node group configuration
  use_spot_instances = var.use_spot_instances
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size

  tags = local.tags
}

# ===================================================================
# Container Registry Module - ECR repository for container images
# ===================================================================

module "container_registry" {
  source = "../../modules/container-registry"

  repository_name               = var.ecr_repository_name
  image_tag_mutability          = var.ecr_image_tag_mutability
  scan_on_push                  = var.ecr_scan_on_push
  max_tagged_images             = 10
  untagged_image_retention_days = 7

  tags = merge(
    local.tags,
    {
      Name = var.ecr_repository_name
    }
  )
}

# ===================================================================
# AWS Load Balancer Controller Module - DISABLED
# ===================================================================
#
# This module is commented out because it requires the Helm provider,
# which has been disabled to break the Terraform provider dependency cycle.
#
# The ALB controller will be installed via one of these methods:
# 1. ArgoCD application (recommended GitOps approach)
# 2. Manual Helm chart installation after EKS cluster creation
# 3. Separate Terraform root that runs after EKS cluster exists
#
# See related GitHub issues for migration roadmap.
#
# ===================================================================

# module "alb_controller" {
#   source = "../../modules/alb-controller"
#
#   cluster_name      = local.cluster_name
#   oidc_provider_arn = module.eks_cluster.oidc_provider_arn
#
#   tags = local.tags
#
#   depends_on = [module.eks_cluster]
# }

# ===================================================================
# Security Monitoring Module
# ===================================================================

module "security" {
  source = "../../modules/security"

  # Required
  cluster_name = local.cluster_name
  region       = var.aws_region

  # Security Hub configuration
  enable_security_hub          = var.enable_security_hub
  enable_cis_standard          = var.enable_cis_standard
  enable_foundational_security = var.enable_foundational_security

  # GuardDuty configuration
  enable_guardduty = var.enable_guardduty

  # Inspector configuration
  enable_inspector = var.enable_inspector

  # Alerting
  security_alert_email = var.security_alert_email

  # Tagging
  tags = local.tags
}
