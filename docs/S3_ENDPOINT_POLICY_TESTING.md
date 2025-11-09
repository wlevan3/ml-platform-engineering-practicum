# S3 Endpoint Policy Testing Guide

This document provides guidance for testing the S3 VPC endpoint least-privilege policy implementation.

## Overview

The S3 endpoint policy restricts access to only the ECR S3 buckets and any additional buckets specified. Testing ensures that ECR image pulls work correctly while blocking unauthorized access.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Access to the dev environment EKS cluster
- kubectl configured for cluster access

## Testing Steps

### 1. Basic ECR Functionality Test

Deploy the updated networking module with the least-privilege policy enabled:

```bash
cd infra/aws-core/terraform/environments/dev
terraform apply -target=module.networking
```

Test ECR image pulls from a pod:

```bash
kubectl run test-pod --image=public.ecr.aws/amazonlinux/amazonlinux:latest --rm -i --restart=Never -- date
```

### 2. Validate S3 Access

Get the ECR S3 bucket name:

```bash
terraform output -raw ecr_s3_bucket_name
```

SSH to an EKS node and test access:

```bash
aws ssm start-session --target <node-instance-id>

# Test ECR bucket access (should succeed)
aws s3 ls s3://prod-us-west-2-starport-layer-bucket/

# Test unauthorized bucket access (should fail)
aws s3 ls s3://aws-public-blockchain-snapshots/
```

### 3. Additional Bucket Testing

Create a test bucket and configure access:

1. Create a test S3 bucket:

```bash
aws s3 mb s3://ml-platform-test-bucket-$(date +%s)
```

2. Add bucket to the networking configuration:

```hcl
s3_endpoint_allow_additional_buckets = [
  "arn:aws:s3:::ml-platform-test-bucket-*",
  "arn:aws:s3:::ml-platform-test-bucket-*/*"
]
```

3. Apply changes and verify access

### 4. Policy Disable Test

Test disabling the policy:

```hcl
s3_endpoint_enable_policy = false
```

Apply changes and verify full S3 access is restored.

## Validation Scripts

Two scripts are provided for automated testing:

- `scripts/validate-s3-policy-config.sh` - Validates configuration without AWS credentials
- `scripts/test-s3-endpoint-policy.sh` - Tests S3 access with AWS credentials

Run configuration validation:

```bash
./scripts/validate-s3-policy-config.sh
```

Run functional tests (requires AWS credentials):

```bash
./scripts/test-s3-endpoint-policy.sh
```

## Troubleshooting

If ECR image pulls fail:

1. Verify the ECR S3 bucket name for your region
2. Check CloudTrail for S3 access denied events
3. Temporarily disable the policy for testing
4. Add additional buckets if needed

## Monitoring

Monitor CloudTrail for S3 access events:

```bash
aws logs filter-log-events \
  --log-group-name /aws/cloudtrail/CloudTrail \
  --filter-pattern '{ $.eventSource = "s3.amazonaws.com" && $.errorCode = "AccessDenied" }'
```

## Success Criteria

- ECR image pulls work without errors
- Access to unauthorized S3 buckets is blocked
- Configured additional buckets are accessible
- Policy can be disabled to restore full access
- All automated tests pass
