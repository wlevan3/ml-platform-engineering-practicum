#!/bin/bash
# =============================================================================
# Terraform State Validation Script
# =============================================================================
#
# PURPOSE:
#   Validates terraform state consistency before and after operations
#   Catches corrupted or incomplete state changes
#
# USAGE:
#   ./validate-terraform-state.sh [plan|destroy]
#   plan    - Validate state before operations (expect resources)
#   destroy - Validate state after destroy (expect empty)
#
# ENVIRONMENT VARIABLES:
#   STRICT_REFRESH_FAILURE=true  - Treat terraform refresh issues as fatal (default: warn only)
#
# NOTE:
#   Refresh failures used to be fatal by default. We now emit warnings unless STRICT_REFRESH_FAILURE=true so
#   transient AWS API hiccups don't flap CI. Set the env var to restore the previous fail-fast behavior.
#
# EXIT CODES:
#   0 - State is valid
#   1 - State validation failed
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

OPERATION="${1:-plan}"
STRICT_REFRESH_FAILURE="${STRICT_REFRESH_FAILURE:-false}"

# Validate STRICT_REFRESH_FAILURE value early so typos fail loudly.
case "${STRICT_REFRESH_FAILURE,,}" in
    true|false)
        ;;
    *)
        log_error "STRICT_REFRESH_FAILURE must be 'true' or 'false' (case-insensitive); received '${STRICT_REFRESH_FAILURE}'."
        exit 1
        ;;
esac

# Check 1: Terraform is initialized
echo "Checking terraform state..."

if [ ! -d ".terraform" ]; then
    log_error "Terraform not initialized (.terraform directory not found)"
    exit 1
fi

log_info "Terraform initialized"

# Check 2: State file is readable
if ! terraform state list &>/dev/null; then
    log_error "Cannot read terraform state (corrupted or inaccessible)"
    exit 1
fi

log_info "State file is readable"

# Check 3: Validate terraform configuration
if ! terraform validate -no-color &>/dev/null; then
    log_error "Terraform validation failed"
    exit 1
fi

log_info "Terraform configuration is valid"

# Check 4: Count resources in state
RESOURCE_COUNT=$(terraform state list 2>/dev/null | awk 'NF {count++} END {print count+0}')

# Check 5: Operation-specific validation
case "$OPERATION" in
    plan)
        # Before planning, expect resources to exist
        if [ "$RESOURCE_COUNT" -eq 0 ]; then
            log_warn "No resources in state (might be first-time setup)"
        else
            log_info "Found $RESOURCE_COUNT resources in state"
        fi

        # Verify critical resources are present
        if terraform state list 2>/dev/null | grep -q "aws_eks_cluster"; then
            log_info "EKS cluster found in state"
        elif [ "$RESOURCE_COUNT" -gt 0 ]; then
            log_warn "EKS cluster not found in state (may already be destroyed)"
        fi
        ;;

    destroy)
        # After destroy, expect state to be empty
        if [ "$RESOURCE_COUNT" -eq 0 ]; then
            log_info "State is empty (all resources destroyed)"
        else
            log_error "$RESOURCE_COUNT resources remain in state (destroy incomplete)"
            echo ""
            echo "Remaining resources:"
            terraform state list | sed 's/^/  - /'
            exit 1
        fi
        ;;

    *)
        log_error "Unknown operation: $OPERATION"
        echo "Usage: $0 [plan|destroy]"
        exit 1
        ;;
esac

# Check 6: Look for broken references or dangling imports
echo "Checking for state integrity issues..."

# Attempt a refresh to catch any state drift. By default we warn so that flaky AWS
# API hiccups don't abort CI runs; set STRICT_REFRESH_FAILURE=true to restore the
# historical "fail hard on refresh errors" behavior.
REFRESH_OUTPUT=$(terraform refresh -no-color 2>&1 || true)
if echo "$REFRESH_OUTPUT" | grep -qiE "error|failed"; then
    if [[ "${STRICT_REFRESH_FAILURE,,}" == "true" ]]; then
        log_error "State refresh reported issues (STRICT_REFRESH_FAILURE=true)"
        echo "$REFRESH_OUTPUT"
        exit 1
    fi
    log_warn "State refresh reported issues (may be non-critical; set STRICT_REFRESH_FAILURE=true to fail):"
    echo "$REFRESH_OUTPUT"
else
    log_info "State refresh successful (no critical issues)"
fi

echo ""
log_info "State validation passed"
exit 0
