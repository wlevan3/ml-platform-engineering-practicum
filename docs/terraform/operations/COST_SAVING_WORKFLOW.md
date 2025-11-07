# Cost-Saving Workflow for Intermittent EKS Usage

**Use Case**: You only use EKS for a few minutes at a time, then destroy it to save costs.

## 📊 Cost Analysis

### Always-On Resources (Keep Running)

| Resource | Cost | Reason to Keep |
|----------|------|----------------|
| **AWS Budgets** | **FREE** | No cost, protects against surprise bills |
| **CloudTrail** | **~$0.50-1.00/month** | Minimal cost (~$0.02/day), provides audit trail |
| **S3 State Bucket** | **~$0.10-0.50/month** | Stores Terraform state, minimal storage |
| **DynamoDB Lock Table** | **FREE** | Pay-per-request (minimal usage) |
| **TOTAL** | **~$0.60-1.50/month** | **≈ $0.02-0.05/day** |

### Destroy Between Sessions

| Resource | Hourly Cost | Daily Cost (if left on) | When to Destroy |
|----------|-------------|-------------------------|-----------------|
| **EKS Control Plane** | $0.10/hour | **$2.40/day** | After every session |
| **EC2 Nodes (2x t3.medium)** | $0.08/hour | **$1.92/day** | Auto-destroyed with EKS |
| **NAT Gateway** | $0.045/hour | **$1.08/day** | Auto-destroyed with VPC |
| **Application Load Balancer** | $0.0225/hour | **$0.54/day** | Auto-destroyed with Ingress |
| **GuardDuty** | $10-30/month | **$0.33-1.00/day** | Disable after trial |
| **TOTAL** | **$0.26/hour** | **$6.27/day** | Destroy immediately after use |

### Cost Comparison

| Scenario | Daily Cost | Monthly Cost |
|----------|------------|--------------|
| **EKS running 24/7** + always-on | $6.27 + $0.05 = **$6.32/day** | **~$190/month** 😱 |
| **EKS 15 min/day** + always-on | $0.065 + $0.05 = **$0.12/day** | **~$3.50/month** ✅ |
| **EKS 1 hour/day** + always-on | $0.26 + $0.05 = **$0.31/day** | **~$9/month** ✅ |

**Savings**: 15 min/day usage = **98% cost reduction** vs. 24/7

> **Note**: All scenarios include always-on baseline costs ($0.05/day for CloudTrail,
> S3 state storage, ECR) for fair comparison. The 98% savings applies to total
> infrastructure costs when using intermittent EKS deployment patterns.

---

## 🔄 Recommended Workflow

### Initial Setup (One-Time)

```bash
cd infra/aws-core/terraform/environments/dev

# 1. Deploy always-on resources (CloudTrail, Budgets)
terraform init
terraform apply -target=module.security

# 2. Confirm budget email subscription (check inbox)

# 3. Verify deployment
aws cloudtrail get-trail-status --name ml-platform-engineering-practicum-trail
```

**Cost**: ~$0.02/day ($0.60/month)

---

### Daily Work Session

#### Start of Session (Create Infrastructure)

```bash
cd infra/aws-core/terraform/environments/dev

# Deploy EKS cluster, VPC, ECR
terraform apply

# Expected time: 15-20 minutes
# Expected hourly cost while running: $0.26/hour
```

#### During Session (Use EKS)

```bash
# Update kubeconfig
aws eks update-kubeconfig --name ml-platform-dev --region us-west-2

# Deploy your application
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/

# Test, debug, experiment...
```

#### End of Session (Destroy Infrastructure)

```bash
cd infra/aws-core/terraform/environments/dev

# Option 1: Use helper script (Recommended - handles all targets correctly)
./destroy-eks-only.sh  # Destroys EKS cluster, keeps VPC for faster recreation
# OR
./destroy-eks.sh       # Full destruction (EKS + VPC), keeps security services

# Option 2: Manual destroy (verify module names first)
# Step 1: Verify current module names (module structure may change over time)
terraform state list

# Step 2: Destroy specific modules based on what you see above
# IMPORTANT: Replace module names below with actual names from state list
terraform destroy -target=module.eks \
                  -target=module.vpc \
                  -target=module.load_balancer_controller_irsa_role \
                  -target=helm_release.aws_load_balancer_controller

# Step 3: Dry-run verification (optional but recommended)
terraform plan  # Should show no changes if destruction was complete

# Verify destruction
aws eks list-clusters  # Should be empty
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=ml-platform*"  # Should be empty
```

**⚠️ Important**: This destroys:

- EKS cluster
- EC2 worker nodes
- VPC, subnets, NAT gateway
- Load balancers
- Security groups

**✅ Preserves**:

- CloudTrail logs (audit trail)
- S3 state bucket (Terraform state)
- AWS Budgets (cost monitoring)
- ECR images (if you pushed any)

---

## 💡 Smart Destruction Strategy

### Option 1: Destroy Everything Except Security (Recommended)

```bash
# Create a helper script
cat > destroy-infra.sh <<'EOF'
#!/bin/bash
set -e

echo "🔥 Destroying EKS infrastructure (keeping CloudTrail, Budgets)..."

cd infra/aws-core/terraform/environments/dev

# Destroy all resources except security module
terraform destroy --auto-approve \
  -target=helm_release.aws_load_balancer_controller \
  -target=module.load_balancer_controller_irsa_role \
  -target=module.eks \
  -target=module.vpc \
  -target=aws_ecr_lifecycle_policy.ml_platform_api

echo "✅ Infrastructure destroyed"
echo "💰 Ongoing cost: ~$0.02/day (CloudTrail + Budgets)"
echo "📊 Budget alerts still active"
EOF

chmod +x destroy-infra.sh
./destroy-infra.sh
```

### Option 2: Destroy Absolutely Everything

```bash
# Only do this if you want to remove CloudTrail and Budgets too
terraform destroy

# This deletes:
# - EKS cluster
# - VPC
# - CloudTrail trail
# - CloudTrail S3 logs (AUDIT HISTORY LOST!)
# - AWS Budgets
# - SNS topics
# - BUT KEEPS: S3 state bucket, DynamoDB lock table
```

**⚠️ Warning**: Deleting CloudTrail removes all audit history!

---

## 🎯 Optimized Workflow Example

### Monday Morning (15-minute session)

```bash
# 9:00 AM - Start
terraform apply              # 15-20 min
# Cost so far: $0

# 9:20 AM - Infrastructure ready
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/        # 2 min
curl http://<ALB_URL>/health # Test
# Cost so far: $0.09 (20 min × $0.26/hour)

# 9:35 AM - Done testing
terraform destroy -target=module.eks -target=module.vpc  # 5 min
# Total session cost: $0.11 (25 min × $0.26/hour)

# Daily total: $0.11 + $0.02 (always-on) = $0.13
```

**Monthly projection**: $0.13/day × 20 workdays = **$2.60/month** ✅

---

## 🚨 What to Keep vs. Destroy

### ✅ KEEP (Always On)

1. **Terraform State Bucket** (`ml-platform-terraform-state`)
   - Cost: ~$0.10-0.50/month
   - Contains Terraform state for all infrastructure
   - **DO NOT DELETE** or you'll lose state tracking

2. **DynamoDB Lock Table** (`ml-platform-terraform-locks`)
   - Cost: FREE (pay-per-request, minimal usage)
   - Prevents concurrent Terraform runs

3. **CloudTrail**
   - Cost: ~$0.50-1.00/month
   - Audit trail: "Who deleted what? When did I create this?"
   - Helps debug cost issues
   - S3 logs grow slowly (~10-50 MB/month)

4. **AWS Budgets**
   - Cost: FREE
   - Protects against accidental resource creation
   - Alerts if something is left running

5. **ECR Repository** (optional)
   - Cost: $0.10/GB/month
   - If you've pushed images, keep repo to avoid rebuilding
   - Delete old images via lifecycle policy (auto-configured)

### ❌ DESTROY (Between Sessions)

1. **EKS Cluster** - $2.40/day if left running
2. **EC2 Worker Nodes** - $1.92/day (2 nodes)
3. **NAT Gateway** - $1.08/day
4. **Load Balancers** - $0.54/day
5. **GuardDuty** - Disable after 30-day trial ($10-30/month)

---

## 📝 Best Practices

### 1. Set Calendar Reminders

- **Every day before closing laptop**: Run `terraform destroy`
- **Weekly**: Check AWS Console for orphaned resources
- **Monthly**: Review budget alert emails

### 2. Use Tagging to Track Costs

All resources are tagged with `Project=ml-platform-engineering-practicum`.

Check costs by tag:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2025-11-01,End=2025-11-04 \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Project
```

### 3. Verify Destruction

After `terraform destroy`, verify:

```bash
# No EKS clusters
aws eks list-clusters

# No VPCs with project tag
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=ml-platform*"

# No EC2 instances
aws ec2 describe-instances --filters "Name=tag:Project,Values=ml-platform*" "Name=instance-state-name,Values=running"

# No load balancers
aws elbv2 describe-load-balancers
```

### 4. Enable AWS Budget Alerts

If you configured `budget_alert_email`, you'll get warnings:

- **50% threshold**: "You've spent $2.50 of $5.00"
- **80% threshold**: "You've spent $4.00 of $5.00"
- **100% threshold**: "Budget exceeded!"

### 5. Review CloudTrail Logs

If you're unsure what's costing money:

```bash
# Download recent CloudTrail logs
aws s3 sync s3://ml-platform-engineering-practicum-cloudtrail-logs-984479408136/ ./cloudtrail-logs/ --exclude "*" --include "*.json.gz"

# Search for resource creation events
gunzip -c cloudtrail-logs/**/*.json.gz | jq '.Records[] | select(.eventName | contains("Create"))'
```

---

## 🆘 Emergency: "I Forgot to Destroy!"

If you left EKS running overnight:

```bash
# Check what's running
aws eks list-clusters
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"

# Destroy immediately
cd infra/aws-core/terraform/environments/dev
terraform destroy -target=module.eks -target=module.vpc --auto-approve

# Check cost impact
aws ce get-cost-and-usage \
  --time-period Start=$(date -v-2d +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost
```

**Cost of leaving EKS running for 1 day**: ~$6.27

---

## 📊 Cost Summary

| Usage Pattern | Monthly Cost | Notes |
|---------------|--------------|-------|
| **24/7 EKS** | **$188/month** | Never destroy, always running |
| **8 hours/day** | **$63/month** | Full workday, weekdays only |
| **1 hour/day** | **$9/month** | Daily testing, destroy after |
| **15 min/day** | **$3.50/month** | Quick tests, immediate destruction |
| **Always-on basics only** | **$0.60/month** | Just CloudTrail + Budgets |

**Your target**: $3.50-9/month (15 min - 1 hour/day usage)

---

## 🎯 Final Recommendation

**For your intermittent usage pattern (few minutes at a time):**

✅ **KEEP running:**

- CloudTrail (~$0.50/month)
- AWS Budgets (FREE)
- S3 state bucket (~$0.10/month)

✅ **DESTROY after every session:**

- EKS cluster
- VPC
- EC2 nodes
- Load balancers

✅ **DISABLE:**

- GuardDuty (after 30-day trial or for intermittent use)

**Expected monthly cost**: $0.60 (always-on) + $2-8 (EKS usage) = **$3-9/month** ✅

This is **94-98% cheaper** than running EKS 24/7! 🎉
