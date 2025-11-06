# Spot Instances Cost Optimization

This document explains the spot instances configuration for EKS worker nodes, which provides
**70% cost savings** compared to on-demand instances.

## Overview

Spot instances allow you to use spare AWS EC2 capacity at significantly reduced prices.
The trade-off is that AWS can interrupt (terminate) spot instances with 2 minutes notice
when it needs the capacity back.

**Cost Comparison** (per hour):

- On-Demand t3.medium: **$0.0416/hour** × 2 nodes = $0.0832/hour
- Spot t3.medium: **~$0.0125/hour** × 2 nodes = $0.0250/hour
- **Savings**: ~70% = $0.0582/hour

**For your usage pattern** (15 min/day × 20 days/month):

- On-Demand: $0.62/month
- Spot: $0.19/month
- **Savings**: **$0.43/month** (~70%)

## Configuration

### Terraform Variables

The spot instances feature is controlled by variables in `terraform/environments/dev/variables.tf`:

```hcl
variable "use_spot_instances" {
  description = "Use Spot instances instead of On-Demand for EKS nodes"
  type        = bool
  default     = true  # Enabled by default for dev environment
}

variable "spot_max_price" {
  description = "Maximum price for spot instances (USD/hour)"
  type        = string
  default     = ""  # Empty = no limit (use on-demand price as ceiling)
}
```

### EKS Node Group

The node group configuration in `terraform/environments/dev/main.tf` uses:

1. **Multiple instance types** for better spot availability:
   - `t3.medium` - Primary (Intel)
   - `t3a.medium` - AMD alternative (similar specs, slightly cheaper)
   - `t2.medium` - Older generation fallback

2. **Capacity type**: `SPOT` when `use_spot_instances = true`

3. **Node labels**: `node-lifecycle=spot` for pod scheduling awareness

### Kubernetes Deployment

The deployment in `k8s/deployment.yaml` includes:

1. **Pod anti-affinity** - Spreads pods across nodes to avoid single point of failure
2. **Multiple replicas** (2) - Ensures at least one pod survives spot interruption
3. **Optional tolerations** (commented out) - Can be enabled if using node taints

## How Spot Interruptions Work

### What Happens During Interruption

1. **AWS sends 2-minute warning** via EC2 Instance Metadata and CloudWatch Events
2. **Node is cordoned** (no new pods scheduled)
3. **Pods are gracefully terminated** (receives SIGTERM, 30-second grace period)
4. **Kubernetes reschedules pods** to other available nodes
5. **Node is terminated** after 2 minutes

### High Availability Design

With 2 replicas and pod anti-affinity:

- Pods are scheduled on **different nodes**
- If Node A is interrupted, **Pod A terminates** but **Pod B keeps serving traffic**
- Kubernetes **automatically creates new Pod A** on Node B (or a new node)
- **Zero downtime** for your API

### Interruption Frequency

Spot interruption rates vary by instance type and region:

- **Average**: 5-10% interruption rate
- **t3.medium in us-west-2**: Typically <5% (stable spot market)
- **For dev/test**: Completely acceptable
- **For production**: Use Spot for non-critical workloads or mixed on-demand/spot

## Monitoring Spot Instances

### Check if Nodes are Spot

```bash
# View node capacity type
kubectl get nodes -L eks.amazonaws.com/capacityType

# Expected output:
# NAME                                         STATUS   CAPACITYTYPE
# ip-10-0-1-123.us-west-2.compute.internal    Ready    SPOT
# ip-10-0-2-456.us-west-2.compute.internal    Ready    SPOT
```

### Check Spot Interruption Notices

```bash
# Watch for spot interruption events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i spot

# Check node conditions
kubectl describe node <node-name> | grep -i interrupt
```

### View Spot Instance Details in AWS

```bash
# List spot instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ml-platform-engineering-practicum" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceLifecycle,InstanceType,SpotInstanceRequestId]' \
  --output table

# Check spot pricing history
# Linux: date -u -d '1 hour ago' | macOS: date -u -v-1H
aws ec2 describe-spot-price-history \
  --instance-types t3.medium t3a.medium t2.medium \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --product-descriptions "Linux/UNIX" \
  --region us-west-2 \
  --output table
```

## AWS Node Termination Handler (Optional)

For production-grade spot instance handling, deploy the AWS Node Termination Handler:

### What It Does

- **Detects spot interruption notices** from EC2 metadata
- **Drains nodes gracefully** before termination
- **Taints nodes** during termination to prevent new pods
- **Handles scheduled maintenance events** (not just spot interruptions)

### Deployment

The handler is **optional** for dev environments but **recommended** for production:

```bash
# Deploy via Helm (already configured in terraform/environments/dev/main.tf)
# Uncomment the aws_node_termination_handler module to enable

terraform apply
```

Configuration is in `terraform/environments/dev/spot_termination_handler.tf` (to be created).

## Disabling Spot Instances

If you encounter issues or want to switch back to on-demand:

### Option 1: Terraform Variable

```bash
cd terraform/environments/dev

# Edit terraform.tfvars
echo 'use_spot_instances = false' >> terraform.tfvars

# Apply changes
terraform apply
```

### Option 2: Command Line

```bash
terraform apply -var="use_spot_instances=false"
```

### Option 3: Edit variables.tf

```hcl
variable "use_spot_instances" {
  default = false  # Change from true to false
}
```

## When to Use Spot vs On-Demand

### ✅ Use Spot Instances For

- **Dev/test environments** (like this practicum)
- **Stateless workloads** (your FastAPI pods)
- **Fault-tolerant applications** (multiple replicas)
- **Batch processing** (can retry on interruption)
- **Short-lived clusters** (destroy after each session)

### ❌ Avoid Spot Instances For

- **Single-replica deployments** (no redundancy)
- **Stateful workloads** without proper backups
- **Long-running jobs** that can't tolerate interruption
- **Workloads requiring guaranteed uptime**

For this ML Platform practicum:

- **Perfect use case** for spot instances
- 2 replicas = high availability
- Stateless API = no data loss risk
- Short sessions = low interruption probability
- **Recommended**: Keep spot instances enabled

## Cost-Benefit Analysis

### Scenario: 15 min/day × 20 days/month

| Configuration | Cost/Month | Savings |
|---------------|------------|---------|
| On-Demand (2× t3.medium) | $0.62 | Baseline |
| Spot (2× t3.medium) | $0.19 | **$0.43 (70%)** |
| Spot + t3a.medium | $0.17 | **$0.45 (73%)** |

### Break-Even Analysis

Even if spot interruptions cause 10% additional overhead (pod rescheduling, slight downtime):

- Spot cost: $0.19 + 10% overhead = $0.21/month
- Still **$0.41/month savings (66%)** vs on-demand

### Over 4-Month Practicum

- On-Demand total: $2.48
- Spot total: $0.76
- **Savings**: **$1.72 over 4 months**

Not huge dollar amounts, but demonstrates real-world cost optimization practices!

## Troubleshooting

### Issue: Nodes Not Becoming Spot Instances

**Check**:

```bash
# Verify Terraform applied correctly
terraform show | grep capacity_type

# Should show: capacity_type = "SPOT"
```

**Fix**: Re-apply Terraform configuration:

```bash
terraform apply
```

### Issue: Frequent Spot Interruptions

**Check** spot interruption rate:

```bash
# View spot interruption history (AWS Console > EC2 > Spot Requests)
aws ec2 describe-spot-instance-requests \
  --filters "Name=state,Values=closed" \
  --query 'SpotInstanceRequests[*].[InstanceId,Status.Code,Status.Message]'
```

**Fix**: Add more instance types to increase availability:

```hcl
instance_types = [
  "t3.medium", "t3a.medium", "t2.medium",
  "t3.small",  # Add more options
]
```

### Issue: Pods Not Rescheduling After Interruption

**Check** deployment replicas and anti-affinity:

```bash
kubectl get deployment ml-platform-api -n ml-platform -o yaml | grep -A5 replicas
kubectl get pods -n ml-platform -o wide
```

**Fix**: Ensure at least 2 replicas and pod anti-affinity configured (already done in `k8s/deployment.yaml`).

## References

- [AWS EC2 Spot Instances](https://aws.amazon.com/ec2/spot/)
- [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
- [EKS Best Practices - Spot Instances](https://aws.github.io/aws-eks-best-practices/karpenter/spot/)
- [Spot Instance Interruption Notices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html)

## Summary

**Spot instances are ENABLED by default** for this dev environment because:

✅ 70% cost savings
✅ Low risk for dev/test workloads
✅ High availability via 2 replicas
✅ Easy to disable if needed
✅ Teaches real-world cost optimization

**Action Required**: None - spot instances work automatically! Just deploy and enjoy the savings.
