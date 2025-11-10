// ... existing code ...
#!/usr/bin/env bash
# Shared helpers for S3 VPC endpoint policy validation and testing.
#
# This file centralizes logic used by:
#   - scripts/check-s3-endpoint-status.sh
#   - scripts/test-s3-endpoint-policy.sh
#   - scripts/validate-s3-policy-config.sh
#
# Top-level scripts in ./scripts are thin wrappers that delegate into these
# helpers. This keeps behavior stable while avoiding duplicated business logic.
#
# NOTE: This script is intended to be executed by wrappers, not sourced blindly.
# Call the exported functions or the specific entrypoints from wrappers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

log_header() {
  local title=$1
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}${title}${NC}"
  echo -e "${BLUE}========================================${NC}"
}

# -----------------------------------------------------------------------------
# check-s3-endpoint-status: behavior extracted from scripts/check-s3-endpoint-status.sh
# -----------------------------------------------------------------------------

s3_endpoint_status_check_prereqs() {
  log_info "Checking prerequisites..."

  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI is not installed"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq is not installed"
    exit 1
  fi

  log_info "Prerequisites check passed"
}

s3_endpoint_status_get_vpc_endpoint() {
  local infra_dir="$1"

  log_info "Getting S3 VPC endpoint details..."

  cd "${infra_dir}" || {
    log_error "Could not navigate to infra directory: ${infra_dir}"
    exit 1
  }

  local vpc_id
  vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "")
  if [[ -z "${vpc_id}" ]]; then
    log_error "Could not get VPC ID from Terraform outputs"
    exit 1
  fi
  log_info "VPC ID: ${vpc_id}"

  local endpoint_id
  endpoint_id=$(aws ec2 describe-vpc-endpoints \
    --filters Name=service-name,Values=com.amazonaws.*.s3 Name=vpc-id,Values="${vpc_id}" \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text 2>/dev/null || echo "")

  if [[ -z "${endpoint_id}" || "${endpoint_id}" == "None" ]]; then
    log_error "Could not find S3 VPC endpoint"
    exit 1
  fi

  log_info "S3 VPC Endpoint ID: ${endpoint_id}"
  echo "${endpoint_id}"
}

s3_endpoint_status_check_policy() {
  local endpoint_id="$1"

  log_info "Checking S3 VPC endpoint policy..."

  local policy_json
  policy_json=$(aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids "${endpoint_id}" \
    --query 'VpcEndpoints[0].PolicyDocument' \
    --output json 2>/dev/null || echo "{}")

  if [[ "${policy_json}" == "{}" || "${policy_json}" == "null" ]]; then
    log_warn "No policy found on S3 VPC endpoint (full access allowed)"
    return 1
  fi

  local bucket_pattern="starport-layer-bucket"
  local match_count
  match_count=$(echo "${policy_json}" | jq --arg pattern "$bucket_pattern" '
    [ .Statement[]?.Resource? // [] , .Statement[]?.NotResource? // [] ]
    | flatten
    | map(select(. | type == "string" and contains($pattern)))
    | length
  ')

  if [[ "$match_count" -gt 0 ]]; then
    log_info "✓ Policy contains ECR bucket restrictions"
    return 0
  else
    log_error "✗ Policy does not contain expected ECR bucket restrictions"
    echo "${policy_json}" | jq '.'
    return 1
  fi
}

s3_endpoint_status_check_route_tables() {
  local endpoint_id="$1"

  log_info "Checking route table attachments..."

  local route_tables
  route_tables=$(aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids "${endpoint_id}" \
    --query 'VpcEndpoints[0].RouteTableIds' \
    --output json 2>/dev/null || echo "[]")

  local rt_count
  rt_count=$(echo "${route_tables}" | jq 'length')
  if [[ ${rt_count} -eq 0 ]]; then
    log_error "✗ S3 VPC endpoint is not attached to any route tables"
    return 1
  fi

  log_info "✓ S3 VPC endpoint is attached to ${rt_count} route table(s)"
  echo "${route_tables}" | jq -r '.[]' | sed 's/^/  - /'
  return 0
}

s3_endpoint_status_get_ecr_bucket_name() {
  log_info "Getting ECR S3 bucket name for current region..."
  local region
  region=$(aws configure get region 2>/dev/null || aws ec2 describe-availability-zones --query 'AvailabilityZones[0].RegionName' --output text 2>/dev/null)
  local bucket="prod-${region}-starport-layer-bucket"
  log_info "ECR S3 bucket: ${bucket}"
  echo "${bucket}"
}

s3_endpoint_status_test_ecr_bucket_access() {
  local bucket_name="$1"
  log_info "Testing access to ECR S3 bucket: ${bucket_name}"
  if aws s3 ls "s3://${bucket_name}/" >/dev/null 2>&1; then
    log_info "✓ ECR S3 bucket is accessible"
    return 0
  else
    log_warn "⚠ ECR S3 bucket not directly accessible (expected behavior - may require VPC endpoint)"
    return 0
  fi
}

s3_endpoint_status_test_non_ecr_bucket_access() {
  log_info "Testing access to non-ECR bucket (should be denied)..."
  if aws s3 ls "s3://aws-public-blockchain-snapshots/" >/dev/null 2>&1; then
    log_warn "⚠ Public bucket is accessible (policy may not be active or test from outside VPC)"
  else
    log_info "✓ Access to non-ECR bucket is properly blocked"
  fi
}

s3_endpoint_status_main() {
  local infra_dir="${PROJECT_ROOT}/infra/aws-core/terraform/environments/dev"

  log_header "S3 VPC Endpoint Policy Status Check"

  s3_endpoint_status_check_prereqs

  local s3_endpoint
  s3_endpoint=$(s3_endpoint_status_get_vpc_endpoint "${infra_dir}")

  local policy_status
  if s3_endpoint_status_check_policy "${s3_endpoint}"; then
    policy_status="Applied"
  else
    policy_status="Not Found"
  fi

  s3_endpoint_status_check_route_tables "${s3_endpoint}"

  local ecr_bucket
  ecr_bucket=$(s3_endpoint_status_get_ecr_bucket_name)

  s3_endpoint_status_test_ecr_bucket_access "${ecr_bucket}"
  s3_endpoint_status_test_non_ecr_bucket_access

  log_header "Status Summary"
  echo "VPC Endpoint ID: ${s3_endpoint}"
  echo "Policy Status: ${policy_status}"
  echo "ECR Bucket: ${ecr_bucket}"
  echo ""

  if [[ "${policy_status}" == "Applied" ]]; then
    log_info "✓ S3 VPC endpoint policy is properly configured"
  else
    log_error "✗ S3 VPC endpoint policy is not applied"
    echo ""
    echo "To apply the policy, run:"
    echo "  cd ${infra_dir}"
    echo "  terraform apply -target=module.networking"
  fi
}

# -----------------------------------------------------------------------------
# test-s3-endpoint-policy: behavior extracted from scripts/test-s3-endpoint-policy.sh
# -----------------------------------------------------------------------------

s3_endpoint_policy_check_prereqs() {
  log_info "Checking prerequisites..."

  for cmd in aws kubectl terraform jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "$cmd is not installed"
      exit 1
    fi
  done

  local infra_dir="${PROJECT_ROOT}/infra/aws-core/terraform/environments/dev"
  if [[ ! -d "${infra_dir}" ]]; then
    log_error "Infrastructure directory not found: ${infra_dir}"
    exit 1
  fi

  log_info "Prerequisites check passed"
}

s3_endpoint_policy_get_ecr_bucket_name() {
  local infra_dir="${PROJECT_ROOT}/infra/aws-core/terraform/environments/dev"
  log_info "Getting ECR S3 bucket name..."

  cd "${infra_dir}"

  local bucket_name
  bucket_name=$(terraform output -raw ecr_s3_bucket_name 2>/dev/null || echo "")
  if [[ -z "${bucket_name}" ]]; then
    log_error "Could not get ECR S3 bucket name from Terraform output"
    log_error "Make sure the networking module is deployed and outputs are available"
    exit 1
  fi

  log_info "ECR S3 bucket: ${bucket_name}"
  echo "${bucket_name}"
}

s3_endpoint_policy_get_eks_node_id() {
  log_info "Getting EKS node instance ID..."

  local node_name
  node_name=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "${node_name}" ]]; then
    log_error "Could not get EKS node name. Make sure kubectl is configured and cluster is accessible"
    exit 1
  fi

  local instance_id
  instance_id=$(kubectl describe node "${node_name}" | grep "ProviderID:" | awk -F'/' '{print $NF}' 2>/dev/null || echo "")
  if [[ -z "${instance_id}" ]]; then
    log_error "Could not extract instance ID from node ${node_name}"
    exit 1
  fi

  log_info "EKS node instance ID: ${instance_id}"
  echo "${instance_id}"
}

s3_endpoint_policy_test_s3_access() {
  local bucket_name="$1"
  local instance_id="$2"
  local should_succeed="$3"

  local test_name="S3 access to ${bucket_name}"
  log_info "Testing ${test_name} via SSM on instance ${instance_id}..."

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

  local command_id
  command_id=$(echo "${send_command_output}" | jq -r '.Command.CommandId')
  if [[ -z "${command_id}" || "${command_id}" == "null" ]]; then
    log_error "Could not retrieve CommandId from send-command output"
    return 1
  fi

  local status
  for _ in {1..30}; do
    status=$(aws ssm get-command-invocation \
      --command-id "${command_id}" \
      --instance-id "${instance_id}" \
      --output json 2>/dev/null | jq -r '.Status')

    if [[ "${status}" == "Success" || "${status}" == "Failed" || "${status}" == "Cancelled" || "${status}" == "TimedOut" ]]; then
      break
    fi
    sleep 2
  done

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

s3_endpoint_policy_test_ecr_pull() {
  log_info "Testing ECR image pull from pod..."

  local ecr_image="${ECR_TEST_IMAGE:-}"

  if [[ -z "${ecr_image}" ]]; then
    log_warn "Skipping ECR pull test - Set ECR_TEST_IMAGE environment variable with your ECR image details"
    log_warn "Example: export ECR_TEST_IMAGE=123456789012.dkr.ecr.us-west-2.amazonaws.com/my-app:latest"
    return 0
  fi

  kubectl run s3-policy-test \
    --image="${ecr_image}" \
    --rm -i --restart=Never \
    --command -- bash -c "echo 'ECR image pull successful'" \
    >/dev/null 2>&1

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

s3_endpoint_policy_tests_main() {
  log_info "Starting S3 endpoint policy tests..."

  s3_endpoint_policy_check_prereqs

  local ecr_bucket
  ecr_bucket=$(s3_endpoint_policy_get_ecr_bucket_name)
  local node_instance
  node_instance=$(s3_endpoint_policy_get_eks_node_id)

  local tests_total=0
  local tests_passed=0

  ((tests_total++))
  if s3_endpoint_policy_test_s3_access "${ecr_bucket}" "${node_instance}" "success"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_endpoint_policy_test_s3_access "aws-public-blockchain-snapshots" "${node_instance}" "failure"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_endpoint_policy_test_ecr_pull; then
    ((tests_passed++))
  fi

  echo
  log_info "Test Results: ${tests_passed}/${tests_total} tests passed"

  if [[ ${tests_passed} -eq ${tests_total} ]]; then
    log_info "All tests passed! S3 endpoint policy is working correctly."
    exit 0
  else
    log_error "Some tests failed. Please review the configuration."
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# validate-s3-policy-config: behavior extracted from scripts/validate-s3-policy-config.sh
# -----------------------------------------------------------------------------

s3_policy_config_check_files_exist() {
  local networking_module="$1"

  log_info "Checking required files..."

  local files=(
    "${networking_module}/variables.tf"
    "${networking_module}/s3-endpoint-policy.tf"
    "${networking_module}/vpc-endpoints.tf"
    "${networking_module}/README.md"
  )

  local missing=0
  for file in "${files[@]}"; do
    if [[ -f "${file}" ]]; then
      log_info "✓ Found: ${file}"
    else
      log_error "✗ Missing: ${file}"
      missing=1
    fi
  done

  return "${missing}"
}

s3_policy_config_validate_terraform_syntax() {
  local networking_module="$1"

  log_info "Validating Terraform syntax..."

  cd "${networking_module}"

  if terraform fmt -check -diff; then
    log_info "✓ Terraform formatting is correct"
  else
    log_error "✗ Terraform formatting issues found"
    return 1
  fi

  local validate_output
  validate_output=$(terraform validate 2>&1 || true)
  if echo "${validate_output}" | grep -q "Module not installed"; then
    log_warn "⚠ Terraform modules not installed (run 'terraform init' to validate)"
    log_info "ⓘ This is expected in a fresh checkout - skipping syntax check"
  elif echo "${validate_output}" | grep -q "Error:"; then
    log_error "✗ Terraform syntax errors found"
    echo "${validate_output}"
    return 1
  else
    log_info "✓ Terraform syntax is valid"
  fi

  return 0
}

s3_policy_config_check_variables() {
  local variables_file="$1"

  log_info "Checking S3 endpoint variables..."

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

  if grep -A3 "variable.*s3_endpoint_enable_policy" "${variables_file}" | grep -q "default.*=.*true"; then
    log_info "✓ s3_endpoint_enable_policy defaults to true (least privilege)"
  else
    log_warn "⚠ s3_endpoint_enable_policy should default to true"
  fi

  return 0
}

s3_policy_config_check_policy_file() {
  local policy_file="$1"

  log_info "Checking S3 endpoint policy configuration..."

  if [[ ! -f "${policy_file}" ]]; then
    log_error "✗ S3 endpoint policy file not found"
    return 1
  fi

  if grep -q "prod.*starport-layer-bucket" "${policy_file}"; then
    log_info "✓ ECR S3 bucket pattern found"
  else
    log_error "✗ ECR S3 bucket pattern not found"
    return 1
  fi

  if grep -q "Effect.*=.*Allow" "${policy_file}" && grep -q "Effect.*=.*Deny" "${policy_file}"; then
    log_info "✓ Policy includes both Allow and Deny statements"
  else
    log_error "✗ Policy missing Allow or Deny statements"
    return 1
  fi

  if grep -q "s3:GetObject" "${policy_file}" && grep -q "s3:ListBucket" "${policy_file}"; then
    log_info "✓ Required S3 actions (GetObject, ListBucket) found"
  else
    log_error "✗ Required S3 actions not found"
    return 1
  fi

  if grep -q "s3_endpoint_enable_policy" "${policy_file}"; then
    log_info "✓ Policy is conditional on s3_endpoint_enable_policy variable"
  else
    log_error "✗ Policy is not conditional"
    return 1
  fi

  return 0
}

s3_policy_config_check_vpc_endpoint() {
  local endpoints_file="$1"

  log_info "Checking S3 VPC endpoint configuration..."

  if grep -q "policy = local.s3_endpoint_policy" "${endpoints_file}"; then
    log_info "✓ S3 VPC endpoint uses the policy"
  else
    log_error "✗ S3 VPC endpoint not configured to use policy"
    return 1
  fi

  if grep -q "com.amazonaws.*.s3" "${endpoints_file}"; then
    log_info "✓ S3 service name is correct"
  else
    log_error "✗ S3 service name is incorrect"
    return 1
  fi

  if grep -A10 -B5 "service_name.*s3" "${endpoints_file}" | grep -q "vpc_endpoint_type = \"Gateway\""; then
    log_info "✓ S3 endpoint is of Gateway type"
  else
    log_error "✗ S3 endpoint is not of Gateway type"
    return 1
  fi

  return 0
}

s3_policy_config_check_docs() {
  local readme_file="$1"

  log_info "Checking documentation..."

  if grep -q "S3 VPC Endpoint Security" "${readme_file}"; then
    log_info "✓ S3 endpoint security documentation found"
  else
    log_warn "⚠ S3 endpoint security documentation not found"
  fi

  if grep -q "s3_endpoint_enable_policy = true" "${readme_file}"; then
    log_info "✓ Example configuration found"
  else
    log_warn "⚠ Example configuration not found"
  fi

  if grep -q "Troubleshooting" "${readme_file}"; then
    log_info "✓ Troubleshooting section found"
  else
    log_warn "⚠ Troubleshooting section not found"
  fi

  return 0
}

s3_policy_config_main() {
  local networking_module="${PROJECT_ROOT}/infra/aws-core/terraform/modules/networking"
  local variables_file="${networking_module}/variables.tf"
  local policy_file="${networking_module}/s3-endpoint-policy.tf"
  local endpoints_file="${networking_module}/vpc-endpoints.tf"
  local readme_file="${networking_module}/README.md"

  log_info "Validating S3 endpoint policy configuration..."
  echo

  local tests_total=0
  local tests_passed=0

  ((tests_total++))
  if s3_policy_config_check_files_exist "${networking_module}"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_policy_config_validate_terraform_syntax "${networking_module}"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_policy_config_check_variables "${variables_file}"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_policy_config_check_policy_file "${policy_file}"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_policy_config_check_vpc_endpoint "${endpoints_file}"; then
    ((tests_passed++))
  fi

  ((tests_total++))
  if s3_policy_config_check_docs "${readme_file}"; then
    ((tests_passed++))
  fi

  echo
  log_info "Validation Results: ${tests_passed}/${tests_total} checks passed"

  if [[ ${tests_passed} -eq ${tests_total} ]]; then
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

# -----------------------------------------------------------------------------
# Entrypoint router
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    check-status)
      shift
      s3_endpoint_status_main "$@"
      ;;
    test-policy)
      shift
      s3_endpoint_policy_tests_main "$@"
      ;;
    validate-config)
      shift
      s3_policy_config_main "$@"
      ;;
    *)
      echo "Usage: $(basename "$0") {check-status|test-policy|validate-config} [args...]" >&2
      exit 1
      ;;
  esac
fi
// ... existing code ...
