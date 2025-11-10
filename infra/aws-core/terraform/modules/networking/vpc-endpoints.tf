# VPC Endpoints for Private EKS Cluster
#
# Required for managed node groups to join cluster when
# cluster_endpoint_public_access = false
#
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html

# Data source for current region
data "aws_region" "current" {}

# Security group for VPC interface endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.vpc_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints (ECR, STS, EC2)"
  vpc_id      = module.vpc.vpc_id

  # Allow inbound HTTPS from VPC CIDR
  ingress {
    description = "Allow HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound (required for endpoint functionality)
  #tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "Allow all outbound - required for VPC endpoints to reach AWS services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-vpc-endpoints-sg"
    }
  )
}

# ECR API endpoint (required for pulling images)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # Explicit dependency: ensure the VPC and security group exist before we create the endpoint,
  # and ensure Terraform deletes the endpoint before touching those dependencies (prevents DNS conflicts on recreate).
  depends_on = [aws_security_group.vpc_endpoints, module.vpc]
  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-ecr-api-endpoint"
    }
  )
}

# ECR Docker registry endpoint (required for pulling image layers)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # Explicit dependency: ensure the VPC and security group exist before we create the endpoint,
  # and ensure Terraform deletes the endpoint before touching those dependencies (prevents DNS conflicts on recreate).
  depends_on = [aws_security_group.vpc_endpoints, module.vpc]

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-ecr-dkr-endpoint"
    }
  )
}

# S3 gateway endpoint (required for ECR image layers stored in S3)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  # Ensure VPC exists before creating gateway endpoint
  depends_on = [module.vpc]

  tags = merge(

    var.tags,
    {
      Name = "${var.vpc_name}-s3-endpoint"
    }
  )
}

# STS endpoint (required for IRSA - IAM roles for service accounts)
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # Explicit dependency: ensure the VPC and security group exist before we create the endpoint,
  # and ensure Terraform deletes the endpoint before touching those dependencies (prevents DNS conflicts on recreate).
  depends_on = [aws_security_group.vpc_endpoints, module.vpc]

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-sts-endpoint"
    }
  )
}

# EC2 endpoint (required for node metadata and EC2 API calls)
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # Explicit dependency: ensure the VPC and security group exist before we create the endpoint,
  # and ensure Terraform deletes the endpoint before touching those dependencies (prevents DNS conflicts on recreate).
  depends_on = [aws_security_group.vpc_endpoints, module.vpc]

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-ec2-endpoint"
    }
  )
}

# Autoscaling endpoint (required for Cluster Autoscaler)
resource "aws_vpc_endpoint" "autoscaling" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.autoscaling"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  # Explicit dependency: ensure the VPC and security group exist before we create the endpoint,
  # and ensure Terraform deletes the endpoint before touching those dependencies (prevents DNS conflicts on recreate).
  depends_on = [aws_security_group.vpc_endpoints, module.vpc]

  tags = merge(
    var.tags,
    {
      Name = "${var.vpc_name}-autoscaling-endpoint"
    }
  )
}
