# Container Registry Module

Terraform module for creating Amazon ECR (Elastic Container Registry) repositories with security best practices and lifecycle policies.

## Features

- Image vulnerability scanning on push
- Encryption at rest with KMS (AWS-managed or customer-managed)
- Immutable image tags (configurable)
- Automated lifecycle policies for image cleanup
- Configurable retention for tagged and untagged images

## Usage

### Basic Example

```hcl
module "container_registry" {
  source = "../../modules/container-registry"

  repository_name      = "ml-platform-api"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true

  # Lifecycle policy
  max_tagged_images              = 10
  untagged_image_retention_days  = 7
  tag_prefix_list                = ["v"]

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### With Custom KMS Key

```hcl
module "container_registry" {
  source = "../../modules/container-registry"

  repository_name = "prod-api"
  encryption_type = "KMS"
  kms_key_arn     = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"

  tags = {
    Environment = "prod"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | = 6.19.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| repository_name | Name of the ECR repository | `string` | - | yes |
| image_tag_mutability | MUTABLE or IMMUTABLE | `string` | `"IMMUTABLE"` | no |
| scan_on_push | Enable vulnerability scanning | `bool` | `true` | no |
| encryption_type | AES256 or KMS | `string` | `"KMS"` | no |
| kms_key_arn | KMS key ARN (null = AWS-managed) | `string` | `null` | no |
| max_tagged_images | Max tagged images to retain | `number` | `10` | no |
| untagged_image_retention_days | Days to retain untagged images | `number` | `7` | no |
| tag_prefix_list | Tag prefixes for lifecycle policy | `list(string)` | `["v"]` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| repository_url | URL of the ECR repository |
| repository_arn | ARN of the ECR repository |
| repository_name | Name of the ECR repository |
| registry_id | Registry ID |

## Lifecycle Policy

The module automatically creates a lifecycle policy with two rules:

1. **Tagged Images**: Keeps the last N tagged images matching the prefix list (default: last 10 images with "v" prefix)
2. **Untagged Images**: Removes untagged images after N days (default: 7 days)

### Cost Optimization

Lifecycle policies help reduce storage costs by automatically cleaning up:

- Old image versions that are no longer needed
- Intermediate build images without tags
- Failed/test builds

## Security Features

- **Image Scanning**: ECR scans images for CVEs on push (powered by AWS Inspector)
- **Encryption**: All images encrypted at rest with KMS
- **Immutable Tags**: Prevents tag overwriting (recommended for production)

## License

This module is part of the ml-platform-engineering-practicum project (learning project).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | = 6.19.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.19.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/6.19.0/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/6.19.0/docs/resources/ecr_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_encryption_type"></a> [encryption\_type](#input\_encryption\_type) | Encryption type (AES256 or KMS) | `string` | `"KMS"` | no |
| <a name="input_image_tag_mutability"></a> [image\_tag\_mutability](#input\_image\_tag\_mutability) | Tag mutability setting for the repository (MUTABLE or IMMUTABLE) | `string` | `"IMMUTABLE"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key for encryption (null = AWS-managed key) | `string` | `null` | no |
| <a name="input_max_tagged_images"></a> [max\_tagged\_images](#input\_max\_tagged\_images) | Maximum number of tagged images to retain | `number` | `10` | no |
| <a name="input_repository_name"></a> [repository\_name](#input\_repository\_name) | Name of the ECR repository | `string` | n/a | yes |
| <a name="input_scan_on_push"></a> [scan\_on\_push](#input\_scan\_on\_push) | Enable vulnerability scanning on image push | `bool` | `true` | no |
| <a name="input_tag_prefix_list"></a> [tag\_prefix\_list](#input\_tag\_prefix\_list) | List of tag prefixes to apply lifecycle policy to | `list(string)` | <pre>[<br/>  "v"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_untagged_image_retention_days"></a> [untagged\_image\_retention\_days](#input\_untagged\_image\_retention\_days) | Number of days to retain untagged images | `number` | `7` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_registry_id"></a> [registry\_id](#output\_registry\_id) | Registry ID where the repository was created |
| <a name="output_repository_arn"></a> [repository\_arn](#output\_repository\_arn) | ARN of the ECR repository |
| <a name="output_repository_name"></a> [repository\_name](#output\_repository\_name) | Name of the ECR repository |
| <a name="output_repository_url"></a> [repository\_url](#output\_repository\_url) | URL of the ECR repository |
<!-- END_TF_DOCS -->
