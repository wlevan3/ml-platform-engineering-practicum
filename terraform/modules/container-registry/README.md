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
| aws | >= 5.0 |

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
