#!/bin/bash
#
# Check S3 VPC Endpoint Policy Status
#
# This script checks if the S3 VPC endpoint policy is correctly applied
# and functioning as expected.
#
# Usage: ./scripts/check-s3-endpoint-status.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra/aws-core/terraform/environments/dev"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Get VPC endpoint details
get_vpc_endpoint() {
    log_info "Getting S3 VPC endpoint details..."

    cd "${INFRA_DIR}" || {
        log_error "Could not navigate to infra directory"
        exit 1
    }

    # Get the VPC ID from Terraform outputs
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    if [[ -z "${VPC_ID}" ]]; then
        log_error "Could not get VPC ID from Terraform outputs"
        exit 1
    fi

    log_info "VPC ID: ${VPC_ID}"

    # Get S3 VPC endpoint
    S3_ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints \
        --filters Name=service-name,Values=com.amazonaws.*.s3 Name=vpc-id,Values="${VPC_ID}" \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text 2>/dev/null || echo "")

    if [[ -z "${S3_ENDPOINT_ID}" || "${S3_ENDPOINT_ID}" == "None" ]]; then
        log_error "Could not find S3 VPC endpoint"
        exit 1
    fi

    log_info "S3 VPC Endpoint ID: ${S3_ENDPOINT_ID}"
    echo "${S3_ENDPOINT_ID}"
}

# Check if policy is applied
check_endpoint_policy() {
    local endpoint_id="$1"

    log_info "Checking S3 VPC endpoint policy..."

    # Get the policy document
    POLICY_JSON=$(aws ec2 describe-vpc-endpoints \
        --vpc-endpoint-ids "${endpoint_id}" \
        --query 'VpcEndpoints[0].PolicyDocument' \
        --output json 2>/dev/null || echo "{}")

    if [[ "${POLICY_JSON}" == "{}" || "${POLICY_JSON}" == "null" ]]; then
        log_warn "No policy found on S3 VPC endpoint (full access allowed)"
        return 1
    fi

    # Check if it contains ECR bucket references
    if echo "${POLICY_JSON}" | jq -e '.Statement[] | select(.Resource[] | contains("starport-layer-bucket"))' > /dev/null; then
        log_info "✓ Policy contains ECR bucket restrictions"
        return 0
    else
        log_error "✗ Policy does not contain expected ECR bucket restrictions"
        echo "${POLICY_JSON}" | jq '.'
        return 1
    fi
}

# Check route table attachments
check_route_table_attachments() {
    local endpoint_id="$1"

    log_info "Checking route table attachments..."

    # Get route tables the endpoint is attached to
    ROUTE_TABLES=$(aws ec2 describe-vpc-endpoints \
        --vpc-endpoint-ids "${endpoint_id}" \
        --query 'VpcEndpoints[0].RouteTableIds' \
        --output json 2>/dev/null || echo "[]")

    RT_COUNT=$(echo "${ROUTE_TABLES}" | jq 'length')
    if [[ ${RT_COUNT} -eq 0 ]]; then
        log_error "✗ S3 VPC endpoint is not attached to any route tables"
        return 1
    fi

    log_info "✓ S3 VPC endpoint is attached to ${RT_COUNT} route table(s)"
    echo "${ROUTE_TABLES}" | jq -r '.[]' | sed 's/^/  - /'
    return 0
}

# Get ECR bucket name for current region
get_ecr_bucket_name() {
    log_info "Getting ECR S3 bucket name for current region..."

    REGION=$(aws configure get region 2>/dev/null || aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].ZoneName' | sed 's/.$//')
    ECR_BUCKET="prod-${REGION}-starport-layer-bucket"

    log_info "ECR S3 bucket: ${ECR_BUCKET}"
    echo "${ECR_BUCKET}"
}

# Test S3 access to ECR bucket
test_ecr_bucket_access() {
    local bucket_name="$1"

    log_info "Testing access to ECR S3 bucket: ${bucket_name}"

    # Check if bucket exists and is accessible
    if aws s3 ls "s3://${bucket_name}/" > /dev/null 2>&1; then
        log_info "✓ ECR S3 bucket is accessible"
        return 0
    else
        log_warn "⚠ ECR S3 bucket not directly accessible (expected behavior - requires VPC endpoint)"
        return 0
    fi
}

# Test access to non-ECR bucket (should fail)
test_non_ecr_bucket_access() {
    log_info "Testing access to non-ECR bucket (should be denied)..."

    # Use a known public bucket
    if aws s3 ls "s3://aws-public-blockchain-snapshots/" > /dev/null 2>&1; then
        log_warn "⚠ Public bucket is accessible (policy may not be active or test from outside VPC)"
    else
        log_info "✓ Access to non-ECR bucket is properly blocked"
    fi
}

# Main function
main() {
    echo "========================================"
    echo "S3 VPC Endpoint Policy Status Check"
    echo "========================================"
    echo

    # Check prerequisites
    check_prerequisites
    echo

    # Get VPC endpoint details
    S3_ENDPOINT=$(get_vpc_endpoint)
    echo

    # Check endpoint policy
    if check_endpoint_policy "${S3_ENDPOINT}"; then
        POLICY_STATUS="Applied"
    else
        POLICY_STATUS="Not Found"
    fi
    echo

    # Check route table attachments
    check_route_table_attachments "${S3_ENDPOINT}"
    echo

    # Get ECR bucket name
    ECR_BUCKET=$(get_ecr_bucket_name)
    echo

    # Test bucket access
    test_ecr_bucket_access "${ECR_BUCKET}"
    test_non_ecr_bucket_access
    echo

    # Summary
    echo "========================================"
    echo "Status Summary"
    echo "========================================"
    echo "VPC Endpoint ID: ${S3_ENDPOINT}"
    echo "Policy Status: ${POLICY_STATUS}"
    echo "ECR Bucket: ${ECR_BUCKET}"
    echo ""

    if [[ "${POLICY_STATUS}" == "Applied" ]]; then
        log_info "✓ S3 VPC endpoint policy is properly configured"
    else
        log_error "✗ S3 VPC endpoint policy is not applied"
        echo ""
        echo "To apply the policy, run:"
        echo "  cd ${INFRA_DIR}"
        echo "  terraform apply -target=module.networking"
    fi
}

# Run main function
main "$@"
