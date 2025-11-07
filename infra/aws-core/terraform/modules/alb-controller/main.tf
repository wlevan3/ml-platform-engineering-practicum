# AWS Load Balancer Controller module
# Deploys the AWS Load Balancer Controller via Helm to manage ALBs for Kubernetes Ingress resources

locals {
  base_helm_settings = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.irsa_role.arn
    }
  ]

  additional_helm_settings = [
    for key, value in var.additional_helm_values : {
      name  = key
      value = value
    }
  ]

  combined_helm_settings = concat(local.base_helm_settings, local.additional_helm_settings)
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = var.namespace
  version    = var.chart_version

  set = local.combined_helm_settings

  depends_on = [
    module.irsa_role
  ]
}
