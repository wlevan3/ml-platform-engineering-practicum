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

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "Number of private subnets must match number of availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "Number of public subnets must match number of availability zones."
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
