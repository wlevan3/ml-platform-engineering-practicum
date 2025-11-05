# Outputs for AWS Load Balancer Controller module

output "iam_role_arn" {
  description = "ARN of the IAM role used by the AWS Load Balancer Controller"
  value       = module.irsa_role.iam_role_arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by the AWS Load Balancer Controller"
  value       = module.irsa_role.iam_role_name
}

output "helm_release_name" {
  description = "Name of the Helm release for the AWS Load Balancer Controller"
  value       = helm_release.aws_load_balancer_controller.name
}

output "helm_release_namespace" {
  description = "Namespace where the AWS Load Balancer Controller is deployed"
  value       = helm_release.aws_load_balancer_controller.namespace
}

output "helm_release_version" {
  description = "Version of the Helm chart deployed"
  value       = helm_release.aws_load_balancer_controller.version
}

output "service_account_name" {
  description = "Name of the Kubernetes service account used by the AWS Load Balancer Controller"
  value       = var.service_account_name
}
