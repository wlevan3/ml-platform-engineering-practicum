# Outputs for dev environment
# These values are used by CI/CD and for manual verification

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS worker nodes"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancers"
  value       = module.vpc.public_subnets
}

# EKS Cluster Outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for service account IAM roles"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = module.eks.node_security_group_id
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR repository URL for ml-platform-api images"
  value       = aws_ecr_repository.ml_platform_api.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.ml_platform_api.arn
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.ml_platform_api.name
}

# Load Balancer Controller Outputs
output "load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.load_balancer_controller_irsa_role.iam_role_arn
}

# Kubeconfig Command
output "kubeconfig_command" {
  description = "Command to update local kubeconfig for cluster access"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# ECR Login Command
output "ecr_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.ml_platform_api.repository_url}"
  sensitive   = true
}

# ===================================================================
# Security Module Outputs
# ===================================================================

output "security_hub_enabled" {
  description = "Whether Security Hub is enabled"
  value       = module.security.security_hub_enabled
}

output "security_hub_standards" {
  description = "Security Hub standards enabled"
  value       = module.security.security_hub_standards
}

output "security_hub_console_url" {
  description = "URL to Security Hub console"
  value       = module.security.security_hub_console_url
}

output "guardduty_enabled" {
  description = "Whether GuardDuty is enabled"
  value       = module.security.guardduty_enabled
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID (if enabled)"
  value       = module.security.guardduty_detector_id
}

output "guardduty_console_url" {
  description = "URL to GuardDuty console"
  value       = module.security.guardduty_console_url
}

output "inspector_enabled" {
  description = "Whether Inspector is enabled"
  value       = module.security.inspector_enabled
}

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = module.security.security_alerts_topic_arn
}

output "security_alerts_topic_name" {
  description = "SNS topic name for security alerts"
  value       = module.security.security_alerts_topic_name
}
