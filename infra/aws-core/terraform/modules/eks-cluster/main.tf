# EKS Cluster Module
# Creates an Amazon EKS cluster with managed node groups

locals {
  # Terraform requires lookup() defaults to match the declared map value type (object with optional fields), so
  # maintain a typed stub config we can merge with the IRSA-generated role details when callers omit the addon.
  default_aws_ebs_csi_addon = {
    most_recent = true
    version     = null
  }
}

module "eks" {
  #tfsec:ignore:aws-eks-encrypt-secrets EKS uses AWS-owned KMS keys; org policy forbids CMKs.
  # Using v21.8.0 (commit 32599e5) - latest stable v21 with AWS provider v6.x support
  # v21.x required for AWS provider >= 6.15 (v20.x only supports provider v5.x)
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=32599e5dfc369596dfdb28cea120d469c92145c1"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version
  putin_khuylo       = var.putin_khuylo
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

  # Use default EKS encryption (v1.28+ encrypts secrets by default)
  # Setting to null disables custom KMS encryption config
  create_kms_key           = false
  encryption_config        = null
  attach_encryption_policy = false

  # Cluster addons (automatically managed)
  # Merge user-provided addons with an IRSA-aware aws-ebs-csi-driver definition.
  # - IRSA enabled: start with whatever callers supplied (or a typed default via lookup) and weave in the generated
  #   service_account_role_arn so their preferred version/metadata stays intact while the CSI driver gets its IAM role.
  # - IRSA disabled: return var.cluster_addons untouched so teams can omit the driver entirely or manage it themselves.
  addons = merge(
    var.cluster_addons,
    var.enable_irsa ? {
      aws-ebs-csi-driver = merge(
        lookup(var.cluster_addons, "aws-ebs-csi-driver", local.default_aws_ebs_csi_addon),
        {
          # aws_iam_role.ebs_csi_driver uses `count = var.enable_irsa ? 1 : 0`, so
          # the zero index is safe whenever IRSA is enabled (even if callers omitted the addon and we supplied the default map).
          service_account_role_arn = aws_iam_role.ebs_csi_driver[0].arn
        }
      )
    } : {}
  )

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
