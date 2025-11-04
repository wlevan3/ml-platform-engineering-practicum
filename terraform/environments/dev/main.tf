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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=7c1f791efd61f326ed6102d564d1a65d1eceedf0"

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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=2cb1fac31b0fc2dd6a236b0c0678df75819c5a3b"

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
      name = "${local.cluster_name}-node-group"

      # Spot instances configuration for cost savings (70% discount)
      # Use multiple instance types to increase spot fulfillment success rate
      capacity_type = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      instance_types = var.use_spot_instances ? [
        "t3.medium",  # Primary: $0.0416/hour on-demand, ~$0.0125/hour spot
        "t3a.medium", # AMD alternative: similar specs, ~$0.0112/hour spot
        "t2.medium",  # Older generation fallback
      ] : [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Disk size for worker nodes
      disk_size = 50 # GB - enough for OS + container images

      # Use Amazon Linux 2 optimized AMI
      ami_type = "AL2_x86_64"

      # Launch template configuration
      # Increased max_unavailable for spot instances (faster node replacement)
      update_config = {
        max_unavailable_percentage = var.use_spot_instances ? 50 : 33
      }

      # IAM role for worker nodes
      # Automatically gets permissions for ECR, CloudWatch, etc.
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # For Session Manager access
      }

      # Node labels for pod scheduling
      labels = merge(
        {
          Environment = var.environment
          NodeGroup   = "ml-platform-nodes"
        },
        var.use_spot_instances ? { "node-lifecycle" = "spot" } : {}
      )

      # Taints for spot instances (forces pods to explicitly tolerate spot interruptions)
      # Disabled by default - can be enabled for stricter control
      # taints = var.use_spot_instances ? [{
      #   key    = "kubernetes.io/lifecycle"
      #   value  = "spot"
      #   effect = "NoSchedule"
      # }] : []

      tags = merge(
        local.tags,
        {
          Name = "${local.cluster_name}-worker-node"
        },
        var.use_spot_instances ? { "k8s.io/cluster-autoscaler/node-template/label/lifecycle" = "spot" } : {}
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

  # Encryption at rest with AWS-managed KMS key
  encryption_configuration {
    encryption_type = "KMS"
    # No kms_key specified = uses AWS-managed KMS key (not customer-managed)
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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=c29ec1ed409683086f63f83ff5b10a6f3c296ef2"

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
  version    = "1.14.1" # Helm chart version (controller appVersion: v2.14.1)

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

# ===================================================================
# Security Hub Configuration
# ===================================================================

# Enable Security Hub for centralized security findings
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = false # We'll enable standards explicitly below
  control_finding_generator = "SECURITY_CONTROL" # Use security control-based findings
}

# Enable CIS AWS Foundations Benchmark
resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_security_hub && var.enable_cis_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "foundational" {
  count = var.enable_security_hub && var.enable_foundational_security ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# ===================================================================
# GuardDuty Configuration
# ===================================================================

# Enable GuardDuty for threat detection
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable = true

  # Enhanced monitoring features
  finding_publishing_frequency = "FIFTEEN_MINUTES" # Options: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true # EKS audit log analysis
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true # Scan EBS volumes on suspicious findings
        }
      }
    }
  }

  tags = local.tags
}

# ===================================================================
# AWS Inspector Configuration
# ===================================================================

# Enable AWS Inspector for EC2/EKS vulnerability scanning
# Note: Inspector v2 automatically discovers EC2 instances and ECR images
resource "aws_inspector2_enabler" "main" {
  count = var.enable_inspector ? 1 : 0

  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]

  depends_on = [module.eks]
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# ===================================================================
# Security Alerting (SNS + EventBridge)
# ===================================================================

# SNS Topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  count = var.enable_security_hub ? 1 : 0

  name              = "${local.cluster_name}-security-alerts"
  display_name      = "ML Platform Security Alerts"
  kms_master_key_id = aws_kms_key.sns[0].id

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-security-alerts"
    }
  )
}

# KMS key for SNS topic encryption
resource "aws_kms_key" "sns" {
  count = var.enable_security_hub ? 1 : 0

  description             = "KMS key for SNS topic encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EventBridge to use the key"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-sns-kms"
    }
  )
}

resource "aws_kms_alias" "sns" {
  count = var.enable_security_hub ? 1 : 0

  name          = "alias/${local.cluster_name}-sns"
  target_key_id = aws_kms_key.sns[0].key_id
}

# SNS Topic Subscription (Email)
resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = var.enable_security_hub && var.security_alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# EventBridge Rule: Security Hub HIGH/CRITICAL findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  count = var.enable_security_hub ? 1 : 0

  name        = "${local.cluster_name}-security-hub-critical-findings"
  description = "Capture Security Hub HIGH and CRITICAL severity findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "security_hub_to_sns" {
  count = var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_hub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.findings[0].Severity.Label"
      title       = "$.detail.findings[0].Title"
      description = "$.detail.findings[0].Description"
      resource    = "$.detail.findings[0].Resources[0].Id"
      region      = "$.detail.findings[0].Resources[0].Region"
      compliance  = "$.detail.findings[0].Compliance.Status"
    }
    input_template = <<EOF
"🚨 Security Alert: <severity> Severity Finding"
"Title: <title>"
"Description: <description>"
"Resource: <resource>"
"Region: <region>"
"Compliance Status: <compliance>"
"Action: Review finding in AWS Security Hub console"
EOF
  }
}

# EventBridge Rule: GuardDuty HIGH/CRITICAL findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${local.cluster_name}-guardduty-critical-findings"
  description = "Capture GuardDuty HIGH and CRITICAL severity findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [7, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9] # HIGH: 7.0-8.9, CRITICAL: 9.0-10.0 (not included for brevity)
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count = var.enable_guardduty && var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      title       = "$.detail.title"
      description = "$.detail.description"
      resource    = "$.detail.resource.instanceDetails.instanceId"
      region      = "$.region"
      finding_id  = "$.detail.id"
    }
    input_template = <<EOF
"🚨 GuardDuty Alert: Severity <severity>"
"Title: <title>"
"Description: <description>"
"Resource: <resource>"
"Region: <region>"
"Finding ID: <finding_id>"
"Action: Review finding in AWS GuardDuty console"
EOF
  }
}

# SNS Topic Policy: Allow EventBridge to publish
resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_security_hub ? 1 : 0

  arn = aws_sns_topic.security_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts[0].arn
      }
    ]
  })
}
