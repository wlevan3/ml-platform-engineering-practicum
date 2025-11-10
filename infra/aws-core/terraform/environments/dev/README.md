# dev

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.19.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_container_registry"></a> [container\_registry](#module\_container\_registry) | ../../modules/container-registry | n/a |
| <a name="module_eks_cluster"></a> [eks\_cluster](#module\_eks\_cluster) | ../../modules/eks-cluster | n/a |
| <a name="module_networking"></a> [networking](#module\_networking) | ../../modules/networking | n/a |
| <a name="module_security"></a> [security](#module\_security) | ../../modules/security | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for infrastructure deployment | `string` | `"us-west-2"` | no |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability zones for the VPC | `list(string)` | <pre>[<br/>  "us-west-2a",<br/>  "us-west-2b",<br/>  "us-west-2c"<br/>]</pre> | no |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | Allowed CIDRs for public EKS endpoint in dev (do NOT use 0.0.0.0/0 in shared/prod). | `list(string)` | <pre>[<br/>  "127.0.0.1/32"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | `"ml-platform-dev"` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes version for EKS cluster | `string` | `"1.34"` | no |
| <a name="input_ecr_image_tag_mutability"></a> [ecr\_image\_tag\_mutability](#input\_ecr\_image\_tag\_mutability) | Image tag mutability setting (MUTABLE or IMMUTABLE) | `string` | `"IMMUTABLE"` | no |
| <a name="input_ecr_repository_name"></a> [ecr\_repository\_name](#input\_ecr\_repository\_name) | Name of the ECR repository for container images | `string` | `"ml-platform-api"` | no |
| <a name="input_ecr_scan_on_push"></a> [ecr\_scan\_on\_push](#input\_ecr\_scan\_on\_push) | Enable vulnerability scanning on image push | `bool` | `true` | no |
| <a name="input_enable_cis_standard"></a> [enable\_cis\_standard](#input\_enable\_cis\_standard) | Enable CIS AWS Foundations Benchmark in Security Hub | `bool` | `true` | no |
| <a name="input_enable_foundational_security"></a> [enable\_foundational\_security](#input\_enable\_foundational\_security) | Enable AWS Foundational Security Best Practices standard | `bool` | `true` | no |
| <a name="input_enable_guardduty"></a> [enable\_guardduty](#input\_enable\_guardduty) | Enable GuardDuty threat detection (30-day free trial, then ~$10-30/month) | `bool` | `false` | no |
| <a name="input_enable_inspector"></a> [enable\_inspector](#input\_enable\_inspector) | Enable AWS Inspector for EC2/EKS vulnerability scanning (requires EC2/EKS) | `bool` | `false` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Enable NAT gateway for private subnets (required for EKS nodes) | `bool` | `true` | no |
| <a name="input_enable_security_hub"></a> [enable\_security\_hub](#input\_enable\_security\_hub) | Enable AWS Security Hub for centralized security findings | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod) | `string` | `"dev"` | no |
| <a name="input_node_desired_size"></a> [node\_desired\_size](#input\_node\_desired\_size) | Desired number of worker nodes | `number` | `2` | no |
| <a name="input_node_instance_type"></a> [node\_instance\_type](#input\_node\_instance\_type) | EC2 instance type for EKS worker nodes | `string` | `"t3.micro"` | no |
| <a name="input_node_max_size"></a> [node\_max\_size](#input\_node\_max\_size) | Maximum number of worker nodes | `number` | `4` | no |
| <a name="input_node_min_size"></a> [node\_min\_size](#input\_node\_min\_size) | Minimum number of worker nodes | `number` | `1` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDR blocks for private subnets (for worker nodes) | `list(string)` | <pre>[<br/>  "10.0.1.0/24",<br/>  "10.0.2.0/24",<br/>  "10.0.3.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | CIDR blocks for public subnets (for load balancers) | `list(string)` | <pre>[<br/>  "10.0.101.0/24",<br/>  "10.0.102.0/24",<br/>  "10.0.103.0/24"<br/>]</pre> | no |
| <a name="input_security_alert_email"></a> [security\_alert\_email](#input\_security\_alert\_email) | Email address for HIGH/CRITICAL security findings (REQUIRED when Security Hub enabled) | `string` | `""` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Use single NAT gateway instead of one per AZ (cost optimization for dev) | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_use_spot_instances"></a> [use\_spot\_instances](#input\_use\_spot\_instances) | Use Spot instances instead of On-Demand for EKS nodes (70% cost savings, but interruptible) | `bool` | `false` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for VPC | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64 encoded certificate data for cluster authentication |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | EKS cluster API endpoint |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | EKS cluster ID |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | Security group ID attached to the EKS cluster |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | Kubernetes version running on the cluster |
| <a name="output_ecr_login_command"></a> [ecr\_login\_command](#output\_ecr\_login\_command) | Command to authenticate Docker to ECR |
| <a name="output_ecr_repository_arn"></a> [ecr\_repository\_arn](#output\_ecr\_repository\_arn) | ECR repository ARN |
| <a name="output_ecr_repository_name"></a> [ecr\_repository\_name](#output\_ecr\_repository\_name) | ECR repository name |
| <a name="output_ecr_repository_url"></a> [ecr\_repository\_url](#output\_ecr\_repository\_url) | ECR repository URL for ml-platform-api images |
| <a name="output_guardduty_console_url"></a> [guardduty\_console\_url](#output\_guardduty\_console\_url) | URL to GuardDuty console |
| <a name="output_guardduty_detector_id"></a> [guardduty\_detector\_id](#output\_guardduty\_detector\_id) | GuardDuty detector ID (if enabled) |
| <a name="output_guardduty_enabled"></a> [guardduty\_enabled](#output\_guardduty\_enabled) | Whether GuardDuty is enabled |
| <a name="output_inspector_enabled"></a> [inspector\_enabled](#output\_inspector\_enabled) | Whether Inspector is enabled |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | Command to update local kubeconfig for cluster access |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | Security group ID attached to the EKS worker nodes |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the OIDC Provider for EKS (for IRSA) |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs for EKS worker nodes |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs for load balancers |
| <a name="output_security_alerts_topic_arn"></a> [security\_alerts\_topic\_arn](#output\_security\_alerts\_topic\_arn) | SNS topic ARN for security alerts |
| <a name="output_security_alerts_topic_name"></a> [security\_alerts\_topic\_name](#output\_security\_alerts\_topic\_name) | SNS topic name for security alerts |
| <a name="output_security_hub_console_url"></a> [security\_hub\_console\_url](#output\_security\_hub\_console\_url) | URL to Security Hub console |
| <a name="output_security_hub_enabled"></a> [security\_hub\_enabled](#output\_security\_hub\_enabled) | Whether Security Hub is enabled |
| <a name="output_security_hub_standards"></a> [security\_hub\_standards](#output\_security\_hub\_standards) | Security Hub standards enabled |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID |
<!-- END_TF_DOCS -->
