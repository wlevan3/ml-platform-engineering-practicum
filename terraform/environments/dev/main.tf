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

# VPC Module - Network foundation for EKS cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # NAT Gateway for private subnet egress (required for EKS nodes)
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway # Cost optimization for dev

  # DNS settings required for EKS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Kubernetes-specific subnet tags
  # Required for EKS to identify subnets for load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.tags
}

# EKS Cluster Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # Networking
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  # Cluster endpoint access
  cluster_endpoint_public_access  = true # Allow access from internet (for GitHub Actions)
  cluster_endpoint_private_access = true # Allow access from within VPC

  # OIDC provider for service account IAM roles
  enable_irsa = true

  # Cluster addons (automatically managed)
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    # EBS CSI driver for persistent volumes (if needed in future)
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Managed node groups
  eks_managed_node_groups = {
    ml_platform_nodes = {
      name           = "${local.cluster_name}-node-group"
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Disk size for worker nodes
      disk_size = 50 # GB - enough for OS + container images

      # Use Amazon Linux 2 optimized AMI
      ami_type = "AL2_x86_64"

      # Launch template configuration
      update_config = {
        max_unavailable_percentage = 50 # Allow 50% of nodes to be unavailable during update
      }

      # IAM role for worker nodes
      # Automatically gets permissions for ECR, CloudWatch, etc.
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # For Session Manager access
      }

      labels = {
        Environment = var.environment
        NodeGroup   = "ml-platform-nodes"
      }

      tags = merge(
        local.tags,
        {
          Name = "${local.cluster_name}-worker-node"
        }
      )
    }
  }

  # Cluster security group rules
  cluster_security_group_additional_rules = {
    # Allow worker nodes to communicate with control plane
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    # Allow nodes to communicate with each other
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    # Allow worker nodes to receive traffic from control plane
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster to node all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = local.tags
}

# ECR Repository for container images
resource "aws_ecr_repository" "ml_platform_api" {
  name                 = var.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability

  # Vulnerability scanning on push
  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.tags,
    {
      Name = var.ecr_repository_name
    }
  )
}

# ECR Lifecycle policy - clean up old images
resource "aws_ecr_lifecycle_policy" "ml_platform_api" {
  repository = aws_ecr_repository.ml_platform_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IAM role for AWS Load Balancer Controller
# Allows the controller to manage ALBs for Kubernetes Ingress
module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-aws-load-balancer-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# AWS Load Balancer Controller (via Helm)
# Manages ALBs for Kubernetes Ingress resources
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2" # Latest stable version as of 2024

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.load_balancer_controller_irsa_role.iam_role_arn
  }

  depends_on = [
    module.eks,
    module.load_balancer_controller_irsa_role
  ]
}
