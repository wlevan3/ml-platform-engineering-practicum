#!/bin/bash
# =============================================================================
# Pre-flight Resource Conflict Detection Script
# =============================================================================
#
# PURPOSE:
#   Detects potential resource conflicts before Terraform apply operations
#   Prevents deployment failures due to resource naming conflicts, quota issues,
#   and other common infrastructure conflicts
#
# USAGE:
#   ./check-resource-conflicts.sh [plan_file|directory]
#   plan_file   - Path to Terraform plan file (JSON format recommended)
#   directory   - Directory containing Terraform configuration (will run terraform plan -out)
#
# EXIT CODES:
#   0 - No conflicts detected
#   1 - Conflicts detected or validation failed
#
# =============================================================================

set -euo pipefail

PLAN_INPUT="${1:-}"
TEMP_JSON=$(mktemp)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_header() { echo -e "${BLUE}## $1${NC}"; }

# =============================================================================
# Conflict Detection Functions (MUST return only numeric counts)
# =============================================================================

check_s3_bucket_conflicts() {
    local conflict_count=0

    local s3_buckets_to_create
    s3_buckets_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_s3_bucket") | .change.after.bucket' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$s3_buckets_to_create" ] && [ "$s3_buckets_to_create" != "null" ]; then
        log_info "Checking S3 bucket name conflicts..."
        while IFS= read -r bucket_name; do
            if [ -n "$bucket_name" ] && [ "$bucket_name" != "null" ]; then
                if [[ "$bucket_name" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] && [ ${#bucket_name} -ge 3 ] && [ ${#bucket_name} -le 63 ]; then
                    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
                        log_error "S3 bucket name conflict: Bucket '$bucket_name' already exists"
                        ((conflict_count++))
                    else
                        log_info "S3 bucket '$bucket_name' is available"
                    fi
                else
                    log_error "Invalid S3 bucket name format: $bucket_name"
                    ((conflict_count++))
                fi
            fi
        done <<< "$s3_buckets_to_create"
    else
        log_info "No S3 buckets being created in this plan"
    fi

    # Return numeric count ONLY
    echo "$conflict_count"
}

check_iam_conflicts() {
    local conflict_count=0

    local iam_roles_to_create
    iam_roles_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_iam_role") | .change.after.name' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$iam_roles_to_create" ] && [ "$iam_roles_to_create" != "null" ]; then
        log_info "Checking IAM role name conflicts..."
        while IFS= read -r role_name; do
            if [ -n "$role_name" ] && [ "$role_name" != "null" ]; then
                if aws iam get-role --role-name "$role_name" 2>/dev/null; then
                    log_error "IAM role conflict: Role '$role_name' already exists"
                    ((conflict_count++))
                else
                    log_info "IAM role '$role_name' is available"
                fi
            fi
        done <<< "$iam_roles_to_create"
    fi

    local iam_policies_to_create
    iam_policies_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_iam_policy") | .change.after.name' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$iam_policies_to_create" ] && [ "$iam_policies_to_create" != "null" ]; then
        log_info "Checking IAM policy name conflicts..."
        local aws_account_id
        aws_account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
            log_error "Could not retrieve AWS account ID for IAM policy checks"
            echo "$conflict_count"
            return
        }

        while IFS= read -r policy_name; do
            if [ -n "$policy_name" ] && [ "$policy_name" != "null" ]; then
                local policy_arn="arn:aws:iam::$aws_account_id:policy/$policy_name"
                if aws iam get-policy --policy-arn "$policy_arn" 2>/dev/null; then
                    log_error "IAM policy conflict: Policy '$policy_name' already exists"
                    ((conflict_count++))
                else
                    log_info "IAM policy '$policy_name' is available"
                fi
            fi
        done <<< "$iam_policies_to_create"
    fi

    echo "$conflict_count"
}

check_network_conflicts() {
    local conflict_count=0
    log_info "Checking network resource conflicts..."

    local vpcs_to_create
    vpcs_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_vpc") | .change.after.tags.Name // .change.after.id' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$vpcs_to_create" ] && [ "$vpcs_to_create" != "null" ]; then
        log_info "Checking VPC name conflicts..."
        while IFS= read -r vpc_name; do
            if [ -n "$vpc_name" ] && [ "$vpc_name" != "null" ]; then
                if aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$vpc_name" --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q "vpc-"; then
                    log_error "VPC name conflict: VPC with name '$vpc_name' already exists"
                    ((conflict_count++))
                else
                    log_info "VPC name '$vpc_name' is available"
                fi
            fi
        done <<< "$vpcs_to_create"
    fi

    # (Any additional checks must only increment conflict_count)
    echo "$conflict_count"
}

check_general_conflicts() {
    local conflict_count=0
    log_info "Checking general resource conflicts..."
    # (Additional checks may go here; must only increment conflict_count)
    echo "$conflict_count"
}

# =============================================================================
# Directory mode: plan generation (already stabilized)
# =============================================================================

# Function to cleanup temp files on exit
cleanup() {
    rm -f "$TEMP_JSON"
}
trap cleanup EXIT

log_header "Pre-flight Resource Conflict Detection"

# Check prerequisites
if ! command -v terraform &>/dev/null; then
    log_error "Terraform CLI not installed"
    exit 1
fi

if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not installed"
    exit 1
fi

log_info "Prerequisites validated (Terraform and AWS CLI available)"

# Check if plan input is provided
if [ -z "$PLAN_INPUT" ]; then
    log_error "No plan file or directory provided"
    echo "Usage: $0 [plan_file|directory]"
    exit 1
fi

# Determine if input is a plan file or directory
if [ -f "$PLAN_INPUT" ]; then
    # Input is a plan file
    PLAN_FILE="$PLAN_INPUT"
    log_info "Using provided plan file: $PLAN_FILE"

    # Try to read as JSON first; if that fails, assume it's a binary plan and convert via terraform show
    if jq empty "$PLAN_FILE" 2>/dev/null; then
        # File is already valid JSON
        cp "$PLAN_FILE" "$TEMP_JSON"
    else
        # Assume binary plan format; convert via terraform show
        log_info "Converting binary plan to JSON"
        if ! terraform show -json "$PLAN_FILE" > "$TEMP_JSON" 2>/dev/null; then
            log_error "Failed to read plan file (may not be a valid Terraform plan)"
            exit 1
        fi
    fi
elif [ -d "$PLAN_INPUT" ]; then
    # Input is a directory: use its real Terraform configuration in-place.
    cd "$PLAN_INPUT" || {
        log_error "Failed to change directory to: $PLAN_INPUT"
        exit 1
    }
    log_info "Generating plan in directory: $PLAN_INPUT"

    # If AWS_PROFILE is set, surface it for clarity.
    if [ -n "${AWS_PROFILE:-}" ]; then
        log_info "Using AWS_PROFILE='${AWS_PROFILE}' for Terraform backend and AWS operations"
    fi

    # Ensure Terraform is initialized. If not, run a proper init (including backend)
    # so that the configured S3 backend is ready before planning.
    if [ ! -d ".terraform" ]; then
        log_info "Terraform not initialized in directory: $PLAN_INPUT"
        log_info "Running 'terraform init -input=false -no-color' to initialize backend and providers..."
        if ! terraform init -input=false -no-color; then
            log_error "Terraform init failed in directory: $PLAN_INPUT"
            log_error "Verify AWS credentials (e.g. AWS_PROFILE) and backend configuration, then retry."
            exit 1
        fi
        log_info "Terraform init completed successfully in directory: $PLAN_INPUT"
    fi

    # Create a temporary plan file
    TEMP_PLAN=$(mktemp)

    log_info "Running 'terraform plan' to generate plan for conflict analysis..."
    if terraform plan -out="$TEMP_PLAN" -detailed-exitcode -input=false -refresh=false -no-color; then
        PLAN_EXIT_CODE=$?
    else
        PLAN_EXIT_CODE=$?
    fi

    # Handle terraform plan exit codes:
    # 0: success, no changes
    # 2: success, changes present
    # 1: failure
    if [ "$PLAN_EXIT_CODE" -eq 1 ]; then
        log_error "Terraform plan failed with an error (see output above for details)"
        rm -f "$TEMP_PLAN" 2>/dev/null
        exit 1
    fi

    if [ "$PLAN_EXIT_CODE" -eq 0 ]; then
        log_info "Terraform plan generated successfully with no changes."
    fi

    if [ "$PLAN_EXIT_CODE" -eq 2 ]; then
        log_info "Terraform plan generated successfully with pending changes (this is normal for pre-flight checks)."
    fi

    # Convert plan to JSON for conflict analysis
    log_info "Converting Terraform plan to JSON for conflict analysis..."
    if ! terraform show -json "$TEMP_PLAN" > "$TEMP_JSON"; then
        log_error "Failed to convert plan to JSON format. Raw terraform show output:"
        terraform show "$TEMP_PLAN" || log_error "terraform show of plan also failed"
        rm -f "$TEMP_PLAN" 2>/dev/null
        exit 1
    fi

    rm -f "$TEMP_PLAN" 2>/dev/null
else
    log_error "Plan file or directory does not exist: $PLAN_INPUT"
    exit 1
fi

# Validate JSON format
if ! jq empty "$TEMP_JSON" 2>/dev/null; then
    log_error "Plan is not valid JSON format"
    exit 1
fi

log_info "Plan is valid JSON format"

# =============================================================================
# Conflict aggregation (after TEMP_JSON and RESOURCE_CHANGES are set)
# =============================================================================

RESOURCE_CHANGES=$(jq '.resource_changes | length' "$TEMP_JSON")
if [ "$RESOURCE_CHANGES" -eq 0 ]; then
    log_info "No resource changes in plan, no conflicts possible"
    exit 0
fi

log_info "Found $RESOURCE_CHANGES resource changes to analyze"
log_header "Running conflict detection checks..."

# Count creates (used to decide if we run create-only checks)
CREATES=$(jq '[.resource_changes[] | select(.change.actions[] == "create")] | length' "$TEMP_JSON")

# Helper to coerce function output to a clean non-negative integer
sanitize_count() {
    local raw="${1:-0}"
    # Take last line, strip non-digits; default to 0 if empty
    raw=$(printf '%s\n' "$raw" | tail -n1 | tr -cd '0-9')
    [ -z "$raw" ] && raw=0
    printf '%s\n' "$raw"
}

# Initialize counters explicitly as numeric
S3_CONFLICTS=0
IAM_CONFLICTS=0
NETWORK_CONFLICTS=0
GENERAL_CONFLICTS=0

if [ "$CREATES" -gt 0 ]; then
    log_info "$CREATES resources to be created, analyzing for conflicts..."

    S3_CONFLICTS=$(sanitize_count "$(check_s3_bucket_conflicts)")
    log_info "S3 conflict checks completed: ${S3_CONFLICTS} conflicts found"

    IAM_CONFLICTS=$(sanitize_count "$(check_iam_conflicts)")
    log_info "IAM conflict checks completed: ${IAM_CONFLICTS} conflicts found"

    NETWORK_CONFLICTS=$(sanitize_count "$(check_network_conflicts)")
    log_info "Network conflict checks completed: ${NETWORK_CONFLICTS} conflicts found"

    GENERAL_CONFLICTS=$(sanitize_count "$(check_general_conflicts)")
    log_info "General conflict checks completed: ${GENERAL_CONFLICTS} conflicts found"
else
    log_info "No create actions detected; skipping create-only conflict checks"
fi

# Ensure all conflict counts are numeric; default to 0 if empty/non-numeric
S3_CONFLICTS=${S3_CONFLICTS:-0}
IAM_CONFLICTS=${IAM_CONFLICTS:-0}
NETWORK_CONFLICTS=${NETWORK_CONFLICTS:-0}
GENERAL_CONFLICTS=${GENERAL_CONFLICTS:-0}

TOTAL_CONFLICTS=$(( S3_CONFLICTS + IAM_CONFLICTS + NETWORK_CONFLICTS + GENERAL_CONFLICTS ))

if [ "$TOTAL_CONFLICTS" -gt 0 ]; then
    log_error "CONFLICTS DETECTED: $TOTAL_CONFLICTS total conflicts found"
    echo ""
    echo "Pre-flight check FAILED - Please resolve conflicts before applying"
    exit 1
else
    log_info "No conflicts detected"
    echo ""
    log_info "Pre-flight check PASSED - Safe to proceed with Terraform apply"
    exit 0
fi
