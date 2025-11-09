# Infrastructure Cleanup Runbook

**Last Updated**: 2025-11-08
**Status**: Production Ready
**Audience**: Developers, Operations

---

## Quick Decision Tree

```text
┌─ Need to clean up infrastructure?
│
├─ Planned cleanup (normal workflow)?
│  └─→ Use: terraform destroy (15-20 min, safest)
│     └─ Go to: Path 1 below
│
├─ Emergency cleanup (deployment failed)?
│  │
│  ├─ Terraform state available?
│  │  └─→ Use: terraform destroy (15-20 min)
│  │     └─ Go to: Path 1 below
│  │
│  └─ Terraform state lost/corrupted?
│     └─→ Manual AWS Console cleanup (30-60 min)
│        └─ Go to: Path 2 below
│
└─ Single stuck resource (e.g., failed node group)?
   └─→ Use: cleanup-failed-nodegroups.sh
      └─ See: TROUBLESHOOTING.md
```

---

## Path 1: Terraform Destroy (Recommended)

**When to use**:

- Planned infrastructure teardown
- Emergency cleanup with Terraform state available
- Need complete, safe resource deletion

**Advantages**:

- ✅ Respects resource dependencies automatically
- ✅ State-scoped (won't delete unrelated resources)
- ✅ Atomic operations (rollback on failure)
- ✅ Audit trail in Terraform state

### Prerequisites

1. **Terraform state accessible**:

   ```bash
   cd infra/aws-core/terraform/environments/dev
   terraform state list  # Should return resources
   ```

2. **AWS credentials configured**:

   ```bash
   aws sts get-caller-identity
   # Should show account 984479408136
   ```

3. **No active deployments**:
   - Check GitHub Actions workflows
   - Ensure no one else is running terraform commands

### Step-by-Step Procedure

#### Step 1: Backup State (Safety Net)

```bash
cd infra/aws-core/terraform/environments/dev
terraform state pull > terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
```

**Why**: If destroy fails mid-execution, you can restore state.

#### Step 2: Preview Destruction Plan

```bash
terraform plan -destroy -out=destroy.tfplan
```

**Review output carefully**:

- Verify resource count matches expectations
- Check that only dev cluster resources are listed
- Look for unexpected resources (production data, shared VPCs)

**Expected resources** (~40-50 total):

- 1 EKS cluster
- 1-2 node groups
- 3 private subnets, 3 public subnets
- 6 VPC endpoints (ECR API, ECR DKR, S3, STS, EC2, AutoScaling)
- 1-2 NAT gateways
- 1-2 Elastic IPs
- Security groups, route tables
- 1 VPC

#### Step 3: Execute Destruction

```bash
terraform apply destroy.tfplan
```

**Duration**: 10-15 minutes (varies by resource count)

**Monitor progress**:

- Watch for errors (red text)
- Note any resources that fail to delete
- Common issues: ENI cleanup delay, security group dependencies

#### Step 4: Verify Complete Cleanup

```bash
# Check Terraform state is empty
terraform state list
# Should return: empty or only S3 backend resources

# Verify AWS has zero resources
aws ec2 describe-vpcs --region us-west-2 \
  --filters "Name=tag:Cluster,Values=ml-platform-dev" \
  --query 'Vpcs[].VpcId'
# Should return: []

# Check for orphaned VPC endpoints
aws ec2 describe-vpc-endpoints --region us-west-2 \
  --filters "Name=tag:ManagedBy,Values=Terraform" \
  --query 'VpcEndpoints[].VpcEndpointId'
# Should return: []
```

#### Step 5: Confirm Cost Savings

```bash
# List all running EC2 instances
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=instance-state-name,Values=running" \
           "Name=tag:Cluster,Values=ml-platform-dev" \
  --query 'Reservations[].Instances[].InstanceId'
# Should return: []

# List NAT gateways (each costs ~$32/month)
aws ec2 describe-nat-gateways --region us-west-2 \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId'
# Should return: []
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Error acquiring state lock" | Another terraform process running | Wait for other process to finish, or use `terraform force-unlock` |
| "VPC has dependencies" | ENIs not deleted yet | Wait 2-3 minutes, retry destroy |
| "Security group in use" | Cross-references between SGs | Terraform usually handles this; if not, see Path 2 |
| "Plan shows no changes" | State already clean | Run verification commands (Step 4) |

---

## Path 2: Manual AWS Console (Disaster Recovery)

**When to use**:

- Terraform state lost or corrupted
- State file doesn't match reality
- Terraform destroy fails repeatedly

**⚠️ WARNING**: High risk of incomplete cleanup. Use only when Path 1 fails.

### Resource Deletion Order

**Critical**: Delete in this exact order to avoid dependency errors.

```text
1. Node Groups → wait for DELETED
2. EC2 Instances (if orphaned) → terminate
3. Load Balancers (ELB, ALB, NLB) → delete
4. EKS Cluster → wait for DELETED (5-10 min)
5. VPC Endpoints → delete all 6, wait 2 min
6. NAT Gateways → delete, wait for deleted state (3-5 min)
7. Elastic IPs → release (only after NAT deleted)
8. Security Groups → revoke cross-references first
9. Subnets → delete private, then public
10. Route Tables → delete non-default
11. Internet Gateway → detach, then delete
12. VPC → final deletion
```

### Step-by-Step Deletion

#### 1. Delete Node Groups

```bash
# List node groups
aws eks list-nodegroups --cluster-name ml-platform-dev --region us-west-2

# Delete each node group
aws eks delete-nodegroup \
  --cluster-name ml-platform-dev \
  --nodegroup-name <NAME> \
  --region us-west-2

# Wait for deletion
aws eks wait nodegroup-deleted \
  --cluster-name ml-platform-dev \
  --nodegroup-name <NAME> \
  --region us-west-2
```

#### 2. Terminate EC2 Instances

```bash
# Find cluster instances
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=tag:Cluster,Values=ml-platform-dev" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text

# Terminate
aws ec2 terminate-instances --instance-ids <ID1> <ID2> --region us-west-2
```

#### 3. Delete EKS Cluster

```bash
aws eks delete-cluster --name ml-platform-dev --region us-west-2

# Wait (5-10 minutes)
aws eks wait cluster-deleted --name ml-platform-dev --region us-west-2
```

#### 4. Delete VPC Endpoints (CRITICAL)

```bash
# Get VPC ID first
VPC_ID=$(aws ec2 describe-vpcs --region us-west-2 \
  --filters "Name=tag:Cluster,Values=ml-platform-dev" \
  --query 'Vpcs[0].VpcId' --output text)

# List all VPC endpoints in this VPC
aws ec2 describe-vpc-endpoints --region us-west-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[].VpcEndpointId' --output text

# Delete ALL endpoints
aws ec2 delete-vpc-endpoints \
  --vpc-endpoint-ids <ID1> <ID2> <ID3> <ID4> <ID5> <ID6> \
  --region us-west-2

# Wait 90 seconds for ENI cleanup
sleep 90
```

**Why this matters**: VPC endpoints create ENIs that block subnet deletion. Must delete endpoints AND wait for ENI cleanup.

#### 5. Delete NAT Gateways

```bash
# List NAT gateways in VPC
aws ec2 describe-nat-gateways --region us-west-2 \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'NatGateways[].[NatGatewayId,NatGatewayAddresses[0].AllocationId]' \
  --output text

# Delete each NAT gateway
aws ec2 delete-nat-gateway --nat-gateway-id <NAT-ID> --region us-west-2

# Wait for state=deleted (3-5 minutes)
while true; do
  STATE=$(aws ec2 describe-nat-gateways --nat-gateway-ids <NAT-ID> --region us-west-2 \
    --query 'NatGateways[0].State' --output text 2>/dev/null || echo "deleted")
  if [[ "$STATE" == "deleted" ]]; then
    echo "NAT Gateway deleted"
    break
  fi
  echo "Waiting... (state: $STATE)"
  sleep 10
done
```

#### 6. Release Elastic IPs

```bash
# Release EIP (use AllocationId from NAT gateway output above)
aws ec2 release-address --allocation-id <EIP-ALLOC-ID> --region us-west-2
```

#### 7. Clean Up Security Groups

```bash
# List security groups in VPC
aws ec2 describe-security-groups --region us-west-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]'

# Revoke cross-references first
# Example: if SG1 references SG2
aws ec2 revoke-security-group-ingress \
  --group-id <SG1-ID> \
  --source-group <SG2-ID> \
  --protocol all \
  --region us-west-2

# Delete security groups
aws ec2 delete-security-group --group-id <SG-ID> --region us-west-2
```

#### 8. Delete Subnets, Route Tables, IGW, VPC

```bash
# Delete subnets
aws ec2 delete-subnet --subnet-id <SUBNET-ID> --region us-west-2

# Delete route tables (non-default)
aws ec2 delete-route-table --route-table-id <RT-ID> --region us-west-2

# Detach and delete Internet Gateway
aws ec2 detach-internet-gateway --internet-gateway-id <IGW-ID> --vpc-id $VPC_ID --region us-west-2
aws ec2 delete-internet-gateway --internet-gateway-id <IGW-ID> --region us-west-2

# Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID --region us-west-2
```

### Verification

After manual cleanup, verify zero resources remain:

```bash
# Should return empty
aws resourcegroupstaggingapi get-resources \
  --region us-west-2 \
  --tag-filters "Key=Cluster,Values=ml-platform-dev"
```

---

## Appendix A: Resource Dependencies

**Why deletion order matters**:

```text
VPC
├── Subnets
│   ├── ENIs (from VPC Endpoints, NAT Gateways, EC2)
│   └── Route Tables
│
├── VPC Endpoints
│   └── ENIs (auto-created, 2-3 min to delete)
│
├── NAT Gateways
│   ├── ENIs (auto-created)
│   └── Elastic IPs (associated)
│
├── Security Groups
│   └── Can reference each other
│
└── Internet Gateway
```

**Deletion cascade**:

- VPC Endpoints must delete BEFORE subnets (ENIs block deletion)
- NAT Gateways must reach state=deleted BEFORE EIP release
- Security group cross-references must be revoked BEFORE deletion
- Everything must be deleted BEFORE VPC deletion

---

## Appendix B: Bug History (Prevention Context)

This runbook was created after 2 deployment failures in 24 hours caused by incomplete emergency cleanup. Original bugs:

| Bug | Description | How Terraform Prevents |
|-----|-------------|------------------------|
| #1 | VPC endpoints not deleted | Explicit `depends_on` ensures deletion before security groups |
| #2 | EIP released while NAT still attached | Terraform polls NAT state until fully deleted |
| #3 | Region-wide filtering deleted wrong resources | Terraform is state-scoped (only managed resources) |
| #4 | EC2 instances orphaned | Module dependencies handle cascading deletion |

**Key Lesson**: Use Terraform destroy instead of custom bash scripts. Terraform already knows the dependency graph and handles edge cases.

---

## Appendix C: Recovery Procedures

### If Terraform Destroy Fails Mid-Execution

1. **Don't panic** - Terraform state is still valid
2. **Check what failed**:

   ```bash
   terraform show | grep "Tainted"
   ```

3. **Identify blocker** (usually ENI cleanup delay or security group dependency)
4. **Fix blocker manually** (see Path 2 for specific resource commands)
5. **Retry terraform destroy**:

   ```bash
   terraform destroy --auto-approve
   ```

### If You Need to Restore State

```bash
# List backups
ls -lh terraform.tfstate.backup.*

# Restore specific backup
cp terraform.tfstate.backup.20251108_120000 terraform.tfstate

# Refresh state to match AWS
terraform refresh

# Retry destroy
terraform destroy
```

---

## Related Documentation

- **Troubleshooting**: `TROUBLESHOOTING.md` - Common cleanup mistakes
- **Contributing**: `CONTRIBUTING.md` - Rollback procedures
- **Bug Documentation**: `docs/EMERGENCY_CLEANUP_BUGS.md` - Historical context
- **Terraform Analysis**: `docs/TERRAFORM_DESTROY_ANALYSIS.md` - Why Terraform > bash

---

**Questions?** Review decision tree at top of document or check TROUBLESHOOTING.md.
