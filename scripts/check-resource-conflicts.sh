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

    # Convert plan to JSON if it's a binary plan file
    if file "$PLAN_FILE" | grep -q "data\|binary"; then
        log_info "Converting binary plan to JSON"
        if ! terraform show -json "$PLAN_FILE" > "$TEMP_JSON" 2>/dev/null; then
            log_error "Failed to read plan file (may not be a valid Terraform plan)"
            exit 1
        fi
    else
        # Assume it's already JSON
        cp "$PLAN_FILE" "$TEMP_JSON"
    fi
elif [ -d "$PLAN_INPUT" ]; then
    # Input is a directory, run terraform plan to generate a plan file
    cd "$PLAN_INPUT"
    log_info "Generating plan in directory: $PLAN_INPUT"

    # Check if terraform is initialized
    if [ ! -d ".terraform" ]; then
        log_error "Terraform not initialized in directory: $PLAN_INPUT"
        exit 1
    fi

    # Create a temporary plan file
    TEMP_PLAN=$(mktemp)
    if ! terraform plan -out="$TEMP_PLAN" -detailed-exitcode 2>/dev/null; then
        # If plan has changes to apply, that's OK for our purposes
        log_info "Terraform plan generated with changes (this is normal)"
    fi

    # Convert plan to JSON
    if ! terraform show -json "$TEMP_PLAN" > "$TEMP_JSON" 2>/dev/null; then
        log_error "Failed to convert plan to JSON format"
        rm -f "$TEMP_PLAN"
        exit 1
    fi

    rm -f "$TEMP_PLAN"
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

# Extract resource changes from plan
RESOURCE_CHANGES=$(jq '.resource_changes | length' "$TEMP_JSON")
if [ "$RESOURCE_CHANGES" -eq 0 ]; then
    log_info "No resource changes in plan, no conflicts possible"
    exit 0
fi

log_info "Found $RESOURCE_CHANGES resource changes to analyze"

# Main conflict detection logic will be added here
log_header "Running conflict detection checks..."

# Count resources by action type
CREATES=$(jq '[.resource_changes[] | select(.change.actions[] == "create")] | length' "$TEMP_JSON")
UPDATES=$(jq '[.resource_changes[] | select(.change.actions[] == "update")] | length' "$TEMP_JSON")
DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete")] | length' "$TEMP_JSON")

log_info "$CREATES resources to be created, $UPDATES to be updated, $DELETES to be deleted"

# Call specific conflict detection functions
S3_CONFLICTS=0
IAM_CONFLICTS=0
NETWORK_CONFLICTS=0
GENERAL_CONFLICTS=0

# Run S3 bucket conflict checks (for newly created resources)
if [ "$CREATES" -gt 0 ]; then
    S3_CONFLICTS=$(check_s3_bucket_conflicts)
    log_info "S3 conflict checks completed: $S3_CONFLICTS conflicts found"

    IAM_CONFLICTS=$(check_iam_conflicts)
    log_info "IAM conflict checks completed: $IAM_CONFLICTS conflicts found"

    NETWORK_CONFLICTS=$(check_network_conflicts)
    log_info "Network conflict checks completed: $NETWORK_CONFLICTS conflicts found"

    GENERAL_CONFLICTS=$(check_general_conflicts)
    log_info "General conflict checks completed: $GENERAL_CONFLICTS conflicts found"
fi

TOTAL_CONFLICTS=$((S3_CONFLICTS + IAM_CONFLICTS + NETWORK_CONFLICTS + GENERAL_CONFLICTS))

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

# Function to check for S3 bucket name conflicts
# This function will look for aws_s3_bucket resources in the plan that are being created,
# and check if those bucket names already exist in AWS
check_s3_bucket_conflicts() {
    local conflict_count=0

    # Get S3 buckets being created
    local s3_buckets_to_create
    s3_buckets_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_s3_bucket") | .change.after.bucket' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$s3_buckets_to_create" ] && [ "$s3_buckets_to_create" != "null" ]; then
        log_info "Checking S3 bucket name conflicts..."

        while IFS= read -r bucket_name; do
            if [ -n "$bucket_name" ] && [ "$bucket_name" != "null" ]; then
                # Check if bucket name already exists (globally in AWS)
                if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
                    log_error "S3 bucket name conflict: Bucket '$bucket_name' already exists globally"
                    ((conflict_count++))
                else
                    log_info "S3 bucket '$bucket_name' is available"
                fi
            fi
        done <<< "$s3_buckets_to_create"
    else
        log_info "No S3 buckets being created in this plan"
    fi

    echo "$conflict_count"
}

# Function to check for IAM resource conflicts
check_iam_conflicts() {
    local conflict_count=0

    # Check IAM roles
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

    # Check IAM policies
    local iam_policies_to_create
    iam_policies_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_iam_policy") | .change.after.name' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$iam_policies_to_create" ] && [ "$iam_policies_to_create" != "null" ]; then
        log_info "Checking IAM policy name conflicts..."

        # Get AWS account ID once to avoid repeated calls
        local aws_account_id
        aws_account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
            log_error "Could not retrieve AWS account ID"
            return 1  # Return error, don't increment conflict count here
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

# Function to check for network resource conflicts
check_network_conflicts() {
    local conflict_count=0
    log_info "Checking network resource conflicts..."

    # Check for VPC name conflicts
    local vpcs_to_create
    vpcs_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_vpc") | .change.after.tags.Name // .change.after.id' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$vpcs_to_create" ] && [ "$vpcs_to_create" != "null" ]; then
        log_info "Checking VPC name conflicts..."

        while IFS= read -r vpc_name; do
            if [ -n "$vpc_name" ] && [ "$vpc_name" != "null" ]; then
                # Check if VPC with this name already exists
                if aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$vpc_name" --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q "vpc-"; then
                    log_error "VPC name conflict: VPC with name '$vpc_name' already exists"
                    ((conflict_count++))
                else
                    log_info "VPC name '$vpc_name' is available"
                fi
            fi
        done <<< "$vpcs_to_create"
    fi

    # Check for VPC CIDR block conflicts
    local vpc_cidrs_to_create
    vpc_cidrs_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_vpc") | .change.after.cidr_block' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$vpc_cidrs_to_create" ] && [ "$vpc_cidrs_to_create" != "null" ]; then
        log_info "Checking VPC CIDR block conflicts..."

        while IFS= read -r cidr_block; do
            if [ -n "$cidr_block" ] && [ "$cidr_block" != "null" ]; then
                # Check if this CIDR block already exists in any VPC
                if aws ec2 describe-vpcs --filters "Name=cidr,Values=$cidr_block" --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q "vpc-"; then
                    log_error "VPC CIDR block conflict: CIDR '$cidr_block' already exists in another VPC"
                    ((conflict_count++))
                else
                    log_info "VPC CIDR block '$cidr_block' is available"
                fi
            fi
        done <<< "$vpc_cidrs_to_create"
    fi

    # Check for subnet conflicts within same VPC
    local subnets_to_create
    subnets_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_subnet") | "\(.change.after.vpc_id // "unknown")|\(.change.after.cidr_block)"' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$subnets_to_create" ] && [ "$subnets_to_create" != "null" ]; then
        log_info "Checking subnet conflicts..."

        # Group subnets by VPC for conflict checking
        declare -A vpc_subnets
        while IFS='|' read -r vpc_id cidr_block; do
            if [ -n "$vpc_id" ] && [ "$vpc_id" != "null" ] && [ -n "$cidr_block" ] && [ "$cidr_block" != "null" ]; then
                # Check if subnet CIDR already exists in the target VPC
                if aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=cidr-block,Values=$cidr_block" --query 'Subnets[0].SubnetId' --output text 2>/dev/null | grep -q "subnet-"; then
                    log_error "Subnet CIDR conflict: Subnet with CIDR '$cidr_block' already exists in VPC '$vpc_id'"
                    ((conflict_count++))
                else
                    log_info "Subnet CIDR '$cidr_block' in VPC '$vpc_id' is available"
                fi
            fi
        done <<< "$subnets_to_create"
    fi

    echo "$conflict_count"
}

# Function to check for general resource conflicts
check_general_conflicts() {
    local conflict_count=0
    log_info "Checking general resource conflicts..."

    # Check for ECR repository name conflicts
    local ecr_repos_to_create
    ecr_repos_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_ecr_repository") | .change.after.name' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$ecr_repos_to_create" ] && [ "$ecr_repos_to_create" != "null" ]; then
        log_info "Checking ECR repository name conflicts..."

        while IFS= read -r repo_name; do
            if [ -n "$repo_name" ] && [ "$repo_name" != "null" ]; then
                if aws ecr describe-repositories --repository-names "$repo_name" --query 'repositories[0].repositoryName' --output text 2>/dev/null | grep -q "$repo_name"; then
                    log_error "ECR repository conflict: Repository '$repo_name' already exists"
                    ((conflict_count++))
                else
                    log_info "ECR repository '$repo_name' is available"
                fi
            fi
        done <<< "$ecr_repos_to_create"
    fi

    # Check for CloudWatch log group conflicts
    local log_groups_to_create
    log_groups_to_create=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" and .type == "aws_cloudwatch_log_group") | .change.after.name' "$TEMP_JSON" 2>/dev/null || echo "")

    if [ -n "$log_groups_to_create" ] && [ "$log_groups_to_create" != "null" ]; then
        log_info "Checking CloudWatch log group conflicts..."

        while IFS= read -r log_group_name; do
            if [ -n "$log_group_name" ] && [ "$log_group_name" != "null" ]; then
                if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group_name"; then
                    log_error "CloudWatch log group conflict: Log group '$log_group_name' already exists"
                    ((conflict_count++))
                else
                    log_info "CloudWatch log group '$log_group_name' is available"
                fi
            fi
        done <<< "$log_groups_to_create"
    fi

    # Check for required tags compliance
    # This check is informational only and doesn't affect conflict count
    local all_resources_with_tags
    all_resources_with_tags=$(jq -r '.resource_changes[] | select(.change.actions[] == "create" or .change.actions[] == "update") | .type + "|" + (.change.after.tags // {}) | . as $resource | to_entries[] | "\($resource)|\(.key)=\(.value)"' "$TEMP_JSON" 2>/dev/null || echo "")

    # For resources that should have tags, check if required tags are present
    # This is a simplified check - in practice, you might have different requirements per resource type
    if [ -n "$all_resources_with_tags" ] && [ "$all_resources_with_tags" != "null" ]; then
        log_info "Checking required tags compliance..."

        # Extract unique resource types to check for missing tags
        local unique_resource_types
        unique_resource_types=$(echo "$all_resources_with_tags" | cut -d'|' -f1 | sort -u)

        while IFS= read -r resource_type; do
            if [ "$resource_type" != "null" ] && [ -n "$resource_type" ]; then
                # For this example, we'll check if there are any tags at all
                # In a real implementation, you'd check for specific required tags
                local resource_tags_for_type
                resource_tags_for_type=$(echo "$all_resources_with_tags" | grep "^$resource_type|" | head -n 1 | cut -d'|' -f2)

                if [ -z "$resource_tags_for_type" ] || [ "$resource_tags_for_type" = "{}" ]; then
                    log_warn "Resource $resource_type has no tags defined (not necessarily an error, depends on organization policy)"
                fi
            fi
        done <<< "$unique_resource_types"
    fi

    echo "$conflict_count"
}
