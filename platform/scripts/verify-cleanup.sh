#!/usr/bin/env bash
#
# AWS Cleanup Verification Script - Layer 3 Verification
#
# This script performs comprehensive multi-service verification to ensure
# complete resource cleanup after terraform destroy and nuclear cleanup.
#
# Usage:
#   ./platform/scripts/verify-cleanup.sh
#
# Exit Codes:
#   0 - All resources cleaned up successfully
#   1 - Resources still exist OR script error
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - jq installed for JSON parsing
#
set -euo pipefail

# ============================================================================
# AWS PROFILE / ACCOUNT SAFETY GUARDRAILS (SAFE TO COMMIT)
# ============================================================================

export AWS_PROFILE="kodekloud"
export AWS_REGION="us-west-2"

# Expected KodeKloud sandbox account ID
readonly EXPECTED_ACCOUNT_ID="984479408136"

# Configuration
readonly PROJECT_TAG_KEY="Project"
readonly PROJECT_TAG_VALUE="ml-platform-engineering-practicum"

# ============================================================================
# Logging Utilities (aligned with other cleanup scripts)
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

RESOURCES_FOUND=false

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
  echo ""
  echo -e "${CYAN}========================================${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}========================================${NC}"
}

log_resource_found() {
  echo -e "${MAGENTA}[FOUND]${NC} $1"
  RESOURCES_FOUND=true
}

# ============================================================================
# Safety / Preflight
# ============================================================================

check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not found. Install: macOS: 'brew install awscli' | Ubuntu: 'apt-get install awscli'"
    exit 1
  fi
  log_success "✓ AWS CLI found: $(aws --version 2>&1 | head -1)"

  if ! command -v jq &>/dev/null; then
    log_error "jq not found. Install: macOS: 'brew install jq' | Ubuntu: 'apt-get install jq'"
    exit 1
  fi
  log_success "✓ jq found: $(jq --version)"

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured or invalid"
    log_info "Set AWS_PROFILE environment variable or run 'aws configure'"
    exit 1
  fi
  log_success "✓ AWS credentials valid"
}

validate_aws_account() {
  local account_id
  account_id=$(aws sts get-caller-identity --query Account --output text)

  if [[ "$account_id" != "$EXPECTED_ACCOUNT_ID" ]]; then
    log_error "❌ Wrong AWS account!"
    log_error "   Expected: $EXPECTED_ACCOUNT_ID (KodeKloud sandbox)"
    log_error "   Current:  $account_id"
    log_error "   Profile:  $AWS_PROFILE"
    log_error ""
    log_error "This script is hardcoded to only run against the KodeKloud sandbox account."
    log_error "Exiting to prevent accidental operations in wrong account."
    exit 1
  fi

  log_success "✅ Correct AWS account verified: $account_id (KodeKloud sandbox)"
  echo ""
}

should_match_project_tag() {
  # Returns 0 if the given tags JSON contains the expected project tag.
  local tags_json
  tags_json=$1

  if [[ -z "$tags_json" ]]; then
    return 1
  fi

  if jq -e --arg k "$PROJECT_TAG_KEY" --arg v "$PROJECT_TAG_VALUE" \
    '. | .. | objects | select(.Key? == $k and .Value? == $v)' \
    <<<"$tags_json" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

# ============================================================================
# Verification Functions (behavior preserved)
# ============================================================================

verify_eks_clusters() {
  log_section "Checking EKS Clusters"

  local clusters
  clusters=$(aws eks list-clusters \
    --region "$AWS_REGION" \
    --query 'clusters[]' \
    --output json | jq -r '.[]') || clusters=""

  if [[ -z "$clusters" ]]; then
    log_success "✓ No EKS clusters found"
    return
  fi

  for cluster in $clusters; do
    local tags
    tags=$(aws eks describe-cluster \
      --name "$cluster" \
      --region "$AWS_REGION" \
      --query 'cluster.tags' \
      --output json 2>/dev/null || echo "{}")

    if should_match_project_tag "$tags"; then
      log_resource_found "EKS Cluster: $cluster"
    fi
  done
}

verify_ec2_instances() {
  log_section "Checking EC2 Instances"

  local instances
  # shellcheck disable=SC2016
  instances=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name,InstanceType]' \
    --output json | jq -r '.[] | @tsv') || instances=""

  if [[ -z "$instances" ]]; then
    log_success "✓ No EC2 instances found"
    return
  fi

  while IFS=$'\t' read -r instance_id state instance_type; do
    log_resource_found "EC2 Instance: $instance_id (State: $state, Type: $instance_type)"
  done <<<"$instances"
}

verify_load_balancers() {
  log_section "Checking Load Balancers"

  local load_balancers
  load_balancers=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query 'LoadBalancers[].LoadBalancerArn' \
    --output json | jq -r '.[]') || load_balancers=""

  if [[ -z "$load_balancers" ]]; then
    log_success "✓ No load balancers found"
    return
  fi

  for lb_arn in $load_balancers; do
    local tags
    tags=$(aws elbv2 describe-tags \
      --resource-arns "$lb_arn" \
      --region "$AWS_REGION" \
      --query 'TagDescriptions[0].Tags' \
      --output json 2>/dev/null || echo "[]")

    if should_match_project_tag "$tags"; then
      local lb_name
      lb_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$lb_arn" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerName' \
        --output text)
      log_resource_found "Load Balancer: $lb_name (ARN: $lb_arn)"
    fi
  done
}

verify_target_groups() {
  log_section "Checking Target Groups"

  local target_groups
  target_groups=$(aws elbv2 describe-target-groups \
    --region "$AWS_REGION" \
    --query 'TargetGroups[].TargetGroupArn' \
    --output json | jq -r '.[]') || target_groups=""

  if [[ -z "$target_groups" ]]; then
    log_success "✓ No target groups found"
    return
  fi

  for tg_arn in $target_groups; do
    local tags
    tags=$(aws elbv2 describe-tags \
      --resource-arns "$tg_arn" \
      --region "$AWS_REGION" \
      --query 'TagDescriptions[0].Tags' \
      --output json 2>/dev/null || echo "[]")

    if should_match_project_tag "$tags"; then
      local tg_name
      tg_name=$(aws elbv2 describe-target-groups \
        --target-group-arns "$tg_arn" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupName' \
        --output text)
      log_resource_found "Target Group: $tg_name (ARN: $tg_arn)"
    fi
  done
}

verify_nat_gateways() {
  log_section "Checking NAT Gateways"

  local nat_gateways
  # shellcheck disable=SC2016
  nat_gateways=$(aws ec2 describe-nat-gateways \
    --region "$AWS_REGION" \
    --filter "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'NatGateways[?State!=`deleted`].[NatGatewayId,State]' \
    --output json | jq -r '.[] | @tsv') || nat_gateways=""

  if [[ -z "$nat_gateways" ]]; then
    log_success "✓ No NAT gateways found"
    return
  fi

  while IFS=$'\t' read -r nat_id state; do
    log_resource_found "NAT Gateway: $nat_id (State: $state)"
  done <<<"$nat_gateways"
}

verify_elastic_ips() {
  log_section "Checking Elastic IPs"

  local eips
  eips=$(aws ec2 describe-addresses \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'Addresses[].AllocationId' \
    --output json | jq -r '.[]') || eips=""

  if [[ -z "$eips" ]]; then
    log_success "✓ No Elastic IPs found"
    return
  fi

  while read -r eip; do
    [[ -n "$eip" ]] && log_resource_found "Elastic IP Allocation: $eip"
  done <<<"$eips"
}

verify_vpcs() {
  log_section "Checking VPCs"

  local vpcs
  vpcs=$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'Vpcs[].VpcId' \
    --output json | jq -r '.[]') || vpcs=""

  if [[ -z "$vpcs" ]]; then
    log_success "✓ No VPCs found"
    return
  fi

  while read -r vpc; do
    [[ -n "$vpc" ]] && log_resource_found "VPC: $vpc"
  done <<<"$vpcs"
}

# ============================================================================
# Main
# ============================================================================

main() {
  check_prerequisites
  validate_aws_account

  verify_eks_clusters
  verify_ec2_instances
  verify_load_balancers
  verify_target_groups
  verify_nat_gateways
  verify_elastic_ips
  verify_vpcs

  echo ""
  if [[ "$RESOURCES_FOUND" == "true" ]]; then
    log_warning "One or more resources associated with $PROJECT_TAG_KEY=$PROJECT_TAG_VALUE are still present."
    exit 1
  fi

  log_success "All checks passed. No tracked resources remain."
  exit 0
}

main "$@"
