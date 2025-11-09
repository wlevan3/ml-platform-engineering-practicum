# S3 VPC Endpoint Policy - Quick Reference

## Configuration

### Enable Least-Privilege Policy (Default)

```hcl
module "networking" {
  source = "../../modules/networking"

  # ... other configuration ...

  # S3 endpoint configuration (least privilege enabled by default)
  s3_endpoint_enable_policy = true
  s3_endpoint_allow_additional_buckets = []
}
```

### Allow Additional Buckets

```hcl
module "networking" {
  source = "../../modules/networking"

  # ... other configuration ...

  # Allow access to additional buckets (e.g., ALB logs)
  s3_endpoint_allow_additional_buckets = [
    "arn:aws:s3:::my-alb-logs-bucket",
    "arn:aws:s3:::my-alb-logs-bucket/*"
  ]
}
```

### Disable Policy (Full Access)

```hcl
module "networking" {
  source = "../../modules/networking"

  # ... other configuration ...

  # Disable for development/testing only
  s3_endpoint_enable_policy = false
}
```

## Common Use Cases

### 1. ECR Image Pulls (Default)

The policy automatically allows access to ECR buckets:

- `prod-{region}-starport-layer-bucket`
- `prod-{region}-starport-layer-bucket/*`

### 2. ALB Access Logs

```hcl
s3_endpoint_allow_additional_buckets = [
  "arn:aws:s3:::my-alb-logs-2023",
  "arn:aws:s3:::my-alb-logs-2023/*"
]
```

### 3. Application Buckets

```hcl
s3_endpoint_allow_additional_buckets = [
  "arn:aws:s3:::my-app-data",
  "arn:aws:s3:::my-app-data/*"
]
```

## Testing Commands

### Validate Configuration (No AWS Credentials)

```bash
./scripts/validate-s3-policy-config.sh
```

### Test with AWS Credentials

```bash
./scripts/test-s3-endpoint-policy.sh
```

### Check Deployment Status

```bash
./scripts/check-s3-endpoint-status.sh
```

## Monitoring

### CloudTrail Query for Denied Access

```bash
aws logs filter-log-events \
  --log-group-name /aws/cloudtrail/CloudTrail \
  --filter-pattern '{ $.eventSource = "s3.amazonaws.com" && $.errorCode = "AccessDenied" }' \
  --start-time $(date -d '1 hour ago' +%s)000
```

### Check VPC Endpoint Status

```bash
aws ec2 describe-vpc-endpoints \
  --filters Name=service-name,Values=com.amazonaws.*.s3 \
  --query 'VpcEndpoints[0].[VpcEndpointId,State]' \
  --output table
```

## Troubleshooting

### ECR Image Pull Fails

1. Check ECR bucket name for your region
2. Verify policy is applied: `./scripts/check-s3-endpoint-status.sh`
3. Temporarily disable policy for testing

### Need Access to New Bucket

1. Add bucket ARN to `s3_endpoint_allow_additional_buckets`
2. Run `terraform apply -target=module.networking`
3. Verify with test script

### Policy Not Working

1. Ensure `s3_endpoint_enable_policy = true`
2. Check VPC endpoint is attached to route tables
3. Verify Terraform applied successfully

## Security Considerations

### DO

- ✅ Use specific bucket ARNs when possible
- ✅ Regularly review additional bucket access
- ✅ Monitor CloudTrail for denied access attempts
- ✅ Keep policy enabled in production

### DON'T

- ❌ Use wildcard patterns unless necessary
- ❌ Add broad permissions not needed for your use case
- ❌ Disable policy in production
- ❌ Ignore security alerts about denied access

## Terraform Outputs

Get useful information after deployment:

```bash
cd infra/aws-core/terraform/environments/dev

# Get ECR bucket name
terraform output -raw ecr_s3_bucket_name

# Get policy JSON
terraform output -raw s3_endpoint_policy
```

## IAM Integration

The VPC endpoint policy works with IAM policies:

1. **VPC Endpoint Policy**: Controls which S3 buckets can be accessed through the endpoint
2. **IAM Policies**: Control which principals (roles/users) can perform actions

Both must allow access for successful S3 operations.

## Example Architecture

```text
┌─────────────────┐
│   EKS Cluster    │
│                 │
│  ┌─────────────┐ │
│  │ Pod         │ │
│  └─────┬───────┘ │
│        │         │
│  ┌─────▼───────┐ │
│  │ IAM Role    │ │
│  └─────┬───────┘ │
│        │         │
│  ┌─────▼───────┐ │
│  │ VPC Endpoint │ │
│  │ (Policy)     │ │
│  └─────┬───────┘ │
│        │         │
│  ┌─────▼───────┐ │
│  │ ECR S3 Bucket│ │
│  └─────────────┘ │
└─────────────────┘
```

## References

- [AWS ECR VPC Endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html)
- [VPC Endpoint Policies](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html#vpc-endpoint-policies)
- [IAM Policy Evaluation Logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
