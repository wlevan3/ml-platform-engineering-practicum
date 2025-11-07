# Networking Module

Terraform module for creating a VPC with public and private subnets across multiple
availability zones. Designed specifically for EKS cluster networking with proper subnet tagging.

## Features

- Multi-AZ deployment with public and private subnets
- NAT gateway for private subnet egress (required for EKS worker nodes)
- DNS hostnames and resolution enabled
- Kubernetes-specific subnet tags for EKS integration
- Optional single NAT gateway for cost optimization
- Configurable CIDR blocks and availability zones

## Usage

### Basic Example

```hcl
module "networking" {
  source = "../../modules/networking"

  vpc_name = "my-eks-vpc"
  vpc_cidr = "10.0.0.0/16"

  azs                  = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # For EKS integration - adds kubernetes.io tags to subnets
  cluster_name = "my-eks-cluster"

  # NAT gateway configuration
  enable_nat_gateway = true
  single_nat_gateway = true  # Cost optimization for dev environments

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### Without EKS (General VPC)

If you don't need Kubernetes-specific subnet tagging, set `cluster_name` to `null`:

```hcl
module "networking" {
  source = "../../modules/networking"

  vpc_name = "general-vpc"
  vpc_cidr = "10.0.0.0/16"

  azs                  = ["us-west-2a", "us-west-2b"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]

  cluster_name = null  # No Kubernetes tagging

  tags = {
    Environment = "prod"
  }
}
```

### Production Configuration (Multi-NAT)

For production environments, use one NAT gateway per AZ for high availability:

```hcl
module "networking" {
  source = "../../modules/networking"

  vpc_name = "prod-eks-vpc"
  vpc_cidr = "10.0.0.0/16"

  azs                  = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  cluster_name = "prod-eks-cluster"

  # Production: NAT gateway in each AZ for high availability
  enable_nat_gateway = true
  single_nat_gateway = false

  tags = {
    Environment = "prod"
    CostCenter  = "platform-engineering"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | = 6.19.0 |

## Providers

| Name | Version |
|------|---------|
| aws | = 6.19.0 |

## Inputs

### Required Inputs

| Name | Description | Type | Validation |
|------|-------------|------|------------|
| `vpc_name` | Name of the VPC | `string` | - |
| `vpc_cidr` | CIDR block for the VPC | `string` | Must be valid IPv4 CIDR |
| `azs` | List of availability zones | `list(string)` | Min 2 AZs |
| `private_subnet_cidrs` | CIDR blocks for private subnets | `list(string)` | Must match AZ count |
| `public_subnet_cidrs` | CIDR blocks for public subnets | `list(string)` | Must match AZ count |

### Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `cluster_name` | EKS cluster name for subnet tagging | `string` | `null` |
| `enable_nat_gateway` | Enable NAT gateway for private subnet egress | `bool` | `true` |
| `single_nat_gateway` | Use single NAT gateway (cost optimization) | `bool` | `true` |
| `enable_dns_hostnames` | Enable DNS hostnames in VPC | `bool` | `true` |
| `enable_dns_support` | Enable DNS support in VPC | `bool` | `true` |
| `additional_public_subnet_tags` | Additional tags for public subnets | `map(string)` | `{}` |
| `additional_private_subnet_tags` | Additional tags for private subnets | `map(string)` | `{}` |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC |
| `vpc_cidr` | CIDR block of the VPC |
| `vpc_name` | Name of the VPC |
| `private_subnet_ids` | IDs of the private subnets |
| `public_subnet_ids` | IDs of the public subnets |
| `private_subnet_cidrs` | CIDR blocks of the private subnets |
| `public_subnet_cidrs` | CIDR blocks of the public subnets |
| `nat_gateway_ids` | IDs of the NAT gateways |
| `azs` | Availability zones used |

## EKS Integration

When `cluster_name` is provided, the module automatically adds the following tags to subnets:

### Public Subnets

```text
kubernetes.io/role/elb                = "1"
kubernetes.io/cluster/${cluster_name} = "shared"
```

### Private Subnets

```text
kubernetes.io/role/internal-elb        = "1"
kubernetes.io/cluster/${cluster_name}" = "shared"
```

These tags are required for EKS to automatically discover subnets for load balancer provisioning.

## NAT Gateway Considerations

### Single NAT Gateway (Cost Optimization)

- **Use for**: Development, testing environments
- **Cost**: ~$32/month (1 NAT gateway)
- **Trade-off**: All private subnets route through one NAT gateway
- **Risk**: If NAT gateway AZ fails, private subnets in other AZs lose internet access

### Multi-NAT Gateway (High Availability)

- **Use for**: Production environments
- **Cost**: ~$96/month (3 NAT gateways @ 3 AZs)
- **Benefit**: Each AZ has its own NAT gateway for redundancy
- **Risk**: Higher cost, but better availability

## Network Architecture

```text
VPC (10.0.0.0/16)
├── AZ1 (us-west-2a)
│   ├── Public Subnet (10.0.101.0/24)
│   │   └── NAT Gateway (if enabled)
│   └── Private Subnet (10.0.1.0/24)
│       └── Routes to NAT Gateway
├── AZ2 (us-west-2b)
│   ├── Public Subnet (10.0.102.0/24)
│   │   └── NAT Gateway (if multi-NAT enabled)
│   └── Private Subnet (10.0.2.0/24)
│       └── Routes to NAT Gateway
└── AZ3 (us-west-2c)
    ├── Public Subnet (10.0.103.0/24)
    │   └── NAT Gateway (if multi-NAT enabled)
    └── Private Subnet (10.0.3.0/24)
        └── Routes to NAT Gateway
```

## Resources Created

- 1 VPC
- N Public Subnets (where N = number of AZs)
- N Private Subnets (where N = number of AZs)
- 1 Internet Gateway
- 1-N NAT Gateways (depending on `single_nat_gateway`)
- 1-N Elastic IPs (one per NAT gateway)
- Route tables and associations

## Module Dependencies

This module uses the official
[terraform-aws-modules/vpc/aws](https://github.com/terraform-aws-modules/terraform-aws-vpc)
module internally, pinned to a specific commit SHA for reproducibility.

## License

This module is part of the ml-platform-engineering-practicum project (learning project).

<!-- markdownlint-disable MD024 MD033 -->
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
| <a name="module_vpc"></a> [vpc](#module\_vpc) | git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git | v6.5.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_private_subnet_tags"></a> [additional\_private\_subnet\_tags](#input\_additional\_private\_subnet\_tags) | Additional tags for private subnets | `map(string)` | `{}` | no |
| <a name="input_additional_public_subnet_tags"></a> [additional\_public\_subnet\_tags](#input\_additional\_public\_subnet\_tags) | Additional tags for public subnets | `map(string)` | `{}` | no |
| <a name="input_azs"></a> [azs](#input\_azs) | List of availability zones | `list(string)` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster (for Kubernetes subnet tagging). Set to null if not using EKS. | `string` | `null` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Enable DNS hostnames in the VPC | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Enable DNS support in the VPC | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Enable NAT gateway for private subnet egress | `bool` | `true` | no |
| <a name="input_flow_log_retention_in_days"></a> [flow\_log\_retention\_in\_days](#input\_flow\_log\_retention\_in\_days) | CloudWatch Logs retention period for VPC flow logs | `number` | `30` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | List of CIDR blocks for private subnets | `list(string)` | n/a | yes |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | List of CIDR blocks for public subnets | `list(string)` | n/a | yes |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Use a single NAT gateway for all private subnets (cost optimization) | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC | `string` | n/a | yes |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | Name of the VPC | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_azs"></a> [azs](#output\_azs) | Availability zones used |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | IDs of the NAT gateways |
| <a name="output_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#output\_private\_subnet\_cidrs) | CIDR blocks of the private subnets |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | IDs of the private subnets |
| <a name="output_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#output\_public\_subnet\_cidrs) | CIDR blocks of the public subnets |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | IDs of the public subnets |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | CIDR block of the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC |
| <a name="output_vpc_name"></a> [vpc\_name](#output\_vpc\_name) | Name of the VPC |
<!-- END_TF_DOCS -->
<!-- markdownlint-enable MD024 MD033 -->
