#!/bin/bash
# =============================================================================
# Resource Tagging Validation Script
# =============================================================================
#
# PURPOSE:
#   Validates that all AWS resources have required tags for safe cleanup
#   Ensures cluster-specific filtering works correctly
#   Prevents accidental deletion of unrelated resources
#
# USAGE:
#   CLUSTER_NAME=ml-platform-dev ./validate-resource-tags.sh
#
# REQUIRED ENVIRONMENT VARIABLES:
#   CLUSTER_NAME - Name of the cluster (used in tag values)
#   AWS_REGION   - AWS region (default: us-west-2)
#
# EXIT CODES:
#   0 - All resources properly tagged
#   1 - Tagging validation failed
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

CLUSTER_NAME="${CLUSTER_NAME:-ml-platform-dev}"
REGION="${AWS_REGION:-us-west-2}"

echo "Validating resource tags for cluster: $CLUSTER_NAME (region: $REGION)"
echo ""

# Check AWS CLI is available
if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not installed"
    exit 1
fi

log_info "AWS CLI is available"

# Function to check if resource has required tags
check_resource_tags() {
    local resource_type=$1
    local resource_id=$2

    # Get tags from resource
    TAGS=$(aws ec2 describe-tags \
        --region "$REGION" \
        --filters "Name=resource-id,Values=$resource_id" \
        --query 'Tags' \
        --output json 2>/dev/null || echo "[]")

    # Check for required tags
    HAS_CLUSTER_TAG=$(echo "$TAGS" | jq --arg CLUSTER "$CLUSTER_NAME" '.[] | select(.Key=="Cluster" and .Value==$CLUSTER)' | jq -s 'length > 0')
    HAS_MANAGED_BY_TAG=$(echo "$TAGS" | jq '.[] | select(.Key=="ManagedBy" and .Value=="Terraform")' | jq -s 'length > 0')

    if [ "$HAS_CLUSTER_TAG" = "true" ] && [ "$HAS_MANAGED_BY_TAG" = "true" ]; then
        return 0  # All required tags present
    fi

    log_warn "$resource_type $resource_id missing required tags (Cluster=$CLUSTER_NAME, ManagedBy=Terraform)"
    return 1
}

# Check 1: EKS Cluster Tags
echo "Checking EKS cluster tags..."
CLUSTER_TAGS=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query 'cluster.tags' \
    --output json 2>/dev/null || echo "{}")

if echo "$CLUSTER_TAGS" | jq -e ".[\"Cluster\"] == \"$CLUSTER_NAME\"" &>/dev/null; then
    log_info "EKS cluster has Cluster tag"
else
    log_warn "EKS cluster missing Cluster tag (but may still be manageable)"
fi

if echo "$CLUSTER_TAGS" | jq -e ".[\"ManagedBy\"] == \"Terraform\"" &>/dev/null; then
    log_info "EKS cluster has ManagedBy tag"
else
    log_warn "EKS cluster missing ManagedBy tag"
fi

echo ""

# Check 2: NAT Gateway Tags
echo "Checking NAT Gateway tags..."
NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
    --region "$REGION" \
    --filter "Name=state,Values=available" \
    --query 'NatGateways[].NatGatewayId' \
    --output text)

if [ -z "$NAT_GATEWAYS" ]; then
    log_info "No NAT Gateways found (none to validate)"
else
    TAGGED_NATS=0
    TOTAL_NATS=$(echo "$NAT_GATEWAYS" | wc -w)

    for nat_id in $NAT_GATEWAYS; do
        if check_resource_tags "nat-gateway" "$nat_id"; then
            TAGGED_NATS=$((TAGGED_NATS + 1))
        fi
    done

    if [ "$TAGGED_NATS" -eq "$TOTAL_NATS" ]; then
        log_info "All $TOTAL_NATS NAT Gateways properly tagged"
    else
        log_warn "$TAGGED_NATS/$TOTAL_NATS NAT Gateways properly tagged"
    fi
fi

echo ""

# Check 3: VPC Endpoint Tags
echo "Checking VPC Endpoint tags..."
VPC_ENDPOINTS_JSON=$(aws ec2 describe-vpc-endpoints \
    --region "$REGION" \
    --query 'VpcEndpoints[]' \
    --output json 2>/dev/null || echo "[]")

TOTAL_VPCES=$(echo "$VPC_ENDPOINTS_JSON" | jq 'length')

if [ "$TOTAL_VPCES" -eq 0 ]; then
    log_info "No VPC Endpoints found (none to validate)"
else
    TAGGED_VPCES=$(echo "$VPC_ENDPOINTS_JSON" | jq --arg CLUSTER "$CLUSTER_NAME" '[.[] | select(.Tags[]? | select(.Key=="Cluster" and .Value==$CLUSTER))] | length')

    if [ "$TAGGED_VPCES" -eq "$TOTAL_VPCES" ]; then
        log_info "All $TOTAL_VPCES VPC Endpoints properly tagged"
    else
        log_warn "$TAGGED_VPCES/$TOTAL_VPCES VPC Endpoints properly tagged"
    fi
fi

echo ""

# Check 4: Elastic IP Tags
echo "Checking Elastic IP tags..."
EIPS=$(aws ec2 describe-addresses \
    --region "$REGION" \
    --query 'Addresses[].AllocationId' \
    --output text 2>/dev/null || echo "")

if [ -z "$EIPS" ]; then
    log_info "No Elastic IPs found (none to validate)"
else
    TAGGED_EIPS=0
    TOTAL_EIPS=$(echo "$EIPS" | wc -w)

    for eip_id in $EIPS; do
        if check_resource_tags "elastic-ip" "$eip_id"; then
            TAGGED_EIPS=$((TAGGED_EIPS + 1))
        fi
    done

    if [ "$TAGGED_EIPS" -eq "$TOTAL_EIPS" ]; then
        log_info "All $TOTAL_EIPS Elastic IPs properly tagged"
    else
        log_warn "$TAGGED_EIPS/$TOTAL_EIPS Elastic IPs properly tagged"
    fi
fi

echo ""

# Check 5: Security Group Tags (Cluster-specific)
echo "Checking Security Group tags..."
SECURITY_GROUPS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filter "Name=tag:Cluster,Values=$CLUSTER_NAME" \
    --query 'SecurityGroups[].GroupId' \
    --output text 2>/dev/null || echo "")

if [ -z "$SECURITY_GROUPS" ]; then
    log_info "No Security Groups with cluster tag found"
else
    SG_COUNT=$(echo "$SECURITY_GROUPS" | wc -w)
    log_info "Found $SG_COUNT Security Groups with cluster tag"
fi

echo ""
log_info "Resource tagging validation complete"
exit 0
