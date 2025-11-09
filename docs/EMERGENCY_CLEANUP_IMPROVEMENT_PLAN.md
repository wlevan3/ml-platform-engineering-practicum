# Emergency Cleanup Script Improvement Plan

**Target File**: `infra/aws-core/terraform/environments/dev/emergency-cleanup-improved.sh`
**Current Version**: commit ba3680f
**Status**: ⚠️ DO NOT USE - Critical safety issues identified
**Plan Created**: 2025-11-08

## Executive Summary

The emergency cleanup script has **7 critical deficiencies** that make it unsafe and incomplete compared to `cleanup-failed-nodegroups.sh`:

| Issue | Severity | Impact |
|-------|----------|--------|
| **NO file logging** | P0 | Zero audit trail for AWS resource deletions |
| **Unsafe filtering** | P0-CRITICAL | Deletes ALL NAT gateways/load balancers in region |
| **No verification** | P0 | Silent failures, no confirmation of deletions |
| **Sequential deletion** | P1 | Slow (4+ minutes vs <1 minute) |
| **Incomplete coverage** | P1 | Missing VPC, subnets, security groups, IGW, etc. |
| **Poor error handling** | P1 | `2>/dev/null` hides all errors |
| **No progress feedback** | P2 | User has no idea what's happening |

**Risk Assessment**: Current script could accidentally delete production NAT gateways or load balancers in shared AWS accounts.

## Priority Matrix

### P0 - Critical (Must Fix Before Use)

1. **Add File Logging**
   - Why: Zero audit trail for deletions is unacceptable
   - Effort: Low (30 minutes)
   - Pattern: Copy from `cleanup-failed-nodegroups.sh`

2. **Fix Resource Filtering**
   - Why: DANGEROUS - deletes all NAT/LB in region
   - Effort: Medium (1 hour)
   - Pattern: Add VPC/cluster tag filtering

3. **Add Verification**
   - Why: Silent failures hide problems
   - Effort: Medium (1 hour)
   - Pattern: Verify each deletion actually happened

### P1 - Important (Improves Reliability)

1. **Add Parallel Deletion**
   - Why: 4x faster execution
   - Effort: Medium (1 hour)
   - Pattern: Background processes with wait tracking

2. **Complete Resource Coverage**
   - Why: Leaves behind expensive VPCs
   - Effort: High (2 hours)
   - Pattern: Add VPC, subnets, security groups, IGW, route tables

3. **Improve Error Handling**
   - Why: `2>/dev/null` hides all errors
   - Effort: Medium (45 minutes)
   - Pattern: Proper error capture and retry logic

### P2 - Nice to Have

1. **Progress Feedback**
   - Why: Better UX
   - Effort: Low (30 minutes)
   - Pattern: Progress bars or step indicators

2. **Time Estimates**
   - Why: User knows how long to wait
   - Effort: Low (15 minutes)
   - Pattern: Start/end timestamps

## Implementation Plan

### Phase 1: Safety & Logging (P0) - 2 hours

#### 1.1 Add File Logging

**Current State**:

```bash
# Line 8: No logging setup
set -euo pipefail
```

**After**:

```bash
set -euo pipefail

# Logging setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/emergency-cleanup-$(date +%Y%m%d_%H%M%S).log"

# Log to both console and file
exec > >(tee -a "$LOG_FILE") 2>&1

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_info "Emergency cleanup started - Log file: $LOG_FILE"
log_info "DRY_RUN mode: ${DRY_RUN:-false}"
```

**Files Created**:

- `logs/emergency-cleanup-20251108_143052.log` (timestamped)

**Benefit**: Complete audit trail of all deletions

---

#### 1.2 Fix NAT Gateway Filtering

**Current State (DANGEROUS)**:

```bash
# Line 127 - Deletes ALL NAT gateways in region
nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null || echo "")
```

**After (SAFE)**:

```bash
# Get VPC ID for cluster
vpc_id=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")

if [[ -z "$vpc_id" ]]; then
    log_warn "Could not determine VPC ID for cluster $CLUSTER_NAME"
    nat_gws=""
else
    log_info "Filtering NAT gateways by VPC: $vpc_id"
    nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
      --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
      --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null || echo "")
fi
```

**Benefit**: Only deletes NAT gateways in the cluster's VPC, not all in region

---

#### 1.3 Fix Load Balancer Filtering

**Current State (DANGEROUS)**:

```bash
# Line 158 - NO FILTERING AT ALL
lbs=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || echo "")
```

**After (SAFE)**:

```bash
# Only delete load balancers with cluster tag
log_info "Filtering load balancers by tag: kubernetes.io/cluster/$CLUSTER_NAME"
lbs=$(aws elbv2 describe-load-balancers --region "$REGION" 2>/dev/null | \
  jq -r --arg cluster "$CLUSTER_NAME" \
    '.LoadBalancers[] | select(.LoadBalancerArn) | .LoadBalancerArn as $arn |
     if ($arn | length > 0) then $arn else empty end' || echo "")

# Filter by tags
filtered_lbs=""
for lb_arn in $lbs; do
    tags=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --region "$REGION" 2>/dev/null || echo "")
    if echo "$tags" | jq -e --arg cluster "$CLUSTER_NAME" \
      '.TagDescriptions[].Tags[] | select(.Key == "kubernetes.io/cluster/\($cluster)")' > /dev/null 2>&1; then
        filtered_lbs="$filtered_lbs $lb_arn"
        log_info "Found cluster load balancer: $lb_arn"
    fi
done
lbs="$filtered_lbs"
```

**Benefit**: Only deletes cluster-owned load balancers, not all in region

---

#### 1.4 Add Deletion Verification

**Current State**:

```bash
# Line 136 - No verification
for nat in $nat_gws; do
    echo "  Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION" 2>/dev/null || echo "    Failed to delete"
done
```

**After**:

```bash
deleted_nat=0
failed_nat=0

for nat in $nat_gws; do
    log_info "Deleting NAT Gateway: $nat"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete NAT Gateway: $nat"
        deleted_nat=$((deleted_nat + 1))
        continue
    fi

    if aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Successfully initiated deletion: $nat"

        # Verify deletion started
        if aws ec2 describe-nat-gateways --nat-gateway-ids "$nat" --region "$REGION" \
          --query 'NatGateways[0].State' --output text 2>/dev/null | grep -q "delet"; then
            log_info "Verified NAT Gateway $nat is deleting"
            deleted_nat=$((deleted_nat + 1))
        else
            log_warn "NAT Gateway $nat deletion not confirmed"
            failed_nat=$((failed_nat + 1))
        fi
    else
        log_error "Failed to delete NAT Gateway: $nat"
        failed_nat=$((failed_nat + 1))
    fi
done

log_info "NAT Gateway deletion summary: $deleted_nat deleted, $failed_nat failed"
```

**Benefit**: Know exactly what succeeded/failed

---

### Phase 2: Performance & Reliability (P1) - 4 hours

#### 2.1 Add Parallel Deletion

**Pattern** (apply to node groups, instances, NAT gateways):

```bash
# Before: Sequential deletion
for ng in $node_groups; do
    aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" ...
done

# After: Parallel deletion
pids=()
deleted_ng=0
failed_ng=0

for ng in $node_groups; do
    (
        log_info "Deleting node group: $ng"
        if aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"; then
            echo "$ng:success"
        else
            echo "$ng:failed"
        fi
    ) &
    pids+=($!)

    # Limit concurrent deletions to 5
    if [[ ${#pids[@]} -ge 5 ]]; then
        wait "${pids[@]}"
        pids=()
    fi
done

# Wait for remaining
wait "${pids[@]}"

log_info "Node group deletion completed"
```

**Benefit**: ~4x faster (parallel AWS API calls)

---

#### 2.2 Add Missing Resource Types

**Current Coverage**:

- ✅ EKS cluster
- ✅ Node groups
- ✅ EC2 instances
- ⚠️ NAT gateways (unsafe filtering)
- ⚠️ Load balancers (unsafe filtering)

**Missing**:

- ❌ VPC
- ❌ Subnets
- ❌ Security groups
- ❌ Internet gateway
- ❌ Route tables
- ❌ Elastic IPs (from NAT gateways)
- ❌ Network interfaces

**Add After NAT Gateway Deletion**:

```bash
# Step 7: Delete Internet Gateway
log_info "Deleting Internet Gateway..."
if [[ -n "$vpc_id" ]]; then
    igw_id=$(aws ec2 describe-internet-gateways --region "$REGION" \
      --filters "Name=attachment.vpc-id,Values=$vpc_id" \
      --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")

    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        log_info "Found Internet Gateway: $igw_id"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$REGION"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION"
        log_info "Deleted Internet Gateway: $igw_id"
    fi
fi

# Step 8: Delete Subnets
log_info "Deleting Subnets..."
if [[ -n "$vpc_id" ]]; then
    subnet_ids=$(aws ec2 describe-subnets --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc_id" \
      --query 'Subnets[*].SubnetId' --output text 2>/dev/null || echo "")

    for subnet in $subnet_ids; do
        log_info "Deleting subnet: $subnet"
        aws ec2 delete-subnet --subnet-id "$subnet" --region "$REGION" 2>&1 | tee -a "$LOG_FILE" || log_warn "Failed to delete subnet $subnet"
    done
fi

# Step 9: Delete Security Groups (except default)
log_info "Deleting Security Groups..."
if [[ -n "$vpc_id" ]]; then
    sg_ids=$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc_id" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")

    for sg in $sg_ids; do
        log_info "Deleting security group: $sg"
        aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>&1 | tee -a "$LOG_FILE" || log_warn "Failed to delete security group $sg"
    done
fi

# Step 10: Delete Route Tables (except main)
log_info "Deleting Route Tables..."
if [[ -n "$vpc_id" ]]; then
    rt_ids=$(aws ec2 describe-route-tables --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc_id" \
      --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")

    for rt in $rt_ids; do
        # Disassociate first
        assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rt" --region "$REGION" \
          --query 'RouteTables[0].Associations[*].RouteTableAssociationId' --output text 2>/dev/null || echo "")
        for assoc in $assoc_ids; do
            aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION" 2>/dev/null || true
        done

        log_info "Deleting route table: $rt"
        aws ec2 delete-route-table --route-table-id "$rt" --region "$REGION" 2>&1 | tee -a "$LOG_FILE" || log_warn "Failed to delete route table $rt"
    done
fi

# Step 11: Delete VPC
log_info "Deleting VPC..."
if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
    log_info "Deleting VPC: $vpc_id"
    if aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Successfully deleted VPC: $vpc_id"
    else
        log_error "Failed to delete VPC: $vpc_id (may have dependencies)"
    fi
fi
```

**Benefit**: Complete cleanup, no lingering resources

---

#### 2.3 Improve Error Handling

**Current Pattern (BAD)**:

```bash
aws eks delete-nodegroup ... 2>/dev/null || echo "Failed"
```

**New Pattern (GOOD)**:

```bash
delete_with_retry() {
    local resource_type=$1
    local resource_id=$2
    local delete_cmd=$3
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        log_info "Attempting to delete $resource_type: $resource_id (attempt $((retry + 1))/$max_retries)"

        if eval "$delete_cmd" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Successfully deleted $resource_type: $resource_id"
            return 0
        else
            retry=$((retry + 1))
            if [[ $retry -lt $max_retries ]]; then
                log_warn "Failed to delete $resource_type: $resource_id, retrying in 5s..."
                sleep 5
            fi
        fi
    done

    log_error "Failed to delete $resource_type: $resource_id after $max_retries attempts"
    return 1
}

# Usage:
delete_with_retry "node group" "$ng" \
  "aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $ng --region $REGION"
```

**Benefit**: Resilient to transient AWS API errors

---

### Phase 3: UX Improvements (P2) - 1 hour

#### 3.1 Add Progress Feedback

```bash
show_progress() {
    local current=$1
    local total=$2
    local item=$3

    local percent=$((current * 100 / total))
    local bar_length=40
    local filled=$((current * bar_length / total))

    printf "\r[%s%s] %d%% (%d/%d) %s" \
        "$(printf '#%.0s' $(seq 1 $filled))" \
        "$(printf ' %.0s' $(seq 1 $((bar_length - filled))))" \
        "$percent" "$current" "$total" "$item"
}

# Usage in loop:
total=${node_group_count}
current=0
for ng in $node_groups; do
    current=$((current + 1))
    show_progress $current $total "$ng"
    # ... deletion logic
done
echo ""  # Newline after progress bar
```

#### 3.2 Add Time Estimates

```bash
# At start:
START_TIME=$(date +%s)
log_info "Cleanup started at $(date '+%Y-%m-%d %H:%M:%S')"

# At end:
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log_info "Cleanup completed in ${DURATION}s"
log_info "Log file: $LOG_FILE"
```

---

## Testing Strategy

### Pre-Implementation Testing

1. **Backup current script**:

   ```bash
   cp emergency-cleanup-improved.sh emergency-cleanup-improved.sh.backup
   ```

2. **Test with DRY_RUN=true**:

   ```bash
   DRY_RUN=true ./emergency-cleanup-improved.sh
   ```

3. **Verify log file creation**:

   ```bash
   ls -lh logs/emergency-cleanup-*.log
   cat logs/emergency-cleanup-*.log
   ```

### Phase Testing

**After Phase 1 (Safety)**:

- [ ] Verify log file created with timestamps
- [ ] Verify NAT gateway filtering uses VPC ID
- [ ] Verify load balancer filtering uses cluster tags
- [ ] Run DRY_RUN against real AWS account
- [ ] Check no unintended resources listed

**After Phase 2 (Performance)**:

- [ ] Time sequential vs parallel deletion
- [ ] Verify all resource types covered
- [ ] Test retry logic with intentional failures
- [ ] Verify complete cleanup (no orphaned resources)

**After Phase 3 (UX)**:

- [ ] Verify progress bars display correctly
- [ ] Check time estimates accurate
- [ ] Review log readability

### Rollout Plan

```bash
# Step 1: Implement Phase 1 (Safety) - 2 hours
git checkout -b fix/emergency-cleanup-safety
# ... implement logging, filtering, verification
git commit -m "fix(scripts): add logging and safe filtering to emergency cleanup"

# Step 2: Test Phase 1
DRY_RUN=true ./emergency-cleanup-improved.sh
# Review logs, verify filtering

# Step 3: Implement Phase 2 (Performance) - 4 hours
# ... implement parallel deletion, complete coverage, error handling
git commit -m "perf(scripts): add parallel deletion and complete resource coverage"

# Step 4: Implement Phase 3 (UX) - 1 hour
# ... implement progress bars, time estimates
git commit -m "feat(scripts): add progress feedback to emergency cleanup"

# Step 5: Push and create PR
git push origin fix/emergency-cleanup-safety
gh pr create --title "fix(scripts): Improve emergency cleanup safety and performance"
```

---

## Success Metrics

### Before Improvements

- ❌ No audit trail
- ❌ Unsafe resource filtering
- ❌ ~4 minutes execution time
- ❌ Silent failures
- ❌ Leaves behind VPC and subnets

### After Improvements

- ✅ Complete audit trail in timestamped log files
- ✅ Safe VPC/cluster-scoped filtering
- ✅ <1 minute execution time (parallel)
- ✅ Verified deletions with retry logic
- ✅ Complete cleanup (zero orphaned resources)
- ✅ Progress feedback and time estimates

---

## Estimated Effort

| Phase | Hours | Priority |
|-------|-------|----------|
| Phase 1: Safety & Logging | 2 | P0 - Critical |
| Phase 2: Performance & Reliability | 4 | P1 - Important |
| Phase 3: UX Improvements | 1 | P2 - Nice to have |
| **Total** | **7 hours** | |

**Can be done incrementally**: Each phase can be committed separately.

---

## Final Recommendation

**DO NOT use current script** until at least Phase 1 is complete. The unsafe filtering is a **critical production risk**.

**Minimum viable improvement**: Complete Phase 1 (2 hours) to make script safe for use.

**Full improvement**: All 3 phases (7 hours) to match quality of `cleanup-failed-nodegroups.sh`.

**Alternative**: Use `terraform destroy` instead, which has built-in safety and completeness.
