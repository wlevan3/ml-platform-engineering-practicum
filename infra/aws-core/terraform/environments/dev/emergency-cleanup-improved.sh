#!/usr/bin/env bash
# =============================================================================
# Emergency AWS Resource Cleanup - DEPRECATED
# =============================================================================
# ⚠️  DEPRECATED: This script is no longer recommended for use.
#
# Use 'terraform destroy' instead for safe, complete resource cleanup.
# See: docs/CLEANUP_RUNBOOK.md for the recommended cleanup procedure.
#
# This script is kept for disaster recovery reference only (when Terraform
# state is corrupted or unavailable). It has known bugs and requires manual
# intervention. Use at your own risk.
#
# Known Issues:
# - Missing VPC endpoint deletion (causes DNS conflicts)
# - Unsafe region-wide filtering (could delete wrong resources)
# - Fixed sleep timings (doesn't adapt to actual AWS deletion times)
#
# Last updated: 2025-11-08
# =============================================================================

echo "⚠️  ERROR: This script is DEPRECATED"
echo ""
echo "Use 'terraform destroy' instead for safe cleanup:"
echo "  cd infra/aws-core/terraform/environments/dev"
echo "  terraform destroy"

echo ""
echo "For detailed cleanup procedures, see: docs/CLEANUP_RUNBOOK.md"

echo ""
echo "If you still need to use this script (disaster recovery only),"
echo "set FORCE_DEPRECATED=true as an environment variable."

echo ""

if [[ "${FORCE_DEPRECATED:-false}" != "true" ]]; then
    echo "❌ Script execution blocked (deprecated)"
    echo "Set FORCE_DEPRECATED=true to override (NOT RECOMMENDED)"
    exit 1
fi

echo "⚠️  WARNING: Proceeding with deprecated emergency cleanup script..."
echo ""

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
while [[ "$REPO_ROOT" != "/" && ! -f "$REPO_ROOT/scripts/logging.sh" ]]; do
    REPO_ROOT="$(dirname "$REPO_ROOT")"
done
if [[ ! -f "$REPO_ROOT/scripts/logging.sh" ]]; then
    echo "[ERROR] Logging helper not found" >&2
    exit 1
fi
source "$REPO_ROOT/scripts/logging.sh"

REGION="us-west-2"
CLUSTER_NAME="ml-platform-dev"
DRY_RUN="${DRY_RUN:-false}"

# AWS cost estimates (monthly, rounded for rough estimation)
readonly NAT_GATEWAY_MONTHLY_COST=32  # AWS NAT Gateway: ~$0.045/hr × 730 hrs
readonly EKS_CLUSTER_MONTHLY_COST=73  # AWS EKS cluster: $0.10/hr × 730 hrs
readonly INSTANCE_MONTHLY_COST_ESTIMATE=1  # Rough average for cost estimation

check_prerequisites() {
    command -v aws >/dev/null || { log_error "AWS CLI not installed"; exit 1; }
    command -v jq >/dev/null || { log_error "jq not installed"; exit 1; }
}

get_resource_counts() {
    local ng_count lb_count nat_count eip_count instance_count

    ng_count=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'length(nodegroups)' --output text 2>/dev/null || echo "0")
    lb_count=$(aws elbv2 describe-load-balancers --region "$REGION" --query 'length(LoadBalancers)' --output text 2>/dev/null || echo "0")
    nat_count=$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=state,Values=available" --query 'length(NatGateways)' --output text 2>/dev/null || echo "0")
    eip_count=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --filters \
            "Name=tag:Cluster,Values=$CLUSTER_NAME" \
            "Name=tag:ManagedBy,Values=Terraform" \
        --query 'length(Addresses)' \
        --output text 2>/dev/null || echo "0")
    instance_count=$(aws ec2 describe-instances --region "$REGION" --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" "Name=tag:Cluster,Values=$CLUSTER_NAME" --query 'length(Reservations[].Instances[])' --output text 2>/dev/null || echo "0")

    echo "$ng_count|$lb_count|$nat_count|$eip_count|$instance_count"
}

show_summary() {
    local counts
    counts=$(get_resource_counts)
    IFS='|' read -r ng_count lb_count nat_count eip_count instance_count <<< "$counts"

    echo ""
    log_warn "=========================================="
    log_warn "EMERGENCY CLEANUP - ALL RESOURCES"
    log_warn "=========================================="
    echo ""
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $REGION"
    echo ""
    echo "Resources to delete:"
    echo "  • Node Groups: $ng_count (ALL - failed and successful)"
    echo "  • EC2 Instances: $instance_count"
    echo "  • NAT Gateways: $nat_count (~$$NAT_GATEWAY_MONTHLY_COST/month each)"
    echo "  • Elastic IPs: $eip_count"
    echo "  • Load Balancers: $lb_count"
    echo "  • EKS Cluster: 1 (~$$EKS_CLUSTER_MONTHLY_COST/month)"
    echo ""

    local monthly_cost=$((nat_count * NAT_GATEWAY_MONTHLY_COST + EKS_CLUSTER_MONTHLY_COST + instance_count * INSTANCE_MONTHLY_COST_ESTIMATE))
    log_warn "Estimated monthly cost: ~$monthly_cost"
    echo ""
}

delete_all_nodegroups() {
    log_info "Step 1: Deleting ALL node groups..."

    local nodegroups
    nodegroups=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'nodegroups[]' --output text 2>/dev/null || echo "")

    if [[ -z "$nodegroups" ]]; then
        log_info "  No node groups found"
        return 0
    fi

    for ng in $nodegroups;
    do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "  [DRY RUN] Would delete: $ng"
        else
            log_info "  Deleting: $ng"
            aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$REGION" 2>/dev/null || log_warn "    Failed to delete $ng"
        fi
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "  Waiting for deletions..."
        for ng in $nodegroups;
        do
            aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$REGION" 2>/dev/null || true
        done
    fi
}

delete_cluster() {
    log_info "Step 2: Deleting EKS cluster..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "  [DRY RUN] Would delete cluster: $CLUSTER_NAME"
    else
        aws eks delete-cluster --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || log_warn "  Failed to delete cluster"
        log_info "  Waiting for cluster deletion..."
        aws eks wait cluster-deleted --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || true
    fi
}

delete_nat_gateways() {
    log_info "Step 3: Deleting NAT Gateways..."

    local nat_gws
    nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=state,Values=available" --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "")

    if [[ -z "$nat_gws" ]]; then
        log_info "  No NAT Gateways found"
        return 0
    fi

    for nat in $nat_gws;
    do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "  [DRY RUN] Would delete: $nat"
        else
            log_info "  Deleting: $nat"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION" 2>/dev/null || log_warn "    Failed"
        fi
    done

    if [[ "$DRY_RUN" != "true" && -n "$nat_gws" ]]; then
        log_info "  Waiting for NAT Gateway deletion..."
        sleep 60
    fi
}

delete_elastic_ips() {
    log_info "Step 4: Releasing Elastic IPs..."

    local eips
    eips=$(aws ec2 describe-addresses \
        --region "$REGION" \
        --filters \
            "Name=tag:Cluster,Values=$CLUSTER_NAME" \
            "Name=tag:ManagedBy,Values=Terraform" \
        --query 'Addresses[].AllocationId' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$eips" ]]; then
        log_info "  No Elastic IPs found"
        return 0
    fi

    for eip in $eips;
    do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "  [DRY RUN] Would release: $eip"
        else
            log_info "  Releasing: $eip"
            aws ec2 release-address --allocation-id "$eip" --region "$REGION" 2>/dev/null || log_warn "    Failed"
        fi
    done
}

delete_load_balancers() {
    log_info "Step 5: Deleting Load Balancers..."

    local lbs
    lbs=$(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null || echo "")

    if [[ -z "$lbs" ]]; then
        log_info "  No Load Balancers found"
        return 0
    fi

    for lb in $lbs;
    do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "  [DRY RUN] Would delete: $lb"
        else
            log_info "  Deleting: $lb"
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb" --region "$REGION" 2>/dev/null || log_warn "    Failed"
        fi
    done
}

main() {
    echo ""
    log_warn "⚠️  EMERGENCY CLEANUP - DESTROYS ALL RESOURCES ⚠️"
    echo ""

    check_prerequisites
    show_summary

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        echo ""
    else
        log_error "THIS WILL DELETE EVERYTHING - CANNOT BE UNDONE"
        local expected_confirm="yes-delete-all-resources"
        read -r -p "Type $expected_confirm to confirm: " confirm

        if [[ "$confirm" != "$expected_confirm" ]]; then
            log_info "Aborted"
            exit 0
        fi
    fi

    echo ""
    delete_all_nodegroups
    delete_cluster
    delete_nat_gateways
    delete_elastic_ips
    delete_load_balancers

    echo ""
    log_info "✅ Emergency cleanup complete"
    log_warn "Run 'terraform destroy' to clean up remaining VPC resources"
    echo ""
}

main "$@"
