#!/usr/bin/env bash
# =============================================================================
# Cleanup Failed EKS Node Groups
# =============================================================================
#
# PURPOSE:
#   Delete all failed EKS node groups and their associated resources
#   (Auto Scaling Groups, EC2 instances, Launch Templates)
#
# WHEN TO USE:
#   - After multiple failed terraform apply attempts
#   - To stop ongoing costs from orphaned node groups
#   - Before applying infrastructure fixes
#
# WHAT IT DOES:
#   1. Lists all node groups in the cluster
#   2. Filters for CREATE_FAILED status
#   3. Initiates deletion for all failed node groups in parallel
#   4. Waits for all deletions to complete (cascades to ASG/instances)
#
# RESOURCES CLEANED UP:
#   - EKS Node Groups (CREATE_FAILED)
#   - Auto Scaling Groups
#   - EC2 Instances (running or stopped)
#   - Launch Templates (if orphaned)
#
# SAFETY:
#   - Only deletes CREATE_FAILED node groups
#   - Prompts for confirmation
#   - Shows resources before deletion
#
# =============================================================================

set -euo pipefail

# Configuration
CLUSTER_NAME="ml-platform-dev"
REGION="us-west-2"
DRY_RUN="${DRY_RUN:-false}"

# Logging configuration
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/cleanup-nodegroups-$(date +%Y%m%d-%H%M%S).log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if AWS CLI is installed
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed (required for JSON parsing)"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Get all node groups in the cluster
get_all_node_groups() {
    log_info "Fetching node groups for cluster: $CLUSTER_NAME"

    local nodegroups
    nodegroups=$(aws eks list-nodegroups \
        --cluster-name "$CLUSTER_NAME" \
        --region "$REGION" \
        --output json \
        --query 'nodegroups[]' 2>/dev/null || echo "[]")

    echo "$nodegroups" | jq -r '.[]'
}

# Get node group status
get_node_group_status() {
    local nodegroup=$1

    aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$nodegroup" \
        --region "$REGION" \
        --query 'nodegroup.status' \
        --output text 2>/dev/null || echo "UNKNOWN"
}

# Get instances for a node group
get_node_group_instances() {
    local nodegroup=$1

    aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$nodegroup" \
        --region "$REGION" \
        --query 'nodegroup.resources.autoScalingGroups[0].name' \
        --output text 2>/dev/null | \
    xargs -I {} aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names {} \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo ""
}

# Display summary of resources to be deleted
show_summary() {
    local failed_nodegroups=("$@")

    echo ""
    log_warning "=========================================="
    log_warning "CLEANUP SUMMARY"
    log_warning "=========================================="
    echo ""
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $REGION"
    log_info "Failed node groups to delete: ${#failed_nodegroups[@]}"
    echo ""

    local total_instances=0

    for nodegroup in "${failed_nodegroups[@]}"; do
        local instances
        instances=$(get_node_group_instances "$nodegroup")
        local instance_count=0

        if [[ -n "$instances" ]]; then
            instance_count=$(echo "$instances" | wc -w | tr -d ' ')
        fi

        total_instances=$((total_instances + instance_count))

        echo -e "${YELLOW}Node Group:${NC} $nodegroup"
        echo "  Status: CREATE_FAILED"
        echo "  Instances: $instance_count"
        if [[ $instance_count -gt 0 ]]; then
            echo "  Instance IDs: $instances"
        fi
        echo ""
    done

    log_warning "Total EC2 instances to terminate: $total_instances"

    # Calculate cost savings
    local hourly_rate=0.0084
    local daily_savings=$(echo "$total_instances * $hourly_rate * 24" | bc -l)
    local monthly_savings=$(echo "$daily_savings * 30" | bc -l)

    printf "${GREEN}Cost savings:${NC} \$%.2f/day (\$%.2f/month)\n" "$daily_savings" "$monthly_savings"
    echo ""
}

# Delete a single node group
delete_node_group() {
    local nodegroup=$1

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete node group: $nodegroup"
        return 0
    fi

    log_info "Deleting node group: $nodegroup"

    if aws eks delete-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$nodegroup" \
        --region "$REGION" \
        --no-cli-pager >/dev/null 2>&1; then
        log_success "Delete initiated for: $nodegroup"
        return 0
    else
        log_error "Failed to delete: $nodegroup"
        return 1
    fi
}

# Wait for node group deletion to complete
wait_for_deletion() {
    local nodegroup=$1

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log_info "Waiting for deletion: $nodegroup"

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        local status
        status=$(get_node_group_status "$nodegroup")

        if [[ "$status" == "UNKNOWN" ]] || [[ "$status" == "" ]]; then
            log_success "Deleted: $nodegroup"
            return 0
        fi

        if [[ "$status" == "DELETE_FAILED" ]]; then
            log_error "Deletion failed: $nodegroup"
            return 1
        fi

        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done

    echo ""
    log_warning "Timeout waiting for deletion: $nodegroup"
    return 1
}

# Main cleanup function
cleanup_failed_nodegroups() {
    local all_nodegroups
    local failed_nodegroups=()

    # Get all node groups
    mapfile -t all_nodegroups < <(get_all_node_groups)

    if [[ ${#all_nodegroups[@]} -eq 0 ]]; then
        log_info "No node groups found in cluster: $CLUSTER_NAME"
        return 0
    fi

    log_info "Found ${#all_nodegroups[@]} node groups"

    # Filter for failed node groups
    for nodegroup in "${all_nodegroups[@]}"; do
        local status
        status=$(get_node_group_status "$nodegroup")

        if [[ "$status" == "CREATE_FAILED" ]]; then
            failed_nodegroups+=("$nodegroup")
        fi
    done

    if [[ ${#failed_nodegroups[@]} -eq 0 ]]; then
        log_success "No failed node groups found - nothing to clean up!"
        return 0
    fi

    # Show summary
    show_summary "${failed_nodegroups[@]}"

    # Confirm deletion
    if [[ "$DRY_RUN" != "true" ]]; then
        echo -e "${YELLOW}This will permanently delete the above resources.${NC}"
        read -p "Are you sure you want to proceed? (yes/no): " -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi

    # Delete node groups (parallel initiation for speed)
    local deleted=0
    local failed=0

    log_info "Initiating parallel deletion for ${#failed_nodegroups[@]} node groups..."
    echo ""

    # Step 1: Initiate all deletions in parallel (don't wait)
    for nodegroup in "${failed_nodegroups[@]}"; do
        if ! delete_node_group "$nodegroup"; then
            failed=$((failed + 1))
        fi
    done

    echo ""
    log_info "Waiting for all deletions to complete..."
    echo ""

    # Step 2: Wait for all deletions to finish
    for nodegroup in "${failed_nodegroups[@]}"; do
        if wait_for_deletion "$nodegroup"; then
            deleted=$((deleted + 1))
        else
            # Only increment failed if wait fails (not already counted in step 1)
            if ! [[ $failed -gt 0 ]]; then
                failed=$((failed + 1))
            fi
        fi
    done

    # Summary
    echo ""
    log_warning "=========================================="
    log_warning "CLEANUP COMPLETE"
    log_warning "=========================================="
    echo ""
    log_success "Successfully deleted: $deleted node groups"

    if [[ $failed -gt 0 ]]; then
        log_error "Failed to delete: $failed node groups"
        return 1
    fi

    return 0
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    log_info "EKS Node Group Cleanup Script"
    log_info "Log file: $LOG_FILE"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Run cleanup
    cleanup_failed_nodegroups

    echo ""
    log_success "Cleanup finished"
    log_info "Full log saved to: $LOG_FILE"
    echo ""
}

# Run main function
main "$@"
