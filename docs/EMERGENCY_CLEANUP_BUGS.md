# Emergency Cleanup Script Bugs

**Date**: 2025-11-08
**Script**: `infra/aws-core/terraform/environments/dev/emergency-cleanup-improved.sh`

## Critical Bugs Found

### Bug #1: Missing VPC Endpoint Deletion
**Severity**: Critical
**Impact**: Blocks Terraform apply due to conflicting DNS domains

**Description**: Script does not delete VPC endpoints at all. When Terraform tries to recreate them with `private_dns_enabled = true`, it fails with:
```
Error: creating EC2 VPC Endpoint (com.amazonaws.us-west-2.ecr.dkr):
private-dns-enabled cannot be set because there is already a conflicting DNS domain
for *.dkr.ecr.us-west-2.amazonaws.com in the VPC
```

**Root Cause**: No `delete_vpc_endpoints()` function exists in the script.

**Evidence**:
- 6 VPC endpoints left behind: S3, ECR API, ECR DKR, STS, EC2, AutoScaling
- All had `private_dns_enabled = true`
- Blocked deployment workflow #19197809403

**Fix Required**:
```bash
delete_vpc_endpoints() {
    log_info "Step X: Deleting VPC Endpoints..."

    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs --region "$REGION" \
        --filters "Name=tag:ManagedBy,Values=Terraform" "Name=tag:Cluster,Values=$CLUSTER_NAME" \
        --query 'Vpcs[0].VpcId' --output text)

    if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
        log_info "  No VPC found"
        return 0
    fi

    local vpce_ids
    vpce_ids=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'VpcEndpoints[].VpcEndpointId' --output text)

    if [[ -z "$vpce_ids" ]]; then
        log_info "  No VPC endpoints found"
        return 0
    fi

    local vpce_array=($vpce_ids)
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "  [DRY RUN] Would delete ${#vpce_array[@]} VPC endpoints"
    else
        log_info "  Deleting ${#vpce_array[@]} VPC endpoints..."
        aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "${vpce_array[@]}" --region "$REGION"
        log_info "  Waiting 90s for ENI cleanup..."
        sleep 90
    fi
}
```

**Call in main()**: Add before `delete_nat_gateways` (VPC endpoints must be deleted before NAT gateways)

### Bug #2: EIP Release Fails When Attached to NAT Gateway
**Severity**: High
**Impact**: Blocks Terraform apply due to "EIP already associated" error

**Description**: Script tries to release EIPs in step 4, but NAT Gateways aren't fully deleted yet (step 3 only waits 60s). EIPs remain attached to NAT Gateway ENIs.

**Error**:
```
Error: waiting for EC2 NAT Gateway (nat-07cfcbeaedad8d1ed) create:
unexpected state 'failed', wanted target 'available'.
last error: Resource.AlreadyAssociated: Elastic IP address [eipalloc-0faddedaf0006dce6]
is already associated
```

**Root Cause**:
- NAT Gateway deletion takes 2-5 minutes, not 60 seconds
- Script doesn't verify NAT Gateways are fully deleted before releasing EIPs
- EIPs can't be released while attached to ENIs

**Fix Required**:
1. Wait for NAT Gateway state to be `deleted` instead of fixed 60s sleep
2. Move EIP release AFTER NAT Gateway deletion verification

```bash
delete_nat_gateways() {
    log_info "Step 3: Deleting NAT Gateways..."

    local nat_gws
    nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
        --filter "Name=state,Values=available" \
        --query 'NatGateways[].NatGatewayId' --output text)

    if [[ -z "$nat_gws" ]]; then
        log_info "  No NAT Gateways found"
        return 0
    fi

    for nat in $nat_gws; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "  [DRY RUN] Would delete: $nat"
        else
            log_info "  Deleting: $nat"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION"
        fi
    done

    if [[ "$DRY_RUN" != "true" && -n "$nat_gws" ]]; then
        log_info "  Waiting for NAT Gateway deletion..."
        for nat in $nat_gws; do
            while true; do
                local state
                state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$nat" --region "$REGION" \
                    --query 'NatGateways[0].State' --output text 2>/dev/null || echo "deleted")
                if [[ "$state" == "deleted" ]]; then
                    break
                fi
                sleep 10
            done
        done
        log_info "  All NAT Gateways deleted"
    fi
}
```

### Bug #3: Unsafe Region-Wide Resource Filtering
**Severity**: Medium
**Impact**: Could delete resources from other projects in same region

**Description**: Functions like `delete_nat_gateways()` and `delete_load_balancers()` query ALL resources in the region, not just those tagged with the cluster.

**Current Code**:
```bash
nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=state,Values=available" \
    --query 'NatGateways[].NatGatewayId' --output text)
```

**Fix Required**: Filter by VPC ID or Terraform tags
```bash
local vpc_id
vpc_id=$(get_vpc_id)

nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
    --query 'NatGateways[].NatGatewayId' --output text)
```

### Bug #4: No EC2 Instance Deletion
**Severity**: Medium
**Impact**: Orphaned EC2 instances continue to incur costs

**Description**: Script counts EC2 instances in summary but never deletes them. Node group deletion should handle this, but if instances are orphaned, they remain running.

**Fix Required**: Add explicit EC2 instance cleanup
```bash
delete_ec2_instances() {
    log_info "Step X: Deleting EC2 instances..."

    local instances
    instances=$(aws ec2 describe-instances --region "$REGION" \
        --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" \
                  "Name=tag:Cluster,Values=$CLUSTER_NAME" \
        --query 'Reservations[].Instances[].InstanceId' --output text)

    if [[ -z "$instances" ]]; then
        log_info "  No EC2 instances found"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "  [DRY RUN] Would terminate: $instances"
    else
        log_info "  Terminating instances: $instances"
        aws ec2 terminate-instances --instance-ids $instances --region "$REGION"
    fi
}
```

## Recommended Execution Order

Proper resource deletion order to respect dependencies:

1. **Node Groups** - Delete first to stop creating new resources
2. **EC2 Instances** - Terminate any orphaned instances
3. **Load Balancers** - Delete before cluster (may have security group rules)
4. **EKS Cluster** - Wait for full deletion
5. **VPC Endpoints** - Delete before NAT (creates ENIs that block subnet deletion)
6. **NAT Gateways** - Delete and wait for full deletion
7. **Elastic IPs** - Release after NAT Gateway ENIs are gone
8. **VPC Resources** - Subnets, route tables, security groups (via Terraform)

## Testing Performed

**Test Date**: 2025-11-08

**Issue Reproduced**:
1. Ran emergency cleanup script
2. Manually deleted 6 VPC endpoints
3. Manually deleted 2 security groups (after removing cross-references)
4. Manually deleted NAT Gateway
5. Manually deleted route tables
6. VPC deletion succeeded

**Triggered by**:
- Deployment workflow #19197249085 failed after 48 minutes with SSM credential errors
- Deployment workflow #19197809403 failed due to leftover VPC endpoints and EIP

## Impact Assessment

**Current State**:
- Script is **unsafe for production use**
- Leaves critical resources behind (VPC endpoints, potentially EIPs)
- Blocks infrastructure redeployment
- Requires manual AWS Console cleanup

**Recommendation**: **Do not use this script until all bugs are fixed**

Use manual cleanup process instead:
1. Delete node groups via AWS Console/CLI
2. Delete EKS cluster and wait for completion
3. Delete VPC endpoints
4. Delete NAT Gateways and wait for completion
5. Release Elastic IPs
6. Run `terraform destroy` for remaining resources
