# Variables for dev environment
# These values configure the EKS cluster, VPC, and supporting infrastructure

variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region format (e.g., us-west-2, eu-central-1)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "ml-platform-dev"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.34" # Latest stable version as of 2025
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "azs" {
  description = "Availability zones for the VPC"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (for worker nodes)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition = alltrue([
      for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All private_subnet_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (for load balancers)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  validation {
    condition = alltrue([
      for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All public_subnet_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GB RAM - suitable for ML inference
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_size >= 1 && var.node_min_size <= var.node_desired_size
    error_message = "node_min_size must be at least 1 and not greater than node_desired_size."
  }
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4

  validation {
    condition     = var.node_max_size >= var.node_desired_size
    error_message = "node_max_size must be greater than or equal to node_desired_size."
  }
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for container images"
  type        = string
  default     = "ml-platform-api"
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE" # Prevent tag overwriting for security

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be either 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnets (required for EKS nodes)"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway instead of one per AZ (cost optimization for dev)"
  type        = bool
  default     = true # Dev environment - save costs
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ===================================================================
# Security Module Variables
# ===================================================================

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "ml-platform-engineering-practicum"
}

variable "region" {
  description = "AWS region (alias for aws_region for module compatibility)"
  type        = string
  default     = "us-west-2"
}

# Budget Configuration (FREE - first 2 budgets)
variable "budget_amount" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "5.00"
}

variable "budget_alert_email" {
  description = "Email address for budget alerts (REQUIRED - replace with your email)"
  type        = string
  default     = "" # REPLACE WITH YOUR EMAIL: "your-email@example.com"
}

# GuardDuty Configuration (30-day FREE trial, then ~$10-30/month)
variable "enable_guardduty" {
  description = "Enable GuardDuty threat detection (30-day free trial, then ~$10-30/month)"
  type        = bool
  default     = false # Disabled by default to save costs for intermittent usage
  # Set to true during 30-day trial or when doing extended testing
}

# Security Hub Configuration (FREE for limited checks, paid for aggregation)
variable "enable_security_hub" {
  description = "Enable AWS Security Hub for centralized security findings"
  type        = bool
  default     = false # Disabled by default; enable during Phase 2+ when EKS is deployed
}

variable "enable_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark in Security Hub"
  type        = bool
  default     = true # Enabled when Security Hub is active
}

variable "enable_foundational_security" {
  description = "Enable AWS Foundational Security Best Practices standard"
  type        = bool
  default     = true # Enabled when Security Hub is active
}

variable "enable_inspector" {
  description = "Enable AWS Inspector for EC2/EKS vulnerability scanning (requires EC2/EKS)"
  type        = bool
  default     = false # Enable after EKS nodes are deployed
}

variable "security_alert_email" {
  description = "Email address for HIGH/CRITICAL security findings (REQUIRED when Security Hub enabled)"
  type        = string
  default     = "" # REPLACE WITH YOUR EMAIL: "your-email@example.com"
}

# ===================================================================
# Cost Optimization Variables
# ===================================================================

variable "use_spot_instances" {
  description = "Use Spot instances instead of On-Demand for EKS nodes (70% cost savings, but interruptible)"
  type        = bool
  default     = true # Enabled by default for dev environment

  # Note: Spot instances can be interrupted with 2-minute notice
  # Kubernetes will automatically reschedule pods to other nodes
  # For dev/test workloads, this is acceptable and saves significant cost
  # Savings: On-demand t3.medium ($0.0416/hour) → Spot (~$0.0125/hour)
}

variable "spot_max_price" {
  description = "Maximum price for spot instances (USD/hour). Leave empty for on-demand price as max."
  type        = string
  default     = "" # Empty = no limit (use on-demand price as ceiling)

  # Recommendation: Leave empty to accept spot price up to on-demand
  # Setting a limit can cause unavailability if spot price exceeds limit
}
