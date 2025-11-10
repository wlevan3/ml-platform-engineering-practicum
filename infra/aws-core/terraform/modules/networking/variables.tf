# ===================================================================
# Networking Module - Variables
# ===================================================================

# ===================================================================
# Required Variables
# ===================================================================

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)

  # Note: Terraform variable validations can only reference the variable being validated (self).
  # Cross-variable validation (e.g., subnet count == AZ count) is not supported in variable blocks.
  # The terraform-aws-vpc module will validate subnet/AZ alignment at apply time.
  validation {
    condition     = length(var.private_subnet_cidrs) > 0
    error_message = "At least one private subnet CIDR must be specified."
  }
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)

  # Note: Terraform variable validations can only reference the variable being validated (self).
  # Cross-variable validation (e.g., subnet count == AZ count) is not supported in variable blocks.
  # The terraform-aws-vpc module will validate subnet/AZ alignment at apply time.
  validation {
    condition     = length(var.public_subnet_cidrs) > 0
    error_message = "At least one public subnet CIDR must be specified."
  }
}

# ===================================================================
# Optional Variables
# ===================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster (for Kubernetes subnet tagging). Set to null if not using EKS."
  type        = string
  default     = null
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for private subnet egress"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all private subnets (cost optimization)"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "additional_public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
  default     = {}
}

variable "additional_private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "flow_log_retention_in_days" {
  description = "CloudWatch Logs retention period for VPC flow logs (90 days meets PCI-DSS requirements)"
  type        = number
  default     = 90
}

# ===================================================================
# S3 VPC Endpoint Configuration
# ===================================================================

variable "s3_endpoint_enable_policy" {
  description = "Enable least-privilege policy for S3 VPC endpoint. When false, allows full access to all S3 buckets."
  type        = bool
  default     = true
}

variable "s3_endpoint_allow_additional_buckets" {
  description = "List of additional S3 bucket ARNs to allow access through the S3 VPC endpoint. Used for services like ALB logging, etc."
  type        = list(string)
  default     = []
}
