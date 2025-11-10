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

# Check 7: Run pre-flight conflict detection if in plan mode
if [ "$OPERATION" = "plan" ]; then
    echo ""
    log_info "Running pre-flight conflict detection..."

    # Get script directory relative to this script for correct path resolution
    SCRIPT_DIR="$(dirname "$0")"
    # If we're in infra/aws-core/terraform/environments/dev, we need to go up a few levels
    if [[ "$SCRIPT_DIR" == *"infra/aws-core/terraform/environments"* ]]; then
        CONFLICT_SCRIPT_PATH="../../../scripts/pre-flight-name-check.sh"
    else
        # If we're in the scripts directory, use relative path
        CONFLICT_SCRIPT_PATH="./pre-flight-name-check.sh"
    fi

    # Create a temporary plan to check for conflicts
    TEMP_PLAN=$(mktemp)
    # Capture the exit code from terraform plan
    if terraform plan -detailed-exitcode -out="$TEMP_PLAN" 2>/dev/null; then
        # Exit code 0 means no changes, but plan succeeded - run conflict check
        # Run the conflict detection script on the plan
        if "$CONFLICT_SCRIPT_PATH" "$TEMP_PLAN"; then
            log_info "Pre-flight conflict detection passed"
        else
            log_error "Pre-flight conflict detection failed"
            rm -f "$TEMP_PLAN" 2>/dev/null
            exit 1
        fi
    else
        # Capture the actual exit code from terraform plan
        TF_EXIT_CODE=$?
        # Terraform exit codes:
        # 0 - Succeeded with no changes
        # 1 - General error
        # 2 - Succeeded with changes (this is OK for our purposes)
        if [ $TF_EXIT_CODE -eq 2 ]; then  # Terraform exit code 2 indicates changes exist
            if "$CONFLICT_SCRIPT_PATH" "$TEMP_PLAN"; then
                log_info "Pre-flight conflict detection passed"
            else
                log_error "Pre-flight conflict detection failed"
                rm -f "$TEMP_PLAN" 2>/dev/null
                exit 1
            fi
        else
            log_warn "Could not generate plan for conflict detection (terraform exit code: $TF_EXIT_CODE)"
            rm -f "$TEMP_PLAN" 2>/dev/null
        fi
    fi
    rm -f "$TEMP_PLAN" 2>/dev/null
fi

# Check 7: Run pre-flight conflict detection if in plan mode
if [ "$OPERATION" = "plan" ]; then
    echo ""
    log_info "Running pre-flight conflict detection..."

    # Create a temporary plan to check for conflicts
    TEMP_PLAN=$(mktemp)
    if terraform plan -detailed-exitcode -out="$TEMP_PLAN" 2>/dev/null; then
        # Run the conflict detection script on the plan
        if ./scripts/check-resource-conflicts.sh "$TEMP_PLAN"; then
            log_info "Pre-flight conflict detection passed"
        else
            log_error "Pre-flight conflict detection failed"
            rm -f "$TEMP_PLAN"
            exit 1
        fi
    else
        # If terraform plan shows changes, that's OK - we'll still run the conflict check
        if [ $? -eq 2 ]; then  # Terraform exit code 2 indicates changes exist
            if ./scripts/check-resource-conflicts.sh "$TEMP_PLAN"; then
                log_info "Pre-flight conflict detection passed"
            else
                log_error "Pre-flight conflict detection failed"
                rm -f "$TEMP_PLAN"
                exit 1
            fi
        else
            log_warn "Could not generate plan for conflict detection"
        fi
    fi
    rm -f "$TEMP_PLAN"
fi

echo ""
log_info "State validation passed"
exit 0
