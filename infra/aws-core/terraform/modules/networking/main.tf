# ===================================================================
# Networking Module - VPC and Subnets
# ===================================================================
#
# This module creates a VPC with public and private subnets across
# multiple availability zones. Designed for EKS cluster networking.
#
# Features:
# - Multi-AZ deployment with public and private subnets
# - NAT gateway for private subnet egress
# - DNS hostnames and resolution enabled
# - Kubernetes-specific subnet tags for EKS integration
# ===================================================================

# VPC Module - Uses official terraform-aws-modules/vpc
module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v6.5.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # NAT Gateway for private subnet egress (required for EKS nodes)
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # DNS settings required for EKS
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  # VPC Flow Logs - enabled for network visibility
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_in_days
  vpc_flow_log_tags                               = var.tags

  # Kubernetes-specific subnet tags
  # Required for EKS to identify subnets for load balancers
  public_subnet_tags = merge(
    var.additional_public_subnet_tags,
    var.cluster_name != null ? {
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {}
  )

  private_subnet_tags = merge(
    var.additional_private_subnet_tags,
    var.cluster_name != null ? {
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {}
  )

  tags = var.tags
}
