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
