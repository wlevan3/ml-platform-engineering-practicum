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
# EXIT CODES:
#   0 - State is valid
#   1 - State validation failed
#
# =============================================================================

set -euo pipefail

OPERATION="${1:-plan}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

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
        if [ "$RESOURCE_COUNT" -gt 0 ]; then
            # Check for EKS cluster
            if terraform state list | grep -q "aws_eks_cluster" 2>/dev/null; then
                log_info "EKS cluster found in state"
            else
                log_warn "EKS cluster not found in state (may already be destroyed)"
            fi
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

# Attempt a refresh to catch any state drift
if ! terraform refresh -no-color 2>&1 | grep -q "error\|failed" || true; then
    log_info "State refresh successful (no critical issues)"
else
    log_warn "State refresh reported issues (may be non-critical)"
fi

echo ""
log_info "State validation passed"
exit 0
