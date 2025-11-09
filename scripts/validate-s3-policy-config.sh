#!/bin/bash
#
# Validation script for S3 endpoint policy configuration
#
# This script validates the Terraform configuration without requiring AWS credentials.
# It checks that the policy is correctly configured and follows best practices.
#
# Usage: ./scripts/validate-s3-policy-config.sh
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NETWORKING_MODULE="${PROJECT_ROOT}/infra/aws-core/terraform/modules/networking"

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

# Check if files exist
check_files_exist() {
    log_info "Checking required files..."

    local files=(
        "${NETWORKING_MODULE}/variables.tf"
        "${NETWORKING_MODULE}/s3-endpoint-policy.tf"
        "${NETWORKING_MODULE}/vpc-endpoints.tf"
        "${NETWORKING_MODULE}/README.md"
    )

    for file in "${files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "✓ Found: ${file}"
        else
            log_error "✗ Missing: ${file}"
            return 1
        fi
    done

    return 0
}

# Validate Terraform syntax
validate_terraform_syntax() {
    log_info "Validating Terraform syntax..."

    cd "${NETWORKING_MODULE}"

    # Check formatting
    if terraform fmt -check -diff > /dev/null 2>&1; then
        log_info "✓ Terraform formatting is correct"
    else
        log_error "✗ Terraform formatting issues found"
        terraform fmt -diff
        return 1
    fi

    # Validate syntax
    # First check if modules are installed
    VALIDATE_OUTPUT=$(terraform validate 2>&1 || true)
    if echo "${VALIDATE_OUTPUT}" | grep -q "Module not installed"; then
        log_warn "⚠ Terraform modules not installed (run 'terraform init' to validate)"
        log_info "ⓘ This is expected in a fresh checkout - skipping syntax check"
    elif echo "${VALIDATE_OUTPUT}" | grep -q "Error:"; then
        log_error "✗ Terraform syntax errors found"
        echo "${VALIDATE_OUTPUT}"
        return 1
    else
        log_info "✓ Terraform syntax is valid"
    fi

    return 0
}

# Check variables are defined
check_variables() {
    log_info "Checking S3 endpoint variables..."

    local variables_file="${NETWORKING_MODULE}/variables.tf"

    # Check for required variables
    if grep -q "s3_endpoint_enable_policy" "${variables_file}"; then
        log_info "✓ s3_endpoint_enable_policy variable found"
    else
        log_error "✗ s3_endpoint_enable_policy variable not found"
        return 1
    fi

    if grep -q "s3_endpoint_allow_additional_buckets" "${variables_file}"; then
        log_info "✓ s3_endpoint_allow_additional_buckets variable found"
    else
        log_error "✗ s3_endpoint_allow_additional_buckets variable not found"
        return 1
    fi

    # Check default values
    if grep -A3 "variable.*s3_endpoint_enable_policy" "${variables_file}" | grep -q "default.*=.*true"; then
        log_info "✓ s3_endpoint_enable_policy defaults to true (least privilege)"
    else
        log_warn "⚠ s3_endpoint_enable_policy should default to true"
    fi

    return 0
}

# Check policy configuration
check_policy_configuration() {
    log_info "Checking S3 endpoint policy configuration..."

    local policy_file="${NETWORKING_MODULE}/s3-endpoint-policy.tf"

    # Check if policy file exists
    if [[ ! -f "${policy_file}" ]]; then
        log_error "✗ S3 endpoint policy file not found"
        return 1
    fi

    # Check for ECR bucket pattern
    if grep -q "prod.*starport-layer-bucket" "${policy_file}"; then
        log_info "✓ ECR S3 bucket pattern found"
    else
        log_error "✗ ECR S3 bucket pattern not found"
        return 1
    fi

    # Check for least privilege configuration
    if grep -q "Effect.*=.*Allow" "${policy_file}" && grep -q "Effect.*=.*Deny" "${policy_file}"; then
        log_info "✓ Policy includes both Allow and Deny statements"
    else
        log_error "✗ Policy missing Allow or Deny statements"
        return 1
    fi

    # Check for S3 actions
    if grep -q "s3:GetObject" "${policy_file}" && grep -q "s3:ListBucket" "${policy_file}"; then
        log_info "✓ Required S3 actions (GetObject, ListBucket) found"
    else
        log_error "✗ Required S3 actions not found"
        return 1
    fi

    # Check for conditional policy application
    if grep -q "s3_endpoint_enable_policy" "${policy_file}"; then
        log_info "✓ Policy is conditional on s3_endpoint_enable_policy variable"
    else
        log_error "✗ Policy is not conditional"
        return 1
    fi

    return 0
}

# Check VPC endpoint configuration
check_vpc_endpoint() {
    log_info "Checking S3 VPC endpoint configuration..."

    local endpoints_file="${NETWORKING_MODULE}/vpc-endpoints.tf"

    # Check if S3 endpoint uses the policy
    if grep -q "policy = local.s3_endpoint_policy" "${endpoints_file}"; then
        log_info "✓ S3 VPC endpoint uses the policy"
    else
        log_error "✗ S3 VPC endpoint not configured to use policy"
        return 1
    fi

    # Check for correct service name
    if grep -q "com.amazonaws.*.s3" "${endpoints_file}"; then
        log_info "✓ S3 service name is correct"
    else
        log_error "✗ S3 service name is incorrect"
        return 1
    fi

    # Check for gateway endpoint type
    if grep -A10 -B5 "service_name.*s3" "${endpoints_file}" | grep -q "vpc_endpoint_type = \"Gateway\""; then
        log_info "✓ S3 endpoint is of Gateway type"
    else
        log_error "✗ S3 endpoint is not of Gateway type"
        return 1
    fi

    return 0
}

# Check documentation
check_documentation() {
    log_info "Checking documentation..."

    local readme_file="${NETWORKING_MODULE}/README.md"

    # Check for S3 endpoint policy documentation
    if grep -q "S3 VPC Endpoint Security" "${readme_file}"; then
        log_info "✓ S3 endpoint security documentation found"
    else
        log_warn "⚠ S3 endpoint security documentation not found"
    fi

    # Check for example configuration
    if grep -q "s3_endpoint_enable_policy = true" "${readme_file}"; then
        log_info "✓ Example configuration found"
    else
        log_warn "⚠ Example configuration not found"
    fi

    # Check for troubleshooting section
    if grep -q "Troubleshooting" "${readme_file}"; then
        log_info "✓ Troubleshooting section found"
    else
        log_warn "⚠ Troubleshooting section not found"
    fi

    return 0
}

# Main function
main() {
    log_info "Validating S3 endpoint policy configuration..."
    echo

    # Initialize test counters
    TESTS_PASSED=0
    TESTS_TOTAL=0

    # Run validation checks
    ((TESTS_TOTAL++))
    if check_files_exist; then
        ((TESTS_PASSED++))
    fi

    ((TESTS_TOTAL++))
    if validate_terraform_syntax; then
        ((TESTS_PASSED++))
    fi

    ((TESTS_TOTAL++))
    if check_variables; then
        ((TESTS_PASSED++))
    fi

    ((TESTS_TOTAL++))
    if check_policy_configuration; then
        ((TESTS_PASSED++))
    fi

    ((TESTS_TOTAL++))
    if check_vpc_endpoint; then
        ((TESTS_PASSED++))
    fi

    ((TESTS_TOTAL++))
    if check_documentation; then
        ((TESTS_PASSED++))
    fi

    # Summary
    echo
    log_info "Validation Results: ${TESTS_PASSED}/${TESTS_TOTAL} checks passed"

    if [[ ${TESTS_PASSED} -eq ${TESTS_TOTAL} ]]; then
        log_info "Configuration validation passed!"
        echo
        log_info "Next steps:"
        echo "  1. Run 'terraform apply' to deploy the changes"
        echo "  2. Execute './scripts/test-s3-endpoint-policy.sh' to test the implementation"
        exit 0
    else
        log_error "Configuration validation failed. Please fix the issues above."
        exit 1
    fi
}

# Run main function
main "$@"
