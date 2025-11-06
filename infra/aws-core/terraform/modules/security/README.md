# AWS Security Monitoring Module

Terraform module for comprehensive AWS security monitoring using Security Hub, GuardDuty, Inspector, and automated alerting.

## Features

- **AWS Security Hub** - Centralized security findings aggregator
  - CIS AWS Foundations Benchmark v1.4.0
  - AWS Foundational Security Best Practices v1.0.0
  - Continuous compliance monitoring
- **AWS GuardDuty** - Intelligent threat detection
  - EKS audit log analysis
  - S3 data event monitoring
  - EBS malware scanning
- **AWS Inspector** - Automated vulnerability scanning
  - EC2 instance scanning
  - ECR container image scanning
- **Automated Alerting** - Real-time notifications
  - EventBridge rules for HIGH/CRITICAL findings
  - SNS topic with KMS encryption
  - Email notifications

## Usage

### Basic Usage

```hcl
module "security" {
  source = "../../modules/security"

  cluster_name = "ml-platform-dev"
  region       = "us-west-2"

  enable_security_hub = true
  enable_guardduty    = true

  security_alert_email = "security@example.com"

  tags = {
    Environment = "dev"
    Project     = "ml-platform"
  }
}
```

### Complete Example

```hcl
module "security" {
  source = "../../modules/security"

  # Required
  cluster_name = "ml-platform-dev"
  region       = "us-west-2"

  # Security Hub
  enable_security_hub          = true
  enable_cis_standard          = true
  enable_foundational_security = true

  # GuardDuty (30-day free trial)
  enable_guardduty = true

  # Inspector (enable after EC2/EKS deployed)
  enable_inspector = true

  # Alerting
  security_alert_email = "security-team@example.com"

  # Tagging
  tags = {
    Environment = "dev"
    Project     = "ml-platform"
    ManagedBy   = "Terraform"
  }
}
```

### Accessing Outputs

```hcl
# Security Hub console URL
output "security_hub_url" {
  value = module.security.security_hub_console_url
}

# GuardDuty detector ID
output "guardduty_detector" {
  value = module.security.guardduty_detector_id
}

# SNS topic for alerts
output "alerts_topic" {
  value = module.security.security_alerts_topic_arn
}
```

## Cost Considerations

| Service | Cost | Notes |
|---------|------|-------|
| **Security Hub** | ~$0.0010 per check | First 10,000 checks/month free |
| **GuardDuty** | ~$10-30/month | 30-day free trial, varies by data volume |
| **Inspector** | ~$0.15/instance/month | Pay-per-scan model |
| **SNS** | ~$0.50/month | First 1,000 emails/month free |
| **KMS** | $1/month | Plus $0.03 per 10,000 API calls |

**Total estimated cost**: ~$15-35/month when all services enabled

### Cost Optimization Tips

1. **Start with Security Hub only** - Get compliance checks without GuardDuty costs
2. **Use GuardDuty 30-day free trial** - Test before committing
3. **Enable Inspector selectively** - Only scan production environments
4. **Disable when not needed** - Set `enable_*` variables to `false` for dev environments

## Security Standards Covered

### CIS AWS Foundations Benchmark v1.4.0

- IAM password policies and MFA
- CloudTrail logging and validation
- S3 bucket encryption and access controls
- VPC Flow Logs and security groups
- KMS key rotation

### AWS Foundational Security Best Practices

- EC2 security (IMDSv2, EBS encryption)
- RDS encryption and backups
- Lambda function security
- API Gateway logging
- EKS security configuration

## Alert Notification Flow

```text
┌─────────────────┐
│  Security Hub   │
│   GuardDuty     │──┐
│   Inspector     │  │
└─────────────────┘  │
                     │
                     ▼
              ┌──────────────┐
              │ EventBridge  │
              │    Rules     │
              └──────────────┘
                     │
                     │ Filter: HIGH/CRITICAL
                     │ Status: NEW
                     ▼
              ┌──────────────┐
              │  SNS Topic   │
              │ (Encrypted)  │
              └──────────────┘
                     │
                     ▼
              ┌──────────────┐
              │    Email     │
              │ Notification │
              └──────────────┘
```

## Incident Response

For detailed incident response procedures, see: [SECURITY_INCIDENT_RESPONSE.md](../../../docs/SECURITY_INCIDENT_RESPONSE.md)

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | = 6.19.0 |

## Providers

| Name | Version |
|------|---------|
| aws | = 6.19.0 |

## Resources

| Name | Type |
|------|------|
| aws_securityhub_account.main | resource |
| aws_securityhub_standards_subscription.cis | resource |
| aws_securityhub_standards_subscription.foundational | resource |
| aws_guardduty_detector.main | resource |
| aws_inspector2_enabler.main | resource |
| aws_sns_topic.security_alerts | resource |
| aws_sns_topic_policy.security_alerts | resource |
| aws_sns_topic_subscription.security_alerts_email | resource |
| aws_cloudwatch_event_rule.security_hub_findings | resource |
| aws_cloudwatch_event_target.security_hub_to_sns | resource |
| aws_cloudwatch_event_rule.guardduty_findings | resource |
| aws_cloudwatch_event_target.guardduty_to_sns | resource |
| aws_caller_identity.current | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster (used for resource naming) | `string` | n/a | yes |
| region | AWS region where security resources will be deployed | `string` | n/a | yes |
| enable_security_hub | Enable AWS Security Hub for centralized security findings aggregation | `bool` | `false` | no |
| enable_cis_standard | Enable CIS AWS Foundations Benchmark in Security Hub | `bool` | `true` | no |
| enable_foundational_security | Enable AWS Foundational Security Best Practices standard | `bool` | `true` | no |
| enable_guardduty | Enable AWS GuardDuty for intelligent threat detection | `bool` | `false` | no |
| enable_inspector | Enable AWS Inspector for EC2/ECR vulnerability scanning | `bool` | `false` | no |
| security_alert_email | Email address for HIGH/CRITICAL security finding notifications | `string` | `""` | no |
| tags | Additional tags to apply to all security module resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| security_hub_enabled | Whether AWS Security Hub is enabled |
| security_hub_account_id | Security Hub account ID (if enabled) |
| security_hub_standards | Map of enabled Security Hub standards |
| security_hub_console_url | URL to Security Hub console |
| guardduty_enabled | Whether AWS GuardDuty is enabled |
| guardduty_detector_id | GuardDuty detector ID (if enabled) |
| guardduty_console_url | URL to GuardDuty console |
| inspector_enabled | Whether AWS Inspector is enabled |
| security_alerts_topic_arn | ARN of the SNS topic for security alerts |
| security_alerts_topic_name | Name of the SNS topic for security alerts |
| eventbridge_rules | Map of EventBridge rule names and ARNs |

## Examples

### Enable Security Hub Only (Cheapest Option)

```hcl
module "security" {
  source = "../../modules/security"

  cluster_name         = "ml-platform-dev"
  region               = "us-west-2"
  enable_security_hub  = true
  enable_guardduty     = false
  enable_inspector     = false
  security_alert_email = "security@example.com"
}
```

### Enable GuardDuty During Free Trial

```hcl
module "security" {
  source = "../../modules/security"

  cluster_name         = "ml-platform-dev"
  region               = "us-west-2"
  enable_security_hub  = true
  enable_guardduty     = true  # 30-day free trial
  security_alert_email = "security@example.com"
}
```

### Full Security Stack (Production)

```hcl
module "security" {
  source = "../../modules/security"

  cluster_name                 = "ml-platform-prod"
  region                       = "us-west-2"
  enable_security_hub          = true
  enable_cis_standard          = true
  enable_foundational_security = true
  enable_guardduty             = true
  enable_inspector             = true
  security_alert_email         = "security-prod@example.com"

  tags = {
    Environment = "prod"
    Compliance  = "required"
  }
}
```

## Testing

### Validate Module

```bash
cd infra/aws-core/terraform/modules/security
terraform init
terraform validate
terraform fmt -check
```

### Test with Terratest (Future)

```bash
cd test/security_test.go
go test -v -timeout 30m
```

## Troubleshooting

### Issue: SNS subscription not confirmed

**Solution**: Check your email for AWS SNS subscription confirmation and click the confirmation link.

### Issue: GuardDuty not detecting findings

**Solution**: GuardDuty requires 7-14 days to establish baseline behavior. Test findings can be generated via AWS console.

### Issue: Security Hub compliance checks not updating

**Solution**: Compliance checks run every 12-24 hours. To force a check, disable and re-enable the control.

## References

- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
- [AWS GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/)
- [AWS Inspector User Guide](https://docs.aws.amazon.com/inspector/latest/user/)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [Incident Response Procedures](../../../docs/SECURITY_INCIDENT_RESPONSE.md)

## License

This module is part of the ML Platform Engineering Practicum project.

## Maintainers

- Platform Engineering Team

## Support

For issues or questions:

- Review [SECURITY_INCIDENT_RESPONSE.md](../../../docs/SECURITY_INCIDENT_RESPONSE.md)
- Check [CLAUDE.md](../../../CLAUDE.md) for project conventions
- Open a GitHub issue with the `security` label

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.19.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.19.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.guardduty_findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_rule.security_hub_findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.guardduty_to_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_event_target.security_hub_to_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_guardduty_detector.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector) | resource |
| [aws_guardduty_detector_feature.ebs_malware_protection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_guardduty_detector_feature.kubernetes_audit_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_guardduty_detector_feature.s3_data_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_inspector2_enabler.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_enabler) | resource |
| [aws_securityhub_account.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_account) | resource |
| [aws_securityhub_standards_subscription.cis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_standards_subscription) | resource |
| [aws_securityhub_standards_subscription.foundational](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_standards_subscription) | resource |
| [aws_sns_topic.security_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.security_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.security_alerts_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster (used for resource naming) | `string` | n/a | yes |
| <a name="input_enable_cis_standard"></a> [enable\_cis\_standard](#input\_enable\_cis\_standard) | Enable CIS AWS Foundations Benchmark in Security Hub (only applies if enable\_security\_hub=true) | `bool` | `true` | no |
| <a name="input_enable_foundational_security"></a> [enable\_foundational\_security](#input\_enable\_foundational\_security) | Enable AWS Foundational Security Best Practices standard in Security Hub (only applies if enable\_security\_hub=true) | `bool` | `true` | no |
| <a name="input_enable_guardduty"></a> [enable\_guardduty](#input\_enable\_guardduty) | Enable AWS GuardDuty for intelligent threat detection (30-day free trial, then ~$10-30/month) | `bool` | `false` | no |
| <a name="input_enable_inspector"></a> [enable\_inspector](#input\_enable\_inspector) | Enable AWS Inspector for EC2/ECR vulnerability scanning (requires running EC2 instances or ECR images) | `bool` | `false` | no |
| <a name="input_enable_security_hub"></a> [enable\_security\_hub](#input\_enable\_security\_hub) | Enable AWS Security Hub for centralized security findings aggregation | `bool` | `false` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where security resources will be deployed | `string` | n/a | yes |
| <a name="input_security_alert_email"></a> [security\_alert\_email](#input\_security\_alert\_email) | Email address for HIGH/CRITICAL security finding notifications (subscription confirmation required) | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all security module resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_eventbridge_rules"></a> [eventbridge\_rules](#output\_eventbridge\_rules) | Map of EventBridge rule names and ARNs |
| <a name="output_guardduty_console_url"></a> [guardduty\_console\_url](#output\_guardduty\_console\_url) | URL to GuardDuty console in AWS Management Console |
| <a name="output_guardduty_detector_id"></a> [guardduty\_detector\_id](#output\_guardduty\_detector\_id) | GuardDuty detector ID (if enabled) |
| <a name="output_guardduty_enabled"></a> [guardduty\_enabled](#output\_guardduty\_enabled) | Whether AWS GuardDuty is enabled |
| <a name="output_inspector_enabled"></a> [inspector\_enabled](#output\_inspector\_enabled) | Whether AWS Inspector is enabled |
| <a name="output_security_alerts_topic_arn"></a> [security\_alerts\_topic\_arn](#output\_security\_alerts\_topic\_arn) | ARN of the SNS topic for security alerts |
| <a name="output_security_alerts_topic_name"></a> [security\_alerts\_topic\_name](#output\_security\_alerts\_topic\_name) | Name of the SNS topic for security alerts |
| <a name="output_security_hub_account_id"></a> [security\_hub\_account\_id](#output\_security\_hub\_account\_id) | Security Hub account ID (if enabled) |
| <a name="output_security_hub_console_url"></a> [security\_hub\_console\_url](#output\_security\_hub\_console\_url) | URL to Security Hub console in AWS Management Console |
| <a name="output_security_hub_enabled"></a> [security\_hub\_enabled](#output\_security\_hub\_enabled) | Whether AWS Security Hub is enabled |
| <a name="output_security_hub_standards"></a> [security\_hub\_standards](#output\_security\_hub\_standards) | Map of enabled Security Hub standards |
<!-- END_TF_DOCS -->
