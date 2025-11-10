# Pre-flight Resource Conflict Detection

This document describes the pre-flight resource conflict detection system implemented in this ML platform engineering project.

## Overview

The pre-flight resource conflict detection system helps prevent infrastructure deployment failures by identifying potential conflicts before Terraform apply operations. This system detects common resource conflicts such as:

- S3 bucket name conflicts (globally unique names)
- IAM resource name conflicts
- VPC and subnet CIDR block overlaps
- ECR repository name conflicts
- CloudWatch log group conflicts
- General resource naming conflicts

## Components

### 1. Conflict Detection Script (`scripts/check-resource-conflicts.sh`)

The main script that performs pre-flight validation:

**Features:**

- Parses Terraform plan JSON output
- Checks for resource conflicts with existing AWS resources
- Supports both binary and JSON plan formats
- Comprehensive logging with color-coded output

**Usage:**

```bash
# Check a specific plan file
./scripts/check-resource-conflicts.sh path/to/plan.json

# Check a specific plan file (binary format)
./scripts/check-resource-conflicts.sh path/to/plan.out

# Check current directory's configuration (generates temporary plan)
./scripts/check-resource-conflicts.sh .
```

**Exit Codes:**

- `0` - No conflicts detected, safe to proceed
- `1` - Conflicts detected or validation failed

### 2. GitHub Actions Integration

The workflow `.github/workflows/check-resource-conflicts.yml` runs conflict detection automatically:

- Triggers on pull requests modifying infrastructure
- Validates during CI/CD pipeline
- Fails the build if conflicts are detected

### 3. Integration with Existing Validation

The system integrates with `scripts/validate-terraform-state.sh` to run as part of the standard validation process.

## Conflict Types Detected

### S3 Bucket Conflicts

- Checks if planned S3 bucket names already exist globally in AWS
- Prevents bucket creation failures due to naming conflicts

### IAM Resource Conflicts

- Validates IAM role names against existing roles
- Checks IAM policy names against existing policies

### Network Resource Conflicts

- Verifies VPC names are unique in the account
- Checks for CIDR block overlaps between VPCs
- Ensures subnet CIDR blocks don't conflict within VPCs

### General Resource Conflicts

- ECR repository name conflicts
- CloudWatch log group conflicts
- Other resource naming validations

## Testing

The system includes a test script (`scripts/test-check-resource-conflicts.sh`) for validation:

```bash
./scripts/test-check-resource-conflicts.sh
```

## Integration with Workflows

The conflict detection runs automatically:

1. In the CI/CD pipeline via GitHub Actions
2. As part of the Terraform validation workflow
3. Manually as part of the deployment process

## Best Practices

1. Always run conflict detection before applying Terraform changes
2. Review any detected conflicts before proceeding
3. Use the validation in your development workflow
4. Include in pull request checks to catch conflicts early

## Troubleshooting

- If the script fails due to missing AWS permissions, ensure your AWS credentials have the necessary permissions to query the resources being validated
- For false-positive conflicts, verify that the resource names in your Terraform configuration are unique
- When working in environments with many resources, consider using more specific naming conventions to avoid conflicts
