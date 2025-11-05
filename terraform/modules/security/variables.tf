# ===================================================================
# Security Module Variables
# ===================================================================

# Required Variables
variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource naming)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and contain only alphanumeric characters and hyphens (max 100 chars)."
  }

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and contain only alphanumeric characters and hyphens (max 100 chars)."
  }
}

variable "region" {
  description = "AWS region where security resources will be deployed"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region format (e.g., us-west-2)."
  }
}

# Security Hub Configuration
variable "enable_security_hub" {
  description = "Enable AWS Security Hub for centralized security findings aggregation"
  type        = bool
  default     = false
}

variable "enable_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark in Security Hub (only applies if enable_security_hub=true)"
  type        = bool
  default     = true
}

variable "enable_foundational_security" {
  description = "Enable AWS Foundational Security Best Practices standard in Security Hub (only applies if enable_security_hub=true)"
  type        = bool
  default     = true
}

# GuardDuty Configuration
variable "enable_guardduty" {
  description = "Enable AWS GuardDuty for intelligent threat detection (30-day free trial, then ~$10-30/month)"
  type        = bool
  default     = false
}

# AWS Inspector Configuration
variable "enable_inspector" {
  description = "Enable AWS Inspector for EC2/ECR vulnerability scanning (requires running EC2 instances or ECR images)"
  type        = bool
  default     = false
}

# Alerting Configuration
variable "security_alert_email" {
  description = "Email address for HIGH/CRITICAL security finding notifications (subscription confirmation required)"
  type        = string
  default     = ""

  validation {
    condition = (
      var.security_alert_email == "" ||
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    )
    error_message = "security_alert_email must be empty or a valid email address."
  }
}

# Tagging
variable "tags" {
  description = "Additional tags to apply to all security module resources"
  type        = map(string)
  default     = {}
}
