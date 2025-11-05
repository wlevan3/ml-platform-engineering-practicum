# Variables for AWS Load Balancer Controller module

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role for the AWS Load Balancer Controller"
  type        = string
  default     = null

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.role_name))
    error_message = "Role name must contain only alphanumeric characters and the following special characters: + = , . @ _ -"
  }
}

variable "namespace" {
  description = "Kubernetes namespace where the AWS Load Balancer Controller will be deployed"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for the AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "chart_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart"
  type        = string
  default     = "1.14.1"
}

variable "additional_helm_values" {
  description = "Additional Helm values to set for the AWS Load Balancer Controller"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to AWS resources created by this module"
  type        = map(string)
  default     = {}
}
