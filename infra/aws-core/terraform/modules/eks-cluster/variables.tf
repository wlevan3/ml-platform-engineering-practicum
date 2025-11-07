# ===================================================================
# EKS Cluster Module - Variables
# ===================================================================

# ===================================================================
# Required Variables
# ===================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,99}$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only alphanumeric characters and hyphens, and be 1-100 characters long."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.(29|30|3[1-4])$", var.cluster_version))
    error_message = "Cluster version must be one of the currently supported AWS EKS versions: 1.29, 1.30, 1.31, 1.32, 1.33, or 1.34."
  }
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]{8,}$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier (format: vpc-xxxxxxxx)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (used to scope node egress rules)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for EKS worker nodes (typically private subnets)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for high availability."
  }
}

# ===================================================================
# Optional Variables - Cluster Configuration
# ===================================================================

variable "control_plane_subnet_ids" {
  description = "List of subnet IDs for EKS control plane (typically public subnets). If not specified, uses subnet_ids."
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint. Required for CI/CD access (e.g., GitHub Actions). Production environments should set to false and use VPN/bastion."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint. Defaults to open (0.0.0.0/0). Production should restrict to specific IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint (access from within VPC)"
  type        = bool
  default     = true
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA) for fine-grained IAM permissions"
  type        = bool
  default     = true
}

variable "cluster_addons" {
  description = "Map of EKS cluster addons to install (e.g., vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver)"
  type = map(object({
    most_recent = optional(bool, true)
    version     = optional(string, null)
  }))
  default = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }
}

# ===================================================================
# Optional Variables - Node Group Configuration
# ===================================================================

variable "use_spot_instances" {
  description = "Use EC2 Spot instances for worker nodes (70% cost savings, but can be interrupted)"
  type        = bool
  default     = true
}

variable "spot_instance_types" {
  description = "List of instance types for spot instances (multiple types increase fulfillment success rate)"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium", "t2.medium"]
}

variable "node_instance_type" {
  description = "Instance type for on-demand worker nodes (used when use_spot_instances=false)"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "Desired size must be at least 1."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_size >= 1
    error_message = "Minimum size must be at least 1."
  }
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4

  validation {
    condition     = var.node_max_size >= 1
    error_message = "Maximum size must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 50

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 1000
    error_message = "Disk size must be between 20 and 1000 GB."
  }
}

variable "node_ami_type" {
  description = "AMI type for worker nodes (AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, AL2023_*_NVIDIA, BOTTLEROCKET_*)"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"

  validation {
    condition     = can(regex("^(AL2023_x86_64_STANDARD|AL2023_ARM_64_STANDARD|AL2023_x86_64_NVIDIA|AL2023_ARM_64_NVIDIA|AL2023_x86_64_NEURON|BOTTLEROCKET_ARM_64|BOTTLEROCKET_x86_64|BOTTLEROCKET_ARM_64_NVIDIA|BOTTLEROCKET_x86_64_NVIDIA)$", var.node_ami_type))
    error_message = "AMI type must be a valid EKS AMI type (AL2023 or Bottlerocket only - AL2 deprecated for EKS 1.33+)."
  }
}

variable "node_iam_role_additional_policies" {
  description = "Map of additional IAM policies to attach to worker node IAM role (e.g., for SSM, CloudWatch)"
  type        = map(string)
  default = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

variable "node_labels" {
  description = "Kubernetes labels to apply to worker nodes (for pod scheduling)"
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints to apply to worker nodes (for pod scheduling restrictions)"
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []
}

# ===================================================================
# Optional Variables - Tags
# ===================================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
