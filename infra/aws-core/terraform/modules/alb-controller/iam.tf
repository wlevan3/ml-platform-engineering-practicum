# IAM Role for AWS Load Balancer Controller (IRSA - IAM Roles for Service Accounts)
# Allows the controller to manage Application Load Balancers for Kubernetes Ingress resources

module "irsa_role" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts?ref=v6.2.3"

  name = var.role_name

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account_name}"]
    }
  }

  tags = var.tags
}
