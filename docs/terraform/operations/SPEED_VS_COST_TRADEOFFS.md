# EKS Deployment Speed vs. Cost Tradeoffs

**Problem**: EKS takes 15-20 minutes to create, which is slow for frequent testing sessions.

**Question**: Can we speed this up by keeping some resources running?

## ⏱️ Deployment Time Breakdown

| Component | Creation Time | Destruction Time | Can Skip? |
|-----------|---------------|------------------|-----------|
| **EKS Control Plane** | **10-12 min** | 8-10 min | ❌ No - Required |
| **VPC + Subnets** | 1-2 min | 1-2 min | ✅ Yes - Keep between sessions |
| **NAT Gateway** | 2-3 min | 2-3 min | ✅ Yes - Keep between sessions |
| **EC2 Nodes** | 3-5 min | 2-3 min | ❌ No - Part of EKS |
| **Load Balancer Controller** | 1-2 min | 1 min | ❌ No - Part of EKS |
| **Total** | **15-20 min** | **12-15 min** | - |

**Bottleneck**: EKS control plane (10-12 min) is **unavoidable** - AWS provisions masters, etcd, API servers.

---

## 🚀 Speed-Up Options

### Option 1: Destroy Everything (Slowest, Cheapest)

**Strategy**: Destroy EKS + VPC + NAT between sessions

```bash
./destroy-eks.sh
# or
terraform destroy
```

| Metric | Value |
|--------|-------|
| **Recreation time** | 15-20 minutes |
| **Daily cost (idle)** | $0.05/day |
| **Monthly cost (idle)** | $0.60/month |
| **Best for** | Weekend/weekly use, maximum cost savings |

**Pros**:

- ✅ Minimum cost ($0.60/month = CloudTrail only)
- ✅ No risk of forgetting resources

**Cons**:

- ❌ Slowest recreation (15-20 min every time)
- ❌ Must recreate networking stack

---

### Option 2: Keep VPC/NAT (Faster, Moderate Cost)

**Strategy**: Destroy EKS, keep VPC and NAT Gateway

```bash
./destroy-eks-only.sh
```

| Metric | Value |
|--------|-------|
| **Recreation time** | **8-10 minutes** ⚡ |
| **Daily cost (idle)** | $1.60/day |
| **Monthly cost (idle)** | $48/month |
| **Best for** | Daily testing, 5-10 min sessions |

**Pros**:

- ✅ **40-50% faster** (8-10 min vs. 15-20 min)
- ✅ Networking ready instantly
- ✅ Still saves $4.67/day vs. 24/7 EKS

**Cons**:

- ❌ VPC + NAT Gateway costs $1.60/day even when idle ($48/month vs. $0.60)
- ❌ Higher monthly cost compared to full destruction

---

### Option 3: Keep EKS Running (Fastest, Most Expensive)

**Strategy**: Never destroy, leave EKS running 24/7

```bash
# Don't destroy anything
```

| Metric | Value |
|--------|-------|
| **Recreation time** | **0 minutes** (instant) ⚡⚡⚡ |
| **Daily cost** | $6.27/day |
| **Monthly cost** | $188/month |
| **Best for** | Production, continuous development |

**Pros**:

- ✅ **Instant access** (no wait time)
- ✅ No terraform apply delays

**Cons**:

- ❌ **Expensive**: $188/month
- ❌ High cost for intermittent use
- ❌ Risk of forgetting and accruing charges

---

## 📊 Cost-Benefit Analysis

### Scenario 1: Quick Daily Testing (15 min/day)

| Approach | Monthly Time Waiting | Monthly Cost | Cost per Hour Saved |
|----------|---------------------|--------------|---------------------|
| **Destroy all** | 300 min (5 hours) | $3/month | Baseline |
| **Keep VPC/NAT** | 160 min (2.7 hours) | $50/month | **$20/hour** saved |
| **Keep EKS 24/7** | 0 min | $190/month | **$63/hour** saved |

**Verdict**: **Not worth it** - Paying $47/month to save 2.3 hours is $20/hour

---

### Scenario 2: Heavy Daily Use (2 hours/day)

| Approach | Monthly Time Waiting | Monthly Cost | Cost per Hour Saved |
|----------|---------------------|--------------|---------------------|
| **Destroy all** | 300 min (5 hours) | $18/month | Baseline |
| **Keep VPC/NAT** | 160 min (2.7 hours) | $65/month | **$20/hour** saved |
| **Keep EKS 24/7** | 0 min | $205/month | **$70/hour** saved |

**Verdict**: Still **not worth it** for learning project

---

### Scenario 3: All-Day Development (8 hours/day, weekdays)

| Approach | Monthly Time Waiting | Monthly Cost |
|----------|---------------------|--------------|
| **Destroy all** | 300 min (5 hours) | $65/month |
| **Keep VPC/NAT** | 160 min (2.7 hours) | $112/month |
| **Keep EKS 24/7** | 0 min | $190/month |

**Verdict**: **Keep VPC** saves 2.3 hours/month for $47 extra - reasonable tradeoff

---

## 🎯 Recommendations by Use Case

### For Your Situation (Few Minutes at a Time)

**Recommended**: **Option 1 - Destroy Everything**

**Reasoning**:

- You use EKS for "a few minutes at a time"
- Assuming 15 min/day × 20 workdays = 5 hours/month
- Waiting 15-20 min to start work is acceptable
- Saving $47/month ($564/year) is significant for learning

**Cost**: $0.60/month (CloudTrail) + $3/month (15 min/day usage) = **$3.60/month**

---

### If You Use It Daily (30-60 min/day)

**Recommended**: **Still Option 1 - Destroy Everything**

**Reasoning**:

- 15-20 min wait is annoying but acceptable
- Keeping VPC/NAT costs $48/month just to save 7-10 minutes
- **$48/month to save 7 min = $6.86 per minute saved** 😱
- Not worth it for a learning project

**Alternative**: Work on something else during the 15-20 min wait (read docs, plan work, etc.)

---

### If You're Doing Multi-Hour Sessions Daily

**Recommended**: **Option 2 - Keep VPC/NAT**

**Reasoning**:

- If working 2-4 hours/day, the 15-20 min startup is annoying
- Keeping VPC saves 7-10 min per session
- $48/month might be worth it for convenience
- Still cheaper than 24/7 EKS ($190/month)

---

## 💡 Alternative Speed-Up Strategies

### 1. Use Terraform Parallelism

Speed up terraform apply by increasing parallelism:

```bash
terraform apply -parallelism=20
```

**Savings**: Marginal (maybe 1-2 min), but free

---

### 2. Pre-warm During Commute/Breaks

Start `terraform apply` before you're ready to work:

```bash
# Morning: Start apply remotely
ssh my-dev-machine "cd infra/aws-core/terraform/environments/dev && terraform apply"

# 20 minutes later: Cluster ready when you sit down
```

---

### 3. Use Local Kubernetes for Quick Tests

For quick experiments, use **k3d** or **kind** instead of EKS:

```bash
# Install k3d (takes 30 seconds)
k3d cluster create test --agents 2

# Deploy your app
kubectl apply -f clusters/dev/bootstrap/k8s-manifests/

# Test locally
curl http://localhost:8080/health

# Destroy
k3d cluster delete test
```

**When to use**:

- Quick testing (< 5 minutes)
- Debugging Kubernetes manifests
- Testing deployments before EKS

**When NOT to use**:

- Testing AWS-specific features (ALB, ECR, IAM)
- Load testing
- Production-like environment

---

### 4. Batch Your Testing

Instead of:

- Session 1: Test feature A (15 min wait + 10 min work)
- Session 2: Test feature B (15 min wait + 10 min work)

Do:

- Session 1: Test features A+B+C (15 min wait + 30 min work)

**Savings**: Eliminates 2 × 15 min = 30 min of waiting

---

## 🧮 Cost Calculator

Use this to decide for your specific usage pattern:

```text
Monthly cost = Base cost + Usage cost

Base cost (always on):
  - CloudTrail: $0.60
  - VPC/NAT (if kept): +$48
  - EKS 24/7 (if kept): +$140

Usage cost:
  - EKS cluster: $0.10/hour
  - EC2 nodes: $0.08/hour
  - NAT Gateway (if not kept): $0.045/hour
  - ALB: $0.0225/hour
  - Total: $0.26/hour

Example:
  - 15 min/day × 20 days = 5 hours/month
  - Cost = $0.60 + (5 × $0.26) = $1.90/month ✅

  - 2 hours/day × 20 days = 40 hours/month
  - Cost = $0.60 + (40 × $0.26) = $11/month ✅
```

---

## ✅ Final Answer to Your Question

### Should I keep VPC/NAT running to speed up deployment?

**For your use case (few minutes at a time):** **NO**

**Reasons**:

1. You'd pay **$48/month** to save 7-10 minutes per session
2. **Cost per minute saved**: $6.86 😱
3. That's **$48 ÷ 7 min ≈ $7/minute** of convenience
4. For comparison, a $15/hour developer values their time at **$0.25/minute**

**Better alternatives**:

1. **Accept the 15-20 min wait** - Use the time productively (read docs, plan work)
2. **Batch your testing** - Do multiple tests in one session
3. **Use local k3d for quick experiments** - Reserve EKS for AWS-specific testing
4. **Pre-warm the cluster** - Start `terraform apply` before you're ready to work

---

## 📋 Quick Reference

| Strategy | Setup Time | Idle Cost/Month | When to Use |
|----------|-----------|----------------|-------------|
| **Destroy all** | 15-20 min | $0.60 | **Default for learning** |
| **Keep VPC/NAT** | 8-10 min | $48 | Daily multi-hour sessions |
| **Keep EKS 24/7** | 0 min | $188 | Production/continuous dev |
| **Use local k3d** | 30 sec | $0 | Quick experiments only |

---

## 🎓 Learning Takeaway

**Premature optimization is expensive!**

The 15-20 minute EKS startup time feels slow, but:

- It's **AWS reality** (EKS control plane provisioning)
- Workarounds cost $48-188/month
- For a **learning project**, the cost isn't justified
- Use the wait time productively or use local k8s for quick tests

**The best optimization**: Embrace the constraint and work around it, not through it.
