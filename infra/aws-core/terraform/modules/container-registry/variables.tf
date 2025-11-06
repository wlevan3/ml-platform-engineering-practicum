# ===================================================================
# Container Registry Module - Variables
# ===================================================================

# ===================================================================
# Required Variables
# ===================================================================

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_/]*$", var.repository_name))
    error_message = "Repository name must start with a lowercase letter or number and can only contain lowercase letters, numbers, hyphens, underscores, and forward slashes."
  }
}

# ===================================================================
# Optional Variables
# ===================================================================

variable "image_tag_mutability" {
  description = "Tag mutability setting for the repository (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Encryption type (AES256 or KMS)"
  type        = string
  default     = "KMS"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "Encryption type must be either AES256 or KMS."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption (null = AWS-managed key)"
  type        = string
  default     = null
}

# Lifecycle Policy Variables

variable "max_tagged_images" {
  description = "Maximum number of tagged images to retain"
  type        = number
  default     = 10

  validation {
    condition     = var.max_tagged_images > 0
    error_message = "Maximum tagged images must be greater than 0."
  }
}

variable "untagged_image_retention_days" {
  description = "Number of days to retain untagged images"
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_retention_days > 0
    error_message = "Untagged image retention days must be greater than 0."
  }
}

variable "tag_prefix_list" {
  description = "List of tag prefixes to apply lifecycle policy to"
  type        = list(string)
  default     = ["v"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
