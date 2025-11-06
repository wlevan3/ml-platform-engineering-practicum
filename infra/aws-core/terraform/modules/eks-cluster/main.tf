# EKS Cluster Module
# Creates an Amazon EKS cluster with managed node groups

module "eks" {
  #tfsec:ignore:aws-eks-encrypt-secrets EKS uses AWS-owned KMS keys; org policy forbids CMKs.
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=v21.8.0"

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
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = var.cluster_endpoint_private_access

  # OIDC provider for service account IAM roles
  enable_irsa = var.enable_irsa

  # Enforce use of AWS-managed KMS only (no customer-managed CMKs)
  create_kms_key           = false
  encryption_config        = null
  attach_encryption_policy = false

  # Cluster addons (automatically managed)
  addons = var.cluster_addons

  # Managed node groups (defined in node-groups.tf)
  eks_managed_node_groups = local.eks_managed_node_groups

  # Cluster security group rules (defined in security-groups.tf)
  security_group_additional_rules = local.cluster_security_group_additional_rules

  # Node security group rules (defined in security-groups.tf)
  node_security_group_additional_rules         = local.node_security_group_additional_rules
  node_security_group_enable_recommended_rules = false

  tags = var.tags
}
