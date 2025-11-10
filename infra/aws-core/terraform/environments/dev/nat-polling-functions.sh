#!/bin/bash
# =============================================================================
# NAT Gateway Deletion Polling Functions
# =============================================================================
#
# Purpose: Provide reusable polling functions with exponential backoff
#          to safely wait for NAT Gateway deletion and EIP unassociation
#
# Usage:
#   source ./nat-polling-functions.sh
#   wait_for_nat_gateway_deletion "nat-123456" "us-west-2" "600"
#   wait_for_eip_unassociated "eipalloc-123456" "us-west-2" "600"
#
# Replaces: hardcoded "sleep 60" with intelligent polling
# Fixes: Bug #2 - EIP "already associated" error during cleanup
#
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default logging function (can be overridden by caller)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# =============================================================================
# POLLING FUNCTIONS
# =============================================================================

# wait_for_nat_gateway_deletion
#
# Polls NAT Gateway state with exponential backoff until deletion completes
# or timeout is reached.
#
# Arguments:
#   $1: NAT Gateway ID (e.g., nat-0123456789abcdef0)
#   $2: AWS Region (e.g., us-west-2)
#   $3: Max wait time in seconds (default: 600 = 10 minutes)
#
# Returns:
#   0: NAT Gateway successfully deleted
#   1: Timeout or error
#
# Algorithm:
#   - Initial interval: 5 seconds
#   - Backoff multiplier: 1.5x per retry
#   - Max interval: 60 seconds
#   - Max total time: 600 seconds (10 minutes)
#
wait_for_nat_gateway_deletion() {
    local nat_gateway_id="${1:?NAT Gateway ID required}"
    local region="${2:-us-west-2}"
    local max_wait_seconds="${3:-600}"

    local start_time elapsed retry_count interval max_interval nat_state

    start_time=$(date +%s)
    retry_count=0
    interval=5
    max_interval=60

    log_info "Polling NAT Gateway deletion ($nat_gateway_id)..."
    log_info "  Max wait: ${max_wait_seconds}s (~$(( max_wait_seconds / 60 )) minutes)"
    log_info "  Backoff strategy: 5s initial, 1.5x multiplier, 60s max interval"
    echo ""

    while true; do
        # Query NAT Gateway state
        local query_result
        query_result=$(aws ec2 describe-nat-gateways \
            --nat-gateway-ids "$nat_gateway_id" \
            --region "$region" \
            --query 'NatGateways[0].State' \
            --output text 2>/dev/null || echo "")

        nat_state="${query_result:-unknown}"
        elapsed=$(($(date +%s) - start_time))
        retry_count=$((retry_count + 1))

        # State analysis
        case "$nat_state" in
            "")
                # Empty response = NAT Gateway fully deleted
                log_success "NAT Gateway deleted (verified at ${elapsed}s after ${retry_count} checks)"
                return 0
                ;;
            "deleted")
                # Official deleted state (AWS eventually returns this value)
                log_success "NAT Gateway marked as deleted (${elapsed}s, ${retry_count} checks)"
                return 0
                ;;
            "deleting")
                # Normal state during deletion
                log_info "  [${retry_count}] State: deleting | Elapsed: ${elapsed}s | Next check in ${interval}s"
                ;;
            "available")
                # Not yet deleted
                log_info "  [${retry_count}] State: available | Elapsed: ${elapsed}s | Next check in ${interval}s"
                ;;
            "pending")
                # Rare state: deletion initiated but not yet started
                log_info "  [${retry_count}] State: pending | Elapsed: ${elapsed}s | Next check in ${interval}s"
                ;;
            "failed")
                # Deletion failed
                log_error "NAT Gateway deletion FAILED (state: failed)"
                return 1
                ;;
            "unknown")
                # Query error (transient or credential issue)
                log_warn "  [${retry_count}] State: unknown (query error) | Elapsed: ${elapsed}s | Retrying..."
                ;;
            *)
                # Unknown state (log for debugging)
                log_warn "  [${retry_count}] State: $nat_state (unexpected) | Elapsed: ${elapsed}s"
                ;;
        esac

        # Timeout check
        if [[ $elapsed -ge $max_wait_seconds ]]; then
            log_error "TIMEOUT: NAT Gateway not deleted after ${max_wait_seconds}s"
            log_error "  Final state: $nat_state"
            log_error "  Total checks: $retry_count"
            log_error "  NAT Gateway ID: $nat_gateway_id"
            return 1
        fi

        # Wait before next check (exponential backoff)
        sleep "$interval"

        # Calculate next interval: multiply by 1.5, cap at max. Using integer math is intentional—sleep only accepts whole seconds.
        interval=$(( interval * 3 / 2 ))
        if (( interval > max_interval )); then
            interval=$max_interval
        fi
    done
}

# wait_for_eip_unassociated
#
# Polls Elastic IP association state with exponential backoff until
# EIP is no longer associated with a NAT Gateway.
#
# Arguments:
#   $1: Allocation ID (e.g., eipalloc-0123456789abcdef0)
#   $2: AWS Region (default: us-west-2)
#   $3: Max wait time in seconds (default: 600)
#
# Returns:
#   0: EIP successfully unassociated
#   1: Timeout or error
#
# Algorithm:
#   - Initial interval: 3 seconds (faster than NAT polling)
#   - Backoff multiplier: 1.5x per retry
#   - Max interval: 30 seconds
#   - Max total time: 600 seconds
#
wait_for_eip_unassociated() {
    local allocation_id="${1:?Allocation ID required}"
    local region="${2:-us-west-2}"
    local max_wait_seconds="${3:-600}"

    local start_time elapsed retry_count interval max_interval association_id

    start_time=$(date +%s)
    retry_count=0
    interval=3
    max_interval=30

    log_info "Polling EIP unassociation ($allocation_id)..."
    log_info "  Max wait: ${max_wait_seconds}s"
    log_info "  Backoff strategy: 3s initial, 1.5x multiplier, 30s max interval"
    echo ""

    while true; do
        # Query EIP association state
        local query_result
        query_result=$(aws ec2 describe-addresses \
            --allocation-ids "$allocation_id" \
            --region "$region" \
            --query 'Addresses[0].AssociationId' \
            --output text 2>/dev/null || echo "")

        association_id="${query_result:-unknown}"
        elapsed=$(($(date +%s) - start_time))
        retry_count=$((retry_count + 1))

        # Association analysis
        if [[ -z "$association_id" ]] || [[ "$association_id" == "None" ]]; then
            # Empty or None = EIP is unassociated
            log_success "EIP unassociated and ready to release (${elapsed}s, ${retry_count} checks)"
            return 0
        elif [[ "$association_id" == "unknown" ]]; then
            # Query error
            log_warn "  [${retry_count}] State: unknown (query error) | Elapsed: ${elapsed}s | Retrying..."
        else
            # Still associated
            log_info "  [${retry_count}] Associated: $association_id | Elapsed: ${elapsed}s | Next check in ${interval}s"
        fi

        # Timeout check
        if [[ $elapsed -ge $max_wait_seconds ]]; then
            log_error "TIMEOUT: EIP still associated after ${max_wait_seconds}s"
            log_error "  Association ID: $association_id"
            log_error "  Total checks: $retry_count"
            log_error "  Allocation ID: $allocation_id"
            return 1
        fi

        # Wait before next check
        sleep "$interval"

        # Calculate next interval
        interval=$(awk "BEGIN {print int(min($interval * 1.5, $max_interval))}")
    done
}

# wait_for_nat_gateway_and_eip_cleanup
#
# Complete end-to-end cleanup: delete NAT Gateway, poll deletion,
# then release the associated EIP.
#
# Arguments:
#   $1: NAT Gateway ID
#   $2: AWS Region (default: us-west-2)
#   $3: Max wait time in seconds (default: 600)
#
# Returns:
#   0: Cleanup successful
#   1: Cleanup failed at some step
#
cleanup_nat_gateway_and_eip() {
    local nat_gateway_id="${1:?NAT Gateway ID required}"
    local region="${2:-us-west-2}"
    local max_wait_seconds="${3:-600}"

    log_info "Starting NAT Gateway cleanup..."
    log_info "  NAT Gateway: $nat_gateway_id"
    log_info "  Region: $region"
    echo ""

    # Step 1: Retrieve associated EIP
    log_info "→ Step 1: Retrieving associated EIP..."
    local allocation_id
    allocation_id=$(aws ec2 describe-nat-gateways \
        --nat-gateway-ids "$nat_gateway_id" \
        --region "$region" \
        --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$allocation_id" ]] || [[ "$allocation_id" == "None" ]]; then
        log_error "No EIP found associated with NAT Gateway"
        return 1
    fi

    log_success "Found EIP: $allocation_id"
    echo ""

    # Step 2: Delete NAT Gateway
    log_info "→ Step 2: Deleting NAT Gateway..."
    if ! aws ec2 delete-nat-gateway \
        --nat-gateway-id "$nat_gateway_id" \
        --region "$region" >/dev/null 2>&1; then
        log_error "Failed to initiate NAT Gateway deletion"
        return 1
    fi

    log_success "Deletion initiated"
    echo ""

    # Step 3: Poll NAT Gateway deletion
    log_info "→ Step 3: Polling NAT Gateway deletion (exponential backoff)..."
    echo ""
    if ! wait_for_nat_gateway_deletion "$nat_gateway_id" "$region" "$max_wait_seconds"; then
        log_warn "NAT Gateway deletion polling timeout (proceeding anyway)"
    fi

    echo ""

    # Step 4: Poll EIP unassociation
    log_info "→ Step 4: Polling EIP unassociation..."
    echo ""
    if ! wait_for_eip_unassociated "$allocation_id" "$region" "$max_wait_seconds"; then
        log_warn "EIP still associated after timeout (proceeding anyway)"
    fi

    echo ""

    # Step 5: Release EIP
    log_info "→ Step 5: Releasing Elastic IP..."
    if ! aws ec2 release-address \
        --allocation-id "$allocation_id" \
        --region "$region" 2>/dev/null; then
        log_error "Failed to release EIP"
        return 1
    fi

    log_success "EIP released: $allocation_id"
    echo ""

    log_success "═════════════════════════════════════════════"
    log_success "NAT Gateway cleanup complete!"
    log_success "═════════════════════════════════════════════"
    return 0
}

# =============================================================================
# PARALLEL CLEANUP FOR MULTIPLE NAT GATEWAYS
# =============================================================================

# cleanup_all_nat_gateways
#
# Initiates cleanup for all NAT Gateways in a region, with parallel polling.
#
# Arguments:
#   $1: AWS Region (default: us-west-2)
#   $2: Max wait time in seconds (default: 600)
#
# Returns:
#   0: All cleanups completed
#   1: Some cleanups failed
#
cleanup_all_nat_gateways() {
    local region="${1:-us-west-2}"
    local max_wait_seconds="${2:-600}"

    log_info "Discovering NAT Gateways in region: $region..."

    local nat_gateways
    nat_gateways=$(aws ec2 describe-nat-gateways \
        --region "$region" \
        --filter "Name=state,Values=available" \
        --query 'NatGateways[].NatGatewayId' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$nat_gateways" ]]; then
        log_info "No NAT Gateways found"
        return 0
    fi

    log_info "Found NAT Gateways: $nat_gateways"
    echo ""

    local nat_array=()
    read -r -a nat_array <<<"$nat_gateways"
    local success_count=0
    local fail_count=0

    # Delete all NAT Gateways (initiate deletions)
    log_info "Initiating deletions for ${#nat_array[@]} NAT Gateway(s)..."
    for nat in "${nat_array[@]}"; do
        log_info "  Initiating: $nat"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$region" 2>/dev/null || true
    done

    echo ""

    # Poll all deletions (can be run in parallel with background jobs)
    log_info "Polling deletions with exponential backoff..."
    for nat in "${nat_array[@]}"; do
        if wait_for_nat_gateway_deletion "$nat" "$region" "$max_wait_seconds"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        echo ""
    done

    log_info "NAT Gateway cleanup results: $success_count succeeded, $fail_count failed"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi

    return 0
}

# =============================================================================
# EXPORT FUNCTIONS (for external use)
# =============================================================================

export -f wait_for_nat_gateway_deletion
export -f wait_for_eip_unassociated
export -f cleanup_nat_gateway_and_eip
export -f cleanup_all_nat_gateways
export -f log_info log_success log_warn log_error

# =============================================================================
# MAIN: Allow script to be called directly
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Script is being executed directly (not sourced)

    case "${1:-help}" in
        wait-nat)
            # wait-nat <nat-id> <region> [max-wait]
            wait_for_nat_gateway_deletion "${2:?NAT ID required}" "${3:-us-west-2}" "${4:-600}"
            ;;
        wait-eip)
            # wait-eip <allocation-id> <region> [max-wait]
            wait_for_eip_unassociated "${2:?Allocation ID required}" "${3:-us-west-2}" "${4:-600}"
            ;;
        cleanup-nat)
            # cleanup-nat <nat-id> <region> [max-wait]
            cleanup_nat_gateway_and_eip "${2:?NAT ID required}" "${3:-us-west-2}" "${4:-600}"
            ;;
        cleanup-all)
            # cleanup-all <region> [max-wait]
            cleanup_all_nat_gateways "${2:-us-west-2}" "${3:-600}"
            ;;
        *)
            echo "Usage: $0 {wait-nat|wait-eip|cleanup-nat|cleanup-all} [arguments]"
            echo ""
            echo "Commands:"
            echo "  wait-nat <nat-id> [region] [max-wait]"
            echo "    Poll NAT Gateway deletion"
            echo ""
            echo "  wait-eip <allocation-id> [region] [max-wait]"
            echo "    Poll EIP unassociation"
            echo ""
            echo "  cleanup-nat <nat-id> [region] [max-wait]"
            echo "    Full cleanup: delete NAT, poll deletion, release EIP"
            echo ""
            echo "  cleanup-all [region] [max-wait]"
            echo "    Cleanup all NAT Gateways in region"
            echo ""
            echo "Examples:"
            echo "  $0 wait-nat nat-0123456789abcdef0 us-west-2 600"
            echo "  $0 cleanup-nat nat-0123456789abcdef0 us-west-2"
            echo "  $0 cleanup-all us-west-2 600"
            exit 1
            ;;
    esac
fi
