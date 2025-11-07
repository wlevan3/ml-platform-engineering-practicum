# Security group rules for EKS cluster and nodes

locals {
  # Cluster security group additional rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  # Node security group base rules (ingress between nodes and cluster)
  node_security_group_base_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster to node all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Node security group egress rules (least privilege - CIS Benchmark 5.4)
  # Scope egress to specific protocols instead of allowing all traffic (-1)
  # NOTE: HTTPS egress to 0.0.0.0/0 is required for ECR, EKS API, and external services
  # To further restrict, deploy VPC endpoints for ECR/EKS and scope HTTPS to VPC CIDR
  node_security_group_egress_rules = var.vpc_cidr == null ? {} : {
    egress_https = {
      description = "HTTPS for ECR, EKS API, VPC endpoints, and external services"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"] # Required for ECR image pulls and EKS API
    }

    egress_dns_tcp = {
      description = "DNS resolution (TCP)"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }

    egress_dns_udp = {
      description = "DNS resolution (UDP)"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }

    egress_ntp = {
      description = "NTP time synchronization"
      protocol    = "udp"
      from_port   = 123
      to_port     = 123
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }

    egress_kubelet = {
      description = "Kubelet API for node communication"
      protocol    = "tcp"
      from_port   = 10250
      to_port     = 10250
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }

    egress_node_ports = {
      description = "NodePort services range"
      protocol    = "tcp"
      from_port   = 30000
      to_port     = 32767
      type        = "egress"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  node_security_group_additional_rules = merge(
    local.node_security_group_base_rules,
    local.node_security_group_egress_rules,
  )
}
