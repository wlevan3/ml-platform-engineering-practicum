# EKS Cluster Module
# Creates an Amazon EKS cluster with managed node groups

module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=v20.24.3"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Networking
  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  # Cluster endpoint access
  # Public access is controlled by variable and may be required for CI/CD access
  # (e.g., GitHub Actions). Production environments should set
  # cluster_endpoint_public_access=false and use VPN/bastion access.
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access

  # OIDC provider for service account IAM roles
  enable_irsa = var.enable_irsa

  # Enforce use of AWS-managed KMS only (no customer-managed CMKs)
  create_kms_key             = false
  cluster_encryption_config  = {}

  # Cluster addons (automatically managed)
  cluster_addons = var.cluster_addons

  # Managed node groups (defined in node-groups.tf)
  eks_managed_node_groups = local.eks_managed_node_groups

  # Cluster security group rules (defined in security-groups.tf)
  cluster_security_group_additional_rules = local.cluster_security_group_additional_rules

  # Node security group rules (defined in security-groups.tf)
  node_security_group_additional_rules = local.node_security_group_additional_rules

  tags = var.tags
}
