# AWS Load Balancer Controller Module

Terraform module for deploying the AWS Load Balancer Controller on EKS clusters via Helm.
The controller provisions Application Load Balancers (ALBs) and Network Load Balancers (NLBs)
for Kubernetes Ingress and Service resources.

## Features

- Automatic provisioning of AWS ALBs/NLBs for Kubernetes Ingress
- IAM Roles for Service Accounts (IRSA) integration
- Configurable Helm chart version
- Support for custom Helm values
- Production-ready defaults

## Prerequisites

- EKS cluster with OIDC provider enabled
- Helm provider configured in Terraform
- Kubernetes provider configured to connect to EKS cluster

## Usage

### Basic Example

```hcl
module "alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = "my-eks-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  role_name         = "my-eks-cluster-aws-load-balancer-controller"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### With Custom Helm Values

```hcl
module "alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = "prod-eks-cluster"
  oidc_provider_arn = module.eks.oidc_provider_arn
  chart_version     = "1.14.1"

  additional_helm_values = {
    "replicaCount"                = "2"
    "resources.limits.cpu"        = "200m"
    "resources.limits.memory"     = "500Mi"
    "enableShield"                = "false"
    "enableWaf"                   = "false"
    "enableWafv2"                 = "true"
  }

  tags = {
    Environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| oidc_provider_arn | ARN of the EKS cluster OIDC provider | `string` | n/a | yes |
| role_name | Name of the IAM role for the controller | `string` | `null` | no |
| namespace | Kubernetes namespace for deployment | `string` | `"kube-system"` | no |
| service_account_name | Name of the Kubernetes service account | `string` | `"aws-load-balancer-controller"` | no |
| chart_version | Version of the Helm chart | `string` | `"1.14.1"` | no |
| additional_helm_values | Additional Helm values to set | `map(string)` | `{}` | no |
| tags | Tags to apply to AWS resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| iam_role_arn | ARN of the IAM role used by the controller |
| iam_role_name | Name of the IAM role used by the controller |
| helm_release_name | Name of the Helm release |
| helm_release_namespace | Namespace where the controller is deployed |
| helm_release_version | Version of the Helm chart deployed |
| service_account_name | Name of the Kubernetes service account |

## AWS Costs

The AWS Load Balancer Controller itself is free (runs in your cluster), but ALBs
it provisions incur costs:

- ALB: ~$22/month (fixed cost) + $0.008/LCU-hour (variable)
- NLB: ~$22/month (fixed cost) + $0.006/NLCU-hour (variable)

Each Kubernetes Ingress resource typically creates one ALB. For cost optimization
in dev environments, consider using a single Ingress with multiple paths instead of
multiple Ingresses.

## How It Works

1. Creates an IAM role with ALB/NLB management permissions
2. Uses IRSA to associate the role with a Kubernetes service account
3. Deploys the controller via Helm chart
4. Controller watches for Ingress/Service resources and provisions AWS load balancers
5. Load balancers are automatically configured based on Kubernetes annotations

## References

- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Helm Chart](https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | = 6.19.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.1.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_irsa_role"></a> [irsa\_role](#module\_irsa\_role) | git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts | v6.2.3 |

## Resources

| Name | Type |
|------|------|
| [helm_release.aws_load_balancer_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_helm_values"></a> [additional\_helm\_values](#input\_additional\_helm\_values) | Additional Helm values to set for the AWS Load Balancer Controller | `map(string)` | `{}` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the AWS Load Balancer Controller Helm chart | `string` | `"1.14.1"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace where the AWS Load Balancer Controller will be deployed | `string` | `"kube-system"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the EKS cluster OIDC provider | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IAM role for the AWS Load Balancer Controller | `string` | `null` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Name of the Kubernetes service account for the AWS Load Balancer Controller | `string` | `"aws-load-balancer-controller"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to AWS resources created by this module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_helm_release_name"></a> [helm\_release\_name](#output\_helm\_release\_name) | Name of the Helm release for the AWS Load Balancer Controller |
| <a name="output_helm_release_namespace"></a> [helm\_release\_namespace](#output\_helm\_release\_namespace) | Namespace where the AWS Load Balancer Controller is deployed |
| <a name="output_helm_release_version"></a> [helm\_release\_version](#output\_helm\_release\_version) | Version of the Helm chart deployed |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the IAM role used by the AWS Load Balancer Controller |
| <a name="output_iam_role_name"></a> [iam\_role\_name](#output\_iam\_role\_name) | Name of the IAM role used by the AWS Load Balancer Controller |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Name of the Kubernetes service account used by the AWS Load Balancer Controller |
<!-- END_TF_DOCS -->
