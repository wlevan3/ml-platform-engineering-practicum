# AWS OIDC Setup for GitHub Actions

## Overview

This document explains the OpenID Connect (OIDC) authentication setup between
GitHub Actions and AWS. OIDC allows GitHub Actions workflows to securely
authenticate to AWS without storing long-lived AWS credentials (access keys) in
GitHub Secrets.

**Benefits of OIDC over Access Keys:**

- ✅ **No long-lived credentials** - Temporary credentials expire automatically
- ✅ **Automatic credential rotation** - AWS STS generates new credentials per workflow run
- ✅ **Reduced security risk** - No need to manage/rotate static access keys
- ✅ **Fine-grained access control** - Restrict access to specific repositories/branches
- ✅ **AWS IAM best practices** - Follows AWS recommended security practices

---

## Infrastructure Components

### 1. GitHub OIDC Provider (AWS IAM)

**ARN:** `arn:aws:iam::984479408136:oidc-provider/token.actions.githubusercontent.com`

**Purpose:** Allows AWS to trust GitHub as an identity provider for federated authentication.

**Configuration:**

- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Audience:** `sts.amazonaws.com` (AWS Security Token Service)
- **Thumbprint:** Automatically managed by AWS

**How to view:**

```bash
AWS_PROFILE=kodekloud aws iam list-open-id-connect-providers
```

---

### 2. IAM Role for GitHub Actions

**ARN:** `arn:aws:iam::984479408136:role/GitHubActions-AssumeRoleForActions`

**Purpose:** IAM role that GitHub Actions assumes to access AWS resources.

**Trust Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::984479408136:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:wlevan3/*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

**Key Conditions:**

- **Repository restriction:** `repo:wlevan3/*` - Only repositories under `wlevan3` user can assume this role
- **Audience validation:** `sts.amazonaws.com` - Ensures the OIDC token is intended for AWS STS

**Permissions:**

- Currently: **AdministratorAccess** (for testing/learning)
- Production recommendation: Scope down to least-privilege permissions

**How to view:**

```bash
AWS_PROFILE=kodekloud aws iam get-role --role-name GitHubActions-AssumeRoleForActions
```

---

## How OIDC Authentication Works

### Authentication Flow

```text
┌─────────────────┐
│ GitHub Actions  │
│ Workflow Runs   │
└────────┬────────┘
         │ 1. Request OIDC token
         │    (includes repo, branch, workflow info)
         ▼
┌─────────────────────────────────────────┐
│ GitHub OIDC Token Endpoint              │
│ https://token.actions.githubusercontent. │
│        com/.well-known/jwks             │
└────────┬────────────────────────────────┘
         │ 2. Return signed JWT token
         │    (short-lived, cryptographically signed)
         ▼
┌─────────────────┐
│ GitHub Actions  │
│ Workflow        │
└────────┬────────┘
         │ 3. AssumeRoleWithWebIdentity
         │    (pass JWT token + role ARN)
         ▼
┌─────────────────────────────────────────┐
│ AWS STS (Security Token Service)        │
│ - Validates JWT signature               │
│ - Checks trust policy conditions        │
│ - Verifies audience (sts.amazonaws.com) │
│ - Confirms repo matches (wlevan3/*)     │
└────────┬────────────────────────────────┘
         │ 4. Return temporary AWS credentials
         │    (access key, secret key, session token)
         │    Valid for 1 hour
         ▼
┌─────────────────┐
│ GitHub Actions  │
│ Workflow        │
│ - Run AWS CLI   │
│ - Call AWS APIs │
└─────────────────┘
```

### Security Model

**Token Claims Validated:**

- `aud` (audience): Must be `sts.amazonaws.com`
- `sub` (subject): Must match `repo:wlevan3/*` (repository pattern)
- `exp` (expiration): Token must not be expired
- **Signature:** Token must be signed by GitHub's OIDC provider

**Temporary Credentials:**

- **Validity:** 1 hour by default (configurable up to 12 hours)
- **Scope:** Limited to permissions granted by IAM role
- **Automatic cleanup:** Credentials expire and cannot be reused

---

## Usage in GitHub Actions Workflows

### Basic Example

```yaml
name: Deploy to AWS

on:
  push:
    branches:
      - main

permissions:
  id-token: write  # Required for OIDC authentication
  contents: read   # Required to checkout code

jobs:
  deploy:
    name: Deploy to AWS
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials using OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::984479408136:role/GitHubActions-AssumeRoleForActions
          aws-region: us-west-2
          role-session-name: GitHubActions-Deploy-${{ github.run_id }}

      - name: Verify AWS identity
        run: |
          echo "Authenticated as:"
          aws sts get-caller-identity

      - name: Deploy application
        run: |
          # Your deployment commands here
          aws s3 sync ./build s3://my-bucket/
```

### Key Configuration

**Permissions block (required):**

```yaml
permissions:
  id-token: write  # REQUIRED for OIDC - allows workflow to request OIDC token
  contents: read   # Standard permission for checkout
```

**aws-actions/configure-aws-credentials@v4:**

- **role-to-assume:** IAM role ARN to assume
- **aws-region:** AWS region for API calls
- **role-session-name:** Unique identifier for this session (helpful for CloudTrail logs)

---

## Testing OIDC Setup

### Test Workflow

A test workflow is available at `.github/workflows/test-oidc-aws.yml`:

**Manual trigger:**

```bash
gh workflow run test-oidc-aws.yml
```

**What the test does:**

1. ✅ Authenticates to AWS using OIDC
2. ✅ Verifies identity with `aws sts get-caller-identity`
3. ✅ Lists S3 buckets (tests read permissions)
4. ✅ Lists EC2 instances in us-west-2 (tests compute permissions)

**How to monitor:**

```bash
gh run watch
```

---

## Troubleshooting

### Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** Trust policy doesn't allow the repository to assume the role

**Solution:**

1. Verify repository name matches trust policy pattern:

   ```bash
   AWS_PROFILE=kodekloud aws iam get-role --role-name GitHubActions-AssumeRoleForActions \
     --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'
   ```

2. Ensure `sub` claim allows `repo:wlevan3/*` or specific repo

---

### Error: "Missing permissions: id-token: write"

**Cause:** Workflow doesn't have OIDC token generation permission

**Solution:** Add `permissions` block to workflow:

```yaml
permissions:
  id-token: write
  contents: read
```

---

### Error: "Unable to assume role - invalid token"

**Cause:** OIDC token validation failed

**Check:**

1. Verify audience is `sts.amazonaws.com` in trust policy
2. Check OIDC provider exists in AWS account
3. Ensure role ARN is correct

---

### Error: "Access Denied" on AWS API calls

**Cause:** IAM role doesn't have required permissions

**Solution:**

1. Check role permissions:

   ```bash
   AWS_PROFILE=kodekloud aws iam list-attached-role-policies \
     --role-name GitHubActions-AssumeRoleForActions
   ```

2. Add required permissions to role or attached policies

---

## Security Best Practices

### 1. Scope Role Permissions (Least Privilege)

**Current state:** Role has `AdministratorAccess` (for testing)

**Production recommendation:**

- Create separate roles for different environments (dev, staging, prod)
- Grant only required permissions (e.g., S3 read/write, ECS deploy)
- Use IAM policy conditions to restrict actions

**Example least-privilege policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-bucket",
        "arn:aws:s3:::my-app-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "arn:aws:ecs:us-west-2:984479408136:service/my-cluster/my-service"
    }
  ]
}
```

---

### 2. Restrict by Repository/Branch

**Current trust policy:** Allows all repos under `wlevan3/*`

**More restrictive options:**

**Specific repository only:**

```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:sub": "repo:wlevan3/ml-platform-engineering-practicum:ref:refs/heads/main"
  }
}
```

**Multiple repositories:**

```json
"Condition": {
  "StringLike": {
    "token.actions.githubusercontent.com:sub": [
      "repo:wlevan3/ml-platform-engineering-practicum:*",
      "repo:wlevan3/another-repo:*"
    ]
  }
}
```

**Main branch only:**

```json
"Condition": {
  "StringLike": {
    "token.actions.githubusercontent.com:sub": "repo:wlevan3/*:ref:refs/heads/main"
  }
}
```

---

### 3. Monitor and Audit

**CloudTrail Logging:**

- All `AssumeRoleWithWebIdentity` calls are logged
- Track which workflows accessed AWS and when
- Review `role-session-name` to identify specific workflow runs

**CloudWatch Alarms:**

- Alert on unexpected role assumptions
- Monitor for unusual AWS API calls from GitHub Actions

**Regular Reviews:**

- Review IAM role permissions quarterly
- Check CloudTrail logs for suspicious activity
- Update trust policies as repository structure changes

---

## Migration from Access Keys

If you have existing workflows using AWS access keys in GitHub Secrets:

### Before (Access Keys)

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-west-2
```

### After (OIDC)

```yaml
permissions:
  id-token: write
  contents: read

# ...

- name: Configure AWS credentials using OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::984479408136:role/GitHubActions-AssumeRoleForActions
    aws-region: us-west-2
```

**Migration steps:**

1. ✅ Create OIDC provider in AWS (already done)
2. ✅ Create IAM role with trust policy (already done)
3. ✅ Test OIDC authentication (`.github/workflows/test-oidc-aws.yml`)
4. ⏭️ Update workflows to use OIDC instead of access keys
5. ⏭️ Remove AWS access keys from GitHub Secrets
6. ⏭️ Deactivate/delete access keys in AWS IAM

---

## References

### AWS Documentation

- [IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AssumeRoleWithWebIdentity API](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### GitHub Documentation

- [About security hardening with OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Configuring OIDC in AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GitHub Actions OIDC claims](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token)

### Related Files

- `.github/workflows/test-oidc-aws.yml` - Test workflow for OIDC verification
- `CLAUDE.md` - Project documentation with AWS profile configuration

---

## Infrastructure as Code (Future Enhancement)

**Current state:** OIDC provider and IAM role created manually via AWS Console

**Phase 2+ recommendation:** Manage with Terraform

**Example Terraform configuration:**

```hcl
# OIDC Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",  # pragma: allowlist secret
  ]
}

# IAM Role
resource "aws_iam_role" "github_actions" {
  name = "GitHubActions-AssumeRoleForActions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:wlevan3/*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Attach policies (replace with least-privilege policies)
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

---

## Notes

- **Learning project:** This setup is for learning ML platform engineering, not production use
- **AdministratorAccess:** Current role has full AWS access for testing - scope down for production
- **AWS Profile:** Use `AWS_PROFILE=kodekloud` for local AWS CLI commands
- **Test workflow:** Runs on pushes to `infra/issue-15-oidc-aws` branch or manual trigger
- **Account ID:** 984479408136 (KodeKloud AWS sandbox account)

**Created:** 2025-11-03
**Last Updated:** 2025-11-03
**Maintained By:** Will Levan (learning project)
