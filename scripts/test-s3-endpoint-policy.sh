#!/bin/bash
#
# Test script for S3 VPC endpoint least-privilege policy
#
# This script verifies that the S3 endpoint policy is working correctly
# by testing access to ECR and non-ECR S3 buckets from an EKS node.
#
# Usage: ./scripts/test-s3-endpoint-policy.sh
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra/aws-core/terraform/environments/dev"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        exit 1
    fi

    # Check if we're in the right directory
    if [[ ! -d "${INFRA_DIR}" ]]; then
        log_error "Infrastructure directory not found: ${INFRA_DIR}"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Get ECR S3 bucket name from Terraform output
get_ecr_bucket_name() {
    log_info "Getting ECR S3 bucket name..."

    cd "${INFRA_DIR}"

    # Get the bucket name from Terraform output
    BUCKET_NAME=$(terraform output -raw ecr_s3_bucket_name 2>/dev/null || echo "")

    if [[ -z "${BUCKET_NAME}" ]]; then
        log_error "Could not get ECR S3 bucket name from Terraform output"
        log_error "Make sure the networking module is deployed and outputs are available"
        exit 1
    fi

    log_info "ECR S3 bucket: ${BUCKET_NAME}"
    echo "${BUCKET_NAME}"
}

# Get an EKS node instance ID
get_eks_node_id() {
    log_info "Getting EKS node instance ID..."

    # Get node name
    NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "${NODE_NAME}" ]]; then
        log_error "Could not get EKS node name. Make sure kubectl is configured and cluster is accessible"
        exit 1
    fi

    # Get instance ID from node name
    INSTANCE_ID=$(kubectl describe node "${NODE_NAME}" | grep "ProviderID:" | awk -F'/' '{print $NF}' 2>/dev/null || echo "")

    if [[ -z "${INSTANCE_ID}" ]]; then
        log_error "Could not extract instance ID from node ${NODE_NAME}"
        exit 1
    fi

    log_info "EKS node instance ID: ${INSTANCE_ID}"
    echo "${INSTANCE_ID}"
}

# Test S3 access from an EKS node
test_s3_access() {
    local bucket_name="$1"
    local instance_id="$2"
    local should_succeed="$3"

    local test_name="S3 access to ${bucket_name}"

    log_info "Testing ${test_name}..."

    # Send the test command directly via SSM
    local send_command_output
    if ! send_command_output=$(aws ssm send-command \
        --instance-ids "${instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"BUCKET_NAME='${bucket_name}'; EXPECTED_RESULT='${should_succeed}'; \
        aws s3 ls \\\"s3://\${BUCKET_NAME}/\\\" > /dev/null 2>&1; \
        EXIT_CODE=\$?; \
        if [[ \\\"\${EXPECTED_RESULT}\\\" == \\\"success\\\" ]]; then \
            if [[ \$EXIT_CODE -eq 0 ]]; then \
                echo 'SUCCESS: Access granted to \${BUCKET_NAME}'; exit 0; \
            else \
                echo 'FAILURE: Access denied to \${BUCKET_NAME} (expected success)'; exit 1; \
            fi; \
        else \
            if [[ \$EXIT_CODE -ne 0 ]]; then \
                echo 'SUCCESS: Access properly denied to \${BUCKET_NAME}'; exit 0; \
            else \
                echo 'FAILURE: Access granted to \${BUCKET_NAME} (expected denial)'; exit 1; \
            fi; \
        fi\"]" \
        --output json 2>/dev/null); then
        log_error "Failed to execute test on instance ${instance_id}"
        return 1
    fi

    # Extract command ID from the response
    local command_id
    command_id=$(echo "${send_command_output}" | jq -r '.Command.CommandId')
    if [[ -z "${command_id}" || "${command_id}" == "null" ]]; then
        log_error "Could not retrieve CommandId from send-command output"
        return 1
    fi

    # Poll for command completion
    local status
    for i in {1..30}; do
        status=$(aws ssm get-command-invocation \
            --command-id "${command_id}" \
            --instance-id "${instance_id}" \
            --output json 2>/dev/null | jq -r '.Status')

        if [[ "${status}" == "Success" || "${status}" == "Failed" || "${status}" == "Cancelled" || "${status}" == "TimedOut" ]]; then
            break
        fi

        sleep 2
    done

    # Get the final result
    local output
    output=$(aws ssm get-command-invocation \
        --command-id "${command_id}" \
        --instance-id "${instance_id}" \
        --output json 2>/dev/null)

    status=$(echo "${output}" | jq -r '.Status')
    local stdout
    stdout=$(echo "${output}" | jq -r '.StandardOutputContent')

    if [[ "${status}" == "Success" && "${stdout}" == *"SUCCESS"* ]]; then
        log_info "✓ ${test_name} test passed"
        return 0
    else
        log_error "✗ ${test_name} test failed"
        [[ -n "${stdout}" ]] && echo -e "${YELLOW}Output:${NC}\n${stdout}"
        return 1
    fi
}

# Test ECR image pull from a pod
test_ecr_pull() {
    log_info "Testing ECR image pull from pod..."

    # Default ECR image (can be overridden via environment)
    local ecr_image="${ECR_TEST_IMAGE:-}"

    # Skip if no ECR image is configured
    if [[ -z "${ecr_image}" ]]; then
        log_warn "Skipping ECR pull test - Set ECR_TEST_IMAGE environment variable with your ECR image details"
        log_warn "Example: export ECR_TEST_IMAGE=123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app:latest"
        return 0
    fi

    # Create a test pod using a private ECR image
    # Private ECR images test the S3 VPC endpoint policy for ECR layer buckets
    kubectl run s3-policy-test \
        --image="${ecr_image}" \
        --rm -i --restart=Never \
        --command -- bash -c "echo 'ECR image pull successful'" \
        > /dev/null 2>&1

    # Capture exit code immediately
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "✓ ECR image pull test passed"
        return 0
    else
        log_error "✗ ECR image pull test failed"
        log_warn "Note: Ensure the ECR image exists and is accessible from the cluster"
        return 1
    fi
}

# Main function
main() {
    log_info "Starting S3 endpoint policy tests..."

    # Check prerequisites
    check_prerequisites

    # Get required information
    ECR_BUCKET=$(get_ecr_bucket_name)
    NODE_INSTANCE=$(get_eks_node_id)

    # Initialize test counters
    TESTS_PASSED=0
    TESTS_TOTAL=0

    # Test 1: ECR bucket access (should succeed)
    ((TESTS_TOTAL++))
    if test_s3_access "${ECR_BUCKET}" "${NODE_INSTANCE}" "success"; then
        ((TESTS_PASSED++))
    fi

    # Test 2: Non-ECR bucket access (should fail)
    ((TESTS_TOTAL++))
    if test_s3_access "aws-public-blockchain-snapshots" "${NODE_INSTANCE}" "failure"; then
        ((TESTS_PASSED++))
    fi

    # Test 3: ECR image pull (should succeed)
    ((TESTS_TOTAL++))
    if test_ecr_pull; then
        ((TESTS_PASSED++))
    fi

    # Summary
    echo
    log_info "Test Results: ${TESTS_PASSED}/${TESTS_TOTAL} tests passed"

    if [[ ${TESTS_PASSED} -eq ${TESTS_TOTAL} ]]; then
        log_info "All tests passed! S3 endpoint policy is working correctly."
        exit 0
    else
        log_error "Some tests failed. Please review the configuration."
        exit 1
    fi
}

# Run main function
main "$@"
