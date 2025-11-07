# EKS Cluster Module

Terraform module for deploying an Amazon Elastic Kubernetes Service (EKS) cluster with managed node
groups. Supports spot instances for cost optimization, customizable networking, and AWS service quotas
management.

## Features

- Managed EKS cluster with configurable Kubernetes version
- Managed node groups with auto-scaling
- Spot instance support for 70% cost savings
- Security group rules for cluster and node communication
- OIDC provider for IAM Roles for Service Accounts (IRSA)
- Configurable cluster addons (vpc-cni, kube-proxy, coredns, EBS CSI driver)
- Public and private API endpoint access control
- AWS service quotas management for EKS resources
- Customizable node labels and taints for pod scheduling

## Prerequisites

- VPC with public and private subnets
- Terraform >= 1.6.0
- AWS provider = 6.19.0

**Note**: Kubernetes provider is intentionally NOT required. Kubernetes resources (ResourceQuotas, LimitRanges) are
managed via YAML manifests in `clusters/dev/bootstrap/k8s-manifests/manifests/` as part of the GitOps migration strategy.

## Usage

### Basic Example (On-Demand Instances)

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "my-eks-cluster"
  cluster_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  control_plane_subnet_ids = module.vpc.public_subnet_ids

  # Disable spot instances for production stability
  use_spot_instances = false
  node_instance_type = "t3.medium"

  node_desired_size = 3
  node_min_size     = 2
  node_max_size     = 5

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### Cost-Optimized Example (Spot Instances)

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "dev-eks-cluster"
  cluster_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Enable spot instances for 70% cost savings
  use_spot_instances  = true
  spot_instance_types = ["t3.medium", "t3a.medium", "t2.medium"]

  node_desired_size = 2
  node_min_size     = 1
  node_max_size     = 4
  node_disk_size    = 50

  # Custom node labels for pod scheduling
  node_labels = {
    Environment = "dev"
    NodeGroup   = "ml-workloads"
  }

  # IAM policies for node access
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "dev"
    CostCenter  = "engineering"
  }
}
```

### Production Example (Restricted Public Access)

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "prod-eks-cluster"
  cluster_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Restrict public API access to specific IPs (e.g., VPN, office)
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24", "198.51.100.0/24"]
  cluster_endpoint_private_access      = true

  # Production-grade node configuration
  use_spot_instances = false
  node_instance_type = "m5.large"
  node_desired_size  = 5
  node_min_size      = 3
  node_max_size      = 10
  node_disk_size     = 100

  # Custom cluster addons
  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      version = "v1.25.0-eksbuild.1"
    }
  }

  tags = {
    Environment = "production"
    Compliance  = "pci-dss"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| cluster_version | Kubernetes version for the cluster | `string` | `"1.28"` | no |
| vpc_id | VPC ID where the cluster will be deployed | `string` | n/a | yes |
| subnet_ids | List of subnet IDs for worker nodes | `list(string)` | n/a | yes |
| control_plane_subnet_ids | List of subnet IDs for control plane | `list(string)` | `[]` | no |
| cluster_endpoint_public_access | Enable public API endpoint | `bool` | `true` | no |
| cluster_endpoint_public_access_cidrs | CIDRs allowed to access public endpoint | `list(string)` | `["0.0.0.0/0"]` | no |
| cluster_endpoint_private_access | Enable private API endpoint | `bool` | `true` | no |
| enable_irsa | Enable IAM Roles for Service Accounts | `bool` | `true` | no |
| cluster_addons | Map of cluster addons to install | `map(object)` | See variables.tf | no |
| use_spot_instances | Use spot instances for cost savings | `bool` | `true` | no |
| spot_instance_types | Instance types for spot instances | `list(string)` | `["t3.medium", "t3a.medium", "t2.medium"]` | no |
| node_instance_type | Instance type for on-demand nodes | `string` | `"t3.medium"` | no |
| node_desired_size | Desired number of worker nodes | `number` | `2` | no |
| node_min_size | Minimum number of worker nodes | `number` | `1` | no |
| node_max_size | Maximum number of worker nodes | `number` | `4` | no |
| node_disk_size | Disk size in GB for worker nodes | `number` | `50` | no |
| node_ami_type | AMI type for worker nodes | `string` | `"AL2_x86_64"` | no |
| node_iam_role_additional_policies | Additional IAM policies for nodes | `map(string)` | See variables.tf | no |
| node_labels | Kubernetes labels for nodes | `map(string)` | `{}` | no |
| node_taints | Kubernetes taints for nodes | `list(object)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | ID/name of the EKS cluster |
| cluster_arn | ARN of the EKS cluster |
| cluster_endpoint | Kubernetes API server endpoint |
| cluster_version | Kubernetes version of the cluster |
| cluster_platform_version | Platform version of the cluster |
| cluster_security_group_id | Security group ID for the cluster |
| cluster_certificate_authority_data | Base64 encoded certificate data (sensitive) |
| oidc_provider_arn | ARN of the OIDC provider for IRSA |
| node_security_group_id | Security group ID for worker nodes |
| eks_managed_node_groups | Map of node group attributes |

## AWS Costs

### EKS Control Plane

- $0.10/hour (~$73/month) per cluster
- Includes 99.95% uptime SLA
- Multi-AZ redundant control plane

### Worker Nodes (On-Demand)

- t3.medium: $0.0416/hour (~$30/month per node)
- m5.large: $0.096/hour (~$70/month per node)
- Plus EBS storage: $0.10/GB-month (e.g., 50GB = $5/month per node)

### Worker Nodes (Spot Instances)

- t3.medium spot: ~$0.0125/hour (~$9/month per node) - **70% savings**
- m5.large spot: ~$0.029/hour (~$21/month per node) - **70% savings**
- Spot instances can be interrupted with 2-minute notice

### Example Monthly Costs

**Dev Environment (2x t3.medium spot, 50GB disks):**

- Control plane: $73
- Worker nodes: 2 × $9 = $18
- Storage: 2 × $5 = $10
- **Total: ~$101/month**

**Production Environment (3x m5.large on-demand, 100GB disks):**

- Control plane: $73
- Worker nodes: 3 × $70 = $210
- Storage: 3 × $10 = $30
- **Total: ~$313/month**

### Cost Optimization Tips

1. Use spot instances for non-critical workloads (70% savings)
2. Use multiple instance types for spot to increase fulfillment rate
3. Rightsize nodes based on actual workload requirements
4. Use cluster autoscaler to scale down during idle periods
5. Consider Fargate for sporadic workloads (pay per pod, not per node)

## How It Works

1. **Cluster Creation**: Provisions EKS control plane with specified Kubernetes version
2. **Networking**: Configures VPC integration, subnet placement, and security groups
3. **OIDC Provider**: Creates OIDC provider for IRSA (IAM roles for pods)
4. **Node Groups**: Deploys managed node groups with auto-scaling configuration
5. **Spot Instances**: If enabled, uses multiple instance types for better availability
6. **Addons**: Installs cluster addons (VPC CNI, CoreDNS, kube-proxy, EBS CSI driver)
7. **Security Groups**: Configures rules for cluster-to-node and node-to-node communication
8. **Service Quotas**: Requests increased quotas for EKS resources if needed

## Spot Instances

Spot instances offer up to 90% cost savings over on-demand pricing but can be interrupted by AWS
with a 2-minute warning. This module uses a best practice approach for spot instances:

- **Multiple Instance Types**: Specifies 3+ instance types to increase fulfillment success rate
- **Update Strategy**: Allows 50% max unavailable during updates (vs 33% for on-demand)
- **Node Labels**: Automatically adds `node-lifecycle=spot` label for pod scheduling
- **No Taints**: By default, spot nodes accept all workloads. Enable taints to restrict.

**When to use spot:**

- Dev/test environments
- Batch processing workloads
- Stateless applications
- Workloads with retry logic

**When NOT to use spot:**

- Production databases
- Real-time processing
- Workloads requiring guaranteed uptime
- Single-instance deployments

## References

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Addons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.19.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.20.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks"></a> [eks](#module\_eks) | git::https://github.com/terraform-aws-modules/terraform-aws-eks.git | 32599e5dfc369596dfdb28cea120d469c92145c1 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.node_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_AmazonSSMManagedInstanceCore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_group_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_addons"></a> [cluster\_addons](#input\_cluster\_addons) | Map of EKS cluster addons to install (e.g., vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver) | <pre>map(object({<br/>    most_recent = optional(bool, true)<br/>    version     = optional(string, null)<br/>  }))</pre> | <pre>{<br/>  "aws-ebs-csi-driver": {<br/>    "most_recent": true<br/>  },<br/>  "coredns": {<br/>    "most_recent": true<br/>  },<br/>  "kube-proxy": {<br/>    "most_recent": true<br/>  },<br/>  "vpc-cni": {<br/>    "most_recent": true<br/>  }<br/>}</pre> | no |
| <a name="input_cluster_endpoint_private_access"></a> [cluster\_endpoint\_private\_access](#input\_cluster\_endpoint\_private\_access) | Enable private API server endpoint (access from within VPC) | `bool` | `true` | no |
| <a name="input_cluster_endpoint_public_access"></a> [cluster\_endpoint\_public\_access](#input\_cluster\_endpoint\_public\_access) | Enable public API server endpoint. Required for CI/CD access (e.g., GitHub Actions). Production environments should set to false and use VPN/bastion. | `bool` | `true` | no |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | List of CIDR blocks that can access the public API server endpoint. Defaults to open (0.0.0.0/0). Production should restrict to specific IPs. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster | `string` | n/a | yes |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes version for the EKS cluster | `string` | `"1.34"` | no |
| <a name="input_control_plane_subnet_ids"></a> [control\_plane\_subnet\_ids](#input\_control\_plane\_subnet\_ids) | List of subnet IDs for EKS control plane (typically public subnets). If not specified, uses subnet\_ids. | `list(string)` | `[]` | no |
| <a name="input_enable_irsa"></a> [enable\_irsa](#input\_enable\_irsa) | Enable IAM Roles for Service Accounts (IRSA) for fine-grained IAM permissions | `bool` | `true` | no |
| <a name="input_enable_ssm_access"></a> [enable\_ssm\_access](#input\_enable\_ssm\_access) | Enable AWS Systems Manager access for node debugging | `bool` | `true` | no |
| <a name="input_node_ami_type"></a> [node\_ami\_type](#input\_node\_ami\_type) | AMI type for worker nodes (AL2023\_x86\_64\_STANDARD, AL2023\_ARM\_64\_STANDARD, AL2023\_*\_NVIDIA, BOTTLEROCKET\_*) | `string` | `"AL2023_ARM_64_STANDARD"` | no |
| <a name="input_node_desired_size"></a> [node\_desired\_size](#input\_node\_desired\_size) | Desired number of worker nodes | `number` | `2` | no |
| <a name="input_node_disk_size"></a> [node\_disk\_size](#input\_node\_disk\_size) | Disk size in GB for worker nodes | `number` | `50` | no |
| <a name="input_node_iam_role_additional_policies"></a> [node\_iam\_role\_additional\_policies](#input\_node\_iam\_role\_additional\_policies) | List of additional IAM policy ARNs to attach to worker node IAM role (e.g., custom CloudWatch policies) | `list(string)` | `[]` | no |
| <a name="input_node_instance_type"></a> [node\_instance\_type](#input\_node\_instance\_type) | Instance type for on-demand worker nodes (used when use\_spot\_instances=false) | `string` | `"t3.medium"` | no |
| <a name="input_node_labels"></a> [node\_labels](#input\_node\_labels) | Kubernetes labels to apply to worker nodes (for pod scheduling) | `map(string)` | `{}` | no |
| <a name="input_node_max_size"></a> [node\_max\_size](#input\_node\_max\_size) | Maximum number of worker nodes | `number` | `4` | no |
| <a name="input_node_min_size"></a> [node\_min\_size](#input\_node\_min\_size) | Minimum number of worker nodes | `number` | `1` | no |
| <a name="input_node_taints"></a> [node\_taints](#input\_node\_taints) | Kubernetes taints to apply to worker nodes (for pod scheduling restrictions) | <pre>list(object({<br/>    key    = string<br/>    value  = optional(string)<br/>    effect = string<br/>  }))</pre> | `[]` | no |
| <a name="input_spot_instance_types"></a> [spot\_instance\_types](#input\_spot\_instance\_types) | List of instance types for spot instances (multiple types increase fulfillment success rate) | `list(string)` | <pre>[<br/>  "t3.medium",<br/>  "t3a.medium",<br/>  "t2.medium"<br/>]</pre> | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for EKS worker nodes (typically private subnets) | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_use_spot_instances"></a> [use\_spot\_instances](#input\_use\_spot\_instances) | Use EC2 Spot instances for worker nodes (70% cost savings, but can be interrupted) | `bool` | `true` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC (used to scope node egress rules) | `string` | `null` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the EKS cluster will be deployed | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | The Amazon Resource Name (ARN) of the cluster |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64 encoded certificate data required to communicate with the cluster |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Endpoint for your Kubernetes API server |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The ID/name of the EKS cluster |
| <a name="output_cluster_platform_version"></a> [cluster\_platform\_version](#output\_cluster\_platform\_version) | The platform version for the cluster |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | Security group ID attached to the EKS cluster |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | The Kubernetes version for the cluster |
| <a name="output_eks_managed_node_groups"></a> [eks\_managed\_node\_groups](#output\_eks\_managed\_node\_groups) | Map of attribute maps for all EKS managed node groups created |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | Security group ID attached to the EKS nodes |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the OIDC Provider for EKS |
<!-- END_TF_DOCS -->
