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
- AWS provider >= 5.0
- Kubernetes provider >= 2.20

## Usage

### Basic Example (On-Demand Instances)

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "my-eks-cluster"
  cluster_version = "1.28"

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
  cluster_version = "1.28"

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
  cluster_version = "1.29"

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
