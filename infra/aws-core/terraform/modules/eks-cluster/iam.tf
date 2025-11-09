# IAM role for EKS managed node groups
# Created separately to avoid for_each with dynamic data sources

# Shared locals
locals {
  eks_oidc_provider_components = split("oidc-provider/", module.eks.oidc_provider_arn)
  eks_oidc_provider_path = try(
    local.eks_oidc_provider_components[1],
    tonumber(
      format(
        "Invalid OIDC provider ARN for cluster %s: %s (expected to contain 'oidc-provider/').",
        var.cluster_name,
        module.eks.oidc_provider_arn
      )
    )
  )
}

# IAM role for node groups
resource "aws_iam_role" "node_group" {
  name_prefix = "${var.cluster_name}-ng-"
  description = "IAM role for EKS managed node group ${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-node-group-role"
    }
  )
}

# Required EKS policies - using static ARNs to avoid for_each with dynamic data
resource "aws_iam_role_policy_attachment" "node_group_amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# SSM access for debugging (optional, controlled by variable)
resource "aws_iam_role_policy_attachment" "node_group_amazon_ssm_managed_instance_core" {
  count      = var.enable_ssm_access ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_group.name
}

# Additional custom policies
resource "aws_iam_role_policy_attachment" "node_group_additional" {
  for_each = toset(var.node_iam_role_additional_policies)

  policy_arn = each.value
  role       = aws_iam_role.node_group.name
}

# ===================================================================
# EBS CSI Driver IRSA Role
# ===================================================================

data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  count = var.enable_irsa ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_path}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_path}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  count              = var.enable_irsa ? 1 : 0
  name_prefix        = "${var.cluster_name}-ebs-csi-"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-ebs-csi-driver"
    }
  )
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count      = var.enable_irsa ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver[0].name
}
