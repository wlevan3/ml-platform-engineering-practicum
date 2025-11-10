#!/usr/bin/env bash
#
# AWS Resource Inventory Script
#
# Tracks all AWS resources created by this project for cost monitoring and cleanup verification.
# Uses project tags to identify resources and supports baseline/diff/verification modes.
#
# Usage:
#   ./platform/scripts/aws-resource-inventory.sh                    # Display current inventory
#   ./platform/scripts/aws-resource-inventory.sh --export file.json # Export to JSON
#   ./platform/scripts/aws-resource-inventory.sh --diff before.json # Compare against baseline
#   ./platform/scripts/aws-resource-inventory.sh --verify-empty     # Verify zero resources (exit 1 if any remain)
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - jq installed (brew install jq)
#
set -euo pipefail

# ============================================================================
# AWS PROFILE / ACCOUNT SAFETY GUARDRAILS (SAFE TO COMMIT)
# ============================================================================

export AWS_PROFILE="kodekloud"
readonly EXPECTED_ACCOUNT_ID="984479408136"

AWS_REGION="${AWS_REGION:-us-west-2}"
readonly PROJECT_TAG_KEY="Project"
readonly PROJECT_TAG_VALUE="ml-platform-engineering-practicum"

# ============================================================================
# Logging Utilities (aligned with aws-nuclear-cleanup.sh)
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

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
  echo -e "\n${MAGENTA}=== $1 ===${NC}"
}

# ============================================================================
# Common Safety / Preflight Helpers
# ============================================================================

check_prerequisites() {
  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI not found. Install: macOS: 'brew install awscli' | Ubuntu: 'apt-get install awscli'"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq not found. Install: macOS: 'brew install jq' | Ubuntu: 'apt-get install jq'"
    exit 1
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured or invalid"
    exit 1
  fi
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
}

should_include_tagged_resource() {
  # Returns 0 if the given JSON/text contains the expected project tag, 1 otherwise.
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
# Resource Discovery Helpers
# ============================================================================

get_eks_clusters() {
  local clusters tagged_clusters
  clusters=$(aws eks list-clusters --region "$AWS_REGION" \
    --query 'clusters[]' --output json 2>/dev/null | jq -r '.[]') || clusters=""

  tagged_clusters=()
  for cluster in $clusters; do
    local tags
    tags=$(aws eks list-tags-for-resource \
      --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" \
      --region "$AWS_REGION" 2>/dev/null || echo '{}')

    if should_include_tagged_resource "$tags"; then
      tagged_clusters+=("$cluster")
    fi
  done

  printf '%s\n' "${tagged_clusters[@]}"
}

get_ec2_instances() {
  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
              "Name=instance-state-name,Values=running,stopped,stopping,pending" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output json 2>/dev/null | jq -r '.[]'
}

get_vpcs() {
  aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'Vpcs[].VpcId' \
    --output json 2>/dev/null | jq -r '.[]'
}

get_nat_gateways() {
  aws ec2 describe-nat-gateways \
    --region "$AWS_REGION" \
    --filter "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
             "Name=state,Values=available,pending" \
    --query 'NatGateways[].NatGatewayId' \
    --output json 2>/dev/null | jq -r '.[]'
}

get_load_balancers() {
  aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query 'LoadBalancers[].LoadBalancerArn' \
    --output json 2>/dev/null | jq -r '.[]' | while read -r arn; do
      local tags
      tags=$(aws elbv2 describe-tags \
        --resource-arns "$arn" \
        --region "$AWS_REGION" 2>/dev/null || echo "[]")

      if should_include_tagged_resource "$tags"; then
        echo "$arn"
      fi
    done
}

get_ecr_repositories() {
  aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --query 'repositories[].repositoryName' \
    --output json 2>/dev/null | jq -r '.[]' | while read -r repo; do
      local tags
      tags=$(aws ecr list-tags-for-resource \
        --resource-arn "arn:aws:ecr:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):repository/$repo" \
        --region "$AWS_REGION" 2>/dev/null || echo "[]")

      if should_include_tagged_resource "$tags"; then
        echo "$repo"
      fi
    done
}

get_ebs_volumes() {
  aws ec2 describe-volumes \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'Volumes[].VolumeId' \
    --output json 2>/dev/null | jq -r '.[]'
}

get_elastic_ips() {
  aws ec2 describe-addresses \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'Addresses[].AllocationId' \
    --output json 2>/dev/null | jq -r '.[]'
}

get_security_groups() {
  # shellcheck disable=SC2016
  aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output json 2>/dev/null | jq -r '.[]'
}

get_s3_buckets() {
  aws s3api list-buckets \
    --query 'Buckets[].Name' \
    --output json 2>/dev/null | jq -r '.[]' | while read -r bucket; do
      local tags
      tags=$(aws s3api get-bucket-tagging --bucket "$bucket" 2>/dev/null || echo "{}")

      if should_include_tagged_resource "$tags"; then
        echo "$bucket"
      fi
    done
}

get_dynamodb_tables() {
  aws dynamodb list-tables \
    --region "$AWS_REGION" \
    --query 'TableNames[]' \
    --output json 2>/dev/null | jq -r '.[]' | while read -r table; do
      local tags
      tags=$(aws dynamodb list-tags-of-resource \
        --resource-arn "arn:aws:dynamodb:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):table/$table" \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")

      if should_include_tagged_resource "$tags"; then
        echo "$table"
      fi
    done
}

# ============================================================================
# Cost Estimation (unchanged behavior, comments retained)
# ============================================================================

calculate_costs() {
  local eks_clusters=$1
  local ec2_instances=$2
  local nat_gateways=$3
  local load_balancers=$4

  # AWS Pricing Documentation (us-west-2 region)
  # Last verified: November 2025
  #
  # Rates:
  # - EKS Control Plane: $0.10/hour per cluster
  #   Source: https://aws.amazon.com/eks/pricing/
  #   Note: Excludes EC2 node costs (included separately below)
  #
  # - EC2 t3.medium instances: $0.0416/hour (On-Demand pricing)
  #   Source: https://aws.amazon.com/ec2/pricing/on-demand/
  #   Note: Actual cost for us-west-2, excludes EBS storage
  #
  # - NAT Gateway: $0.045/hour per gateway
  #   Source: https://aws.amazon.com/vpc/pricing/
  #   Note: Excludes data processing charges ($0.045/GB)
  #
  # - Application Load Balancer (ALB): $0.0225/hour per LB
  #   Source: https://aws.amazon.com/elasticloadbalancing/pricing/
  #   Note: Excludes LCU charges (varies by traffic)
  #
  # Disclaimer: Estimates are rough approximations. Does not include:
  # - Data transfer costs
  # - EBS storage costs
  # - NAT Gateway data processing charges
  # - ALB LCU charges (based on traffic)
  # - S3, DynamoDB, ECR, or other service costs
  # Always verify actual costs via AWS Cost Explorer.

  local total_cost=0
  local eks_cost
  local ec2_cost
  local nat_cost
  local alb_cost

  # EKS control plane: $0.10/hour per cluster
  eks_cost=$(echo "$eks_clusters * 0.10" | bc -l)
  total_cost=$(echo "$total_cost + $eks_cost" | bc -l)

  # EC2 instances (t3.medium): ~$0.0416/hour
  ec2_cost=$(echo "$ec2_instances * 0.0416" | bc -l)
  total_cost=$(echo "$total_cost + $ec2_cost" | bc -l)

  # NAT Gateways: $0.045/hour
  nat_cost=$(echo "$nat_gateways * 0.045" | bc -l)
  total_cost=$(echo "$total_cost + $nat_cost" | bc -l)

  # Load Balancers: $0.0225/hour
  alb_cost=$(echo "$load_balancers * 0.0225" | bc -l)
  total_cost=$(echo "$total_cost + $alb_cost" | bc -l)

  echo "$total_cost"
}

# ============================================================================
# Main Inventory Logic (preserve existing CLI behavior)
# ============================================================================

main() {
  check_prerequisites
  validate_aws_account

  local export_file=""
  local diff_file=""
  local verify_empty=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --export)
        export_file="${2:-}"
        if [[ -z "$export_file" ]]; then
          log_error "--export requires a file path"
          exit 1
        fi
        shift 2
        ;;
      --diff)
        diff_file="${2:-}"
        if [[ -z "$diff_file" || ! -f "$diff_file" ]]; then
          log_error "--diff requires an existing baseline file"
          exit 1
        fi
        shift 2
        ;;
      --verify-empty)
        verify_empty=true
        shift
        ;;
      *)
        log_error "Unknown argument: $1"
        exit 1
        ;;
    esac
  done

  log_section "Collecting AWS resource inventory for tag $PROJECT_TAG_KEY=$PROJECT_TAG_VALUE"

  local eks_clusters ec2_instances vpcs nat_gateways lbs ecr_repos ebs_vols eips sgs s3_buckets ddb_tables

  eks_clusters=$(get_eks_clusters || true)
  ec2_instances=$(get_ec2_instances || true)
  vpcs=$(get_vpcs || true)
  nat_gateways=$(get_nat_gateways || true)
  lbs=$(get_load_balancers || true)
  ecr_repos=$(get_ecr_repositories || true)
  ebs_vols=$(get_ebs_volumes || true)
  eips=$(get_elastic_ips || true)
  sgs=$(get_security_groups || true)
  s3_buckets=$(get_s3_buckets || true)
  ddb_tables=$(get_dynamodb_tables || true)

  # Build JSON structure
  local inventory_json
  inventory_json=$(jq -n \
    --argjson eks_clusters "$(printf '%s\n' $eks_clusters | jq -R . | jq -s .)" \
    --argjson ec2_instances "$(printf '%s\n' $ec2_instances | jq -R . | jq -s .)" \
    --argjson vpcs "$(printf '%s\n' $vpcs | jq -R . | jq -s .)" \
    --argjson nat_gateways "$(printf '%s\n' $nat_gateways | jq -R . | jq -s .)" \
    --argjson load_balancers "$(printf '%s\n' $lbs | jq -R . | jq -s .)" \
    --argjson ecr_repositories "$(printf '%s\n' $ecr_repos | jq -R . | jq -s .)" \
    --argjson ebs_volumes "$(printf '%s\n' $ebs_vols | jq -R . | jq -s .)" \
    --argjson elastic_ips "$(printf '%s\n' $eips | jq -R . | jq -s .)" \
    --argjson security_groups "$(printf '%s\n' $sgs | jq -R . | jq -s .)" \
    --argjson s3_buckets "$(printf '%s\n' $s3_buckets | jq -R . | jq -s .)" \
    --argjson dynamodb_tables "$(printf '%s\n' $ddb_tables | jq -R . | jq -s .)" \
    '{
      eks_clusters: $eks_clusters,
      ec2_instances: $ec2_instances,
      vpcs: $vpcs,
      nat_gateways: $nat_gateways,
      load_balancers: $load_balancers,
      ecr_repositories: $ecr_repositories,
      ebs_volumes: $ebs_volumes,
      elastic_ips: $elastic_ips,
      security_groups: $security_groups,
      s3_buckets: $s3_buckets,
      dynamodb_tables: $dynamodb_tables
    }'
  )

  # Default: print inventory to stdout
  echo "$inventory_json" | jq

  # Export, if requested
  if [[ -n "$export_file" ]]; then
    echo "$inventory_json" >"$export_file"
    log_success "Exported inventory to $export_file"
  fi

  # Diff against baseline, if requested (behavior preserved: non-zero exit on differences)
  if [[ -n "$diff_file" ]]; then
    if ! jq -e . "$diff_file" >/dev/null 2>&1; then
      log_error "Baseline file '$diff_file' is not valid JSON"
      exit 1
    fi

    local diff
    diff=$(jq --slurp '.[0] as $a | .[1] as $b | if $a == $b then empty else {"baseline":$a,"current":$b} end' \
      "$diff_file" <(echo "$inventory_json"))

    if [[ -n "$diff" ]]; then
      log_warning "Inventory differs from baseline:"
      echo "$diff" | jq
      exit 1
    else
      log_success "Current inventory matches baseline"
    fi
  fi

  # Verify empty (no resources), if requested
  if [[ "$verify_empty" == "true" ]]; then
    if echo "$inventory_json" | jq -e '
      (.eks_clusters|length) == 0 and
      (.ec2_instances|length) == 0 and
      (.vpcs|length) == 0 and
      (.nat_gateways|length) == 0 and
      (.load_balancers|length) == 0 and
      (.ecr_repositories|length) == 0 and
      (.ebs_volumes|length) == 0 and
      (.elastic_ips|length) == 0 and
      (.security_groups|length) == 0 and
      (.s3_buckets|length) == 0 and
      (.dynamodb_tables|length) == 0
    ' >/dev/null; then
      log_success "All tracked resources have been cleaned up"
      exit 0
    else
      log_warning "Some tracked resources still exist"
      exit 1
    fi
  fi
}

main "$@"
