# Node groups configuration for EKS cluster

locals {
  eks_managed_node_groups = {
    main = {
      name = "${var.cluster_name}-ng" # Shortened to fit AWS IAM role name_prefix limit (38 chars)

      # Spot instances configuration for cost savings (70% discount)
      capacity_type = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      # Use multiple instance types for spot to increase fulfillment success rate
      instance_types = var.use_spot_instances ? var.spot_instance_types : [var.node_instance_type]

      # Scaling configuration
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Disk configuration
      disk_size = var.node_disk_size

      # Enforce IMDSv2 for node metadata access
      metadata_options = {
        http_endpoint = "enabled"
        http_tokens   = "required"
      }

      # AMI type
      ami_type = var.node_ami_type

      # Launch template configuration
      update_config = {
        max_unavailable_percentage = var.use_spot_instances ? 50 : 33
      }

      # IAM role additional policies
      iam_role_additional_policies = var.node_iam_role_additional_policies

      # Node labels for pod scheduling
      labels = merge(
        var.node_labels,
        var.use_spot_instances ? { "node-lifecycle" = "spot" } : {}
      )

      # Taints (optional, for stricter control)
      taints = {
        for taint in var.node_taints :
        "${taint.key}-${taint.effect}" => {
          key    = taint.key
          value  = try(taint.value, null)
          effect = taint.effect
        }
      }

      tags = merge(
        var.tags,
        {
          Name = "${var.cluster_name}-worker-node"
        },
        var.use_spot_instances ? { "k8s.io/cluster-autoscaler/node-template/label/lifecycle" = "spot" } : {}
      )
    }
  }
}
