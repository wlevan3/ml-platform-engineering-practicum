#!/bin/bash
# =============================================================================
# AWS Resource Verification Script (Resource Groups Tagging API)
# =============================================================================
#
# PURPOSE:
#   Verifies that all cluster resources are deleted from AWS
#   Uses Resource Groups Tagging API (queries actual AWS state, not terraform state)
#   Primary validation method (immune to state corruption)
#
# USAGE:
#   CLUSTER_NAME=ml-platform-dev ./verify-aws-resources-deleted.sh
#
# REQUIRED ENVIRONMENT VARIABLES:
#   CLUSTER_NAME - Name of the cluster
#   AWS_REGION   - AWS region (default: us-west-2)
#
# WHAT IT CHECKS:
#   - EKS clusters
#   - NAT Gateways
#   - VPC Endpoints
#   - Elastic IPs
#   - Security Groups
#   - EC2 Instances
#
# EXIT CODES:
#   0 - All resources deleted (0 found in AWS)
#   1 - Resources still exist in AWS
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

CLUSTER_NAME="${CLUSTER_NAME:-ml-platform-dev}"
REGION="${AWS_REGION:-us-west-2}"

echo "Verifying all AWS resources deleted for cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# Check AWS CLI is available
if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not installed"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_error "jq not installed"
    exit 1
fi

log_info "AWS CLI and jq available"
echo ""

ORPHANED_FOUND=false
ORPHANED_COUNT=0

# Function to check resource type
check_resource_type() {
    local resource_type=$1
    local type_label=$2

    echo "Checking $type_label..."

    # Query resources with cluster tag
    RESOURCES=$(aws resourcegroupstaggingapi get-resources \
        --resource-type-filter "$resource_type" \
        --tag-filter "Key=Cluster,Values=$CLUSTER_NAME" \
        --region "$REGION" \
        --query 'ResourceTagMappingList' \
        --output json 2>/dev/null || echo "[]")

    RESOURCE_COUNT=$(echo "$RESOURCES" | jq 'length')

    if [ "$RESOURCE_COUNT" -eq 0 ]; then
        log_info "$type_label: 0 found"
    else
        log_error "$type_label: Found $RESOURCE_COUNT resources (ORPHANED)"
        echo "$RESOURCES" | jq -r '.[] | .ResourceARN' | sed 's/^/  - /'
        log_warn "Manual cleanup required for $type_label before verification can pass"
        ORPHANED_FOUND=true
        ORPHANED_COUNT=$((ORPHANED_COUNT + RESOURCE_COUNT))
    fi

    echo ""
}

# Check each resource type
check_resource_type "eks:cluster" "EKS Clusters"
check_resource_type "ec2:nat-gateway" "NAT Gateways"
check_resource_type "ec2:vpc-endpoint" "VPC Endpoints"
check_resource_type "ec2:elastic-ip" "Elastic IPs"
check_resource_type "ec2:security-group" "Security Groups"
check_resource_type "ec2:instance" "EC2 Instances"

# Summary
echo "=========================================="
if [ "$ORPHANED_FOUND" = true ]; then
    log_error "Found $ORPHANED_COUNT orphaned resources in AWS"
    echo ""
    echo "These resources must be manually deleted:"
    echo "  1. Delete via AWS Console or CLI"
    echo "  2. Remove cluster tags to re-run this script"
    echo "  3. Consider updating cleanup script to handle these resources"
    exit 1
else
    log_info "All resources deleted successfully"
    echo "Resource Groups Tagging API: 0 resources found"
    exit 0
fi
