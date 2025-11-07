# IAM role for EKS managed node groups
# Created separately to avoid for_each with dynamic data sources

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
resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# SSM access for debugging (optional, controlled by variable)
resource "aws_iam_role_policy_attachment" "node_group_AmazonSSMManagedInstanceCore" {
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
