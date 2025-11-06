# EKS Cluster Module
# Creates an Amazon EKS cluster with managed node groups

module "eks" {
  #tfsec:ignore:aws-eks-encrypt-secrets EKS uses AWS-owned KMS keys; org policy forbids CMKs.
  # Using v21.8.0 (commit 32599e5) - latest stable v21 with AWS provider v6.x support
  # v21.x required for AWS provider >= 6.15 (v20.x only supports provider v5.x)
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=32599e5dfc369596dfdb28cea120d469c92145c1"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version
  enabled_log_types  = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Networking
  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  # Cluster endpoint access
  # Public access is controlled by variable and may be required for CI/CD access
  # (e.g., GitHub Actions). Production environments should set
  # cluster_endpoint_public_access=false and use VPN/bastion access.
  #trivy:ignore:avd-aws-0040 Public access intentionally configurable for CI/CD
  #trivy:ignore:avd-aws-0041 Public CIDR intentionally configurable for CI/CD
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = var.cluster_endpoint_private_access

  # OIDC provider for service account IAM roles
  enable_irsa = var.enable_irsa

  # Enforce use of AWS-managed KMS only (no customer-managed CMKs)
  create_kms_key           = false
  encryption_config        = {}
  attach_encryption_policy = false

  # Cluster addons (automatically managed)
  addons = var.cluster_addons

  # Managed node groups (defined in node-groups.tf)
  eks_managed_node_groups = local.eks_managed_node_groups

  # Cluster security group rules (defined in security-groups.tf)
  security_group_additional_rules = local.cluster_security_group_additional_rules

  # Node security group rules (defined in security-groups.tf)
  # Note: Upstream module creates egress_all rule for nodes (AVD-AWS-0104)
  # This is intentional - EKS nodes require internet access for:
  # - Pulling container images from ECR/registries
  # - AWS API calls (EC2, S3, etc.)
  # - Package downloads and updates
  #trivy:ignore:avd-aws-0104 EKS nodes require unrestricted egress for container images and AWS APIs
  node_security_group_additional_rules         = local.node_security_group_additional_rules
  node_security_group_enable_recommended_rules = false

  tags = var.tags
}
