# Security Module Deployment Guide

Quick guide to deploy foundational security services (CloudTrail, GuardDuty, Budgets).

## Prerequisites

✅ Terraform backend bootstrapped (`terraform/scripts/bootstrap-backend.sh`)
✅ AWS CLI configured with KodeKloud profile
✅ Your email address ready

## Deployment Steps

### 1. Configure Your Email (REQUIRED)

Edit `variables.tf` and replace the placeholder email:

```hcl
variable "budget_alert_email" {
  default = "your-email@gmail.com"  # ← CHANGE THIS
}
```

### 2. Deploy Security Module

```bash
cd terraform/environments/dev

# Review what will be created
terraform plan

# Expected output:
#  + aws_budgets_budget.monthly_cost
#  + aws_cloudtrail.main
#  + aws_guardduty_detector.main[0]
#  + aws_s3_bucket.cloudtrail_logs
#  + aws_sns_topic.budget_alerts
#  ... and more

# Apply changes
terraform apply

# Type 'yes' when prompted
```

**Deployment time:** 2-3 minutes

### 3. Confirm Email Subscription

Within 5 minutes, check your email for:

```text
Subject: AWS Notification - Subscription Confirmation
From: no-reply@sns.amazonaws.com

You have chosen to subscribe to the topic:
arn:aws:sns:us-west-2:...:ml-platform-budget-alerts

To confirm this subscription, click: [Confirm subscription]
```

**Click "Confirm subscription"** or you won't receive alerts!

### 4. Verify Deployment

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name ml-platform-engineering-practicum-trail

# Expected output:
# "IsLogging": true

# Check GuardDuty status
aws guardduty list-detectors

# Expected output:
# "DetectorIds": ["abc123..."]

# Check S3 bucket for CloudTrail logs (may take 15 minutes for first logs)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 ls s3://ml-platform-engineering-practicum-cloudtrail-logs-${ACCOUNT_ID}/
```

## Cost Impact

**Month 1 (with GuardDuty trial):**

- AWS Budgets: **FREE**
- CloudTrail: **FREE** (management events)
- S3 storage: ~$0.50-2.00/month
- GuardDuty: **FREE** (30-day trial)
- **Total: $1-3/month**

**After 30 days:**

- Option A: Keep GuardDuty → $11-33/month
- Option B: Disable GuardDuty → $1-3/month

## What You Get

### 1. Cost Monitoring

- Email alerts at 50%, 80%, 100% of $5 budget
- Forecasted overage warnings

### 2. Audit Logging

- Every AWS API call recorded
- 1-year retention (auto-deleted after 365 days)
- Stored in S3 with lifecycle policies

### 3. Threat Detection (30-day trial)

- Malware detection
- Compromised instance detection
- Unusual API activity alerts
- Data exfiltration monitoring

## Disabling GuardDuty After Trial

**On day 28 of trial, decide:**

**Keep GuardDuty** (recommended for prod):

```bash
# Do nothing - it will automatically start charging
```

**Disable GuardDuty** (recommended for learning projects):

```bash
terraform apply -var="enable_guardduty=false"

# This will:
# - Stop threat detection
# - Stop GuardDuty charges
# - Preserve historical findings (read-only)
```

## Troubleshooting

### Email not received?

1. Check spam folder
2. Verify email in `variables.tf`
3. Reapply:

   ```bash
   terraform taint aws_sns_topic_subscription.budget_email[0]
   terraform apply
   ```

### CloudTrail not logging?

```bash
# Check trail status
aws cloudtrail get-trail-status --name ml-platform-engineering-practicum-trail

# If not logging:
aws cloudtrail start-logging --name ml-platform-engineering-practicum-trail
```

### S3 bucket not created?

```bash
# List buckets
aws s3 ls | grep cloudtrail

# If missing, check Terraform state
terraform state list | grep cloudtrail

# Recreate if needed
terraform taint aws_s3_bucket.cloudtrail_logs
terraform apply
```

## Next Steps

1. **Test budget alerts** - Create a t2.micro EC2 instance, wait for email, delete
2. **Explore CloudTrail logs** - Download and inspect logs from S3
3. **Review GuardDuty findings** - AWS Console → GuardDuty → Findings
4. **Set calendar reminder** - Day 28: Decide on GuardDuty

## Clean Up (If Needed)

```bash
# Remove all security resources
terraform destroy -target=module.security

# This will delete:
# - CloudTrail trail
# - S3 bucket (and all logs)
# - GuardDuty detector
# - SNS topic and subscriptions
# - Budget alerts
```

**⚠️ Warning:** Deleting CloudTrail removes all audit history!

## References

- Full module documentation: `terraform/modules/security/README.md`
- CloudTrail logs location: `s3://ml-platform-engineering-practicum-cloudtrail-logs-<YOUR_ACCOUNT_ID>/`
- GuardDuty console: <https://console.aws.amazon.com/guardduty/>
- Budgets console: <https://console.aws.amazon.com/billing/home#/budgets>
