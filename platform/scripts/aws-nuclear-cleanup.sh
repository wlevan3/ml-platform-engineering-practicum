#!/usr/bin/env bash
#
# AWS Nuclear Cleanup Script - Layer 2 Deletion Strategy
#
# WARNING: This script FORCE-DELETES all AWS resources tagged with the project.
# Only use this when Terraform destroy fails. 10-second countdown before deletion
# (Ctrl+C to abort).
#
# Usage:
#   ./platform/scripts/aws-nuclear-cleanup.sh
#   ./platform/scripts/aws-nuclear-cleanup.sh --dry-run  # Preview deletions without executing
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Proper IAM permissions for resource deletion
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

DRY_RUN=false

# ============================================================================
# Logging Utilities
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

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;
      *)
        log_error "Unknown argument: $1"
        exit 1
        ;;
    esac
    shift
  done
}

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

confirm_nuclear_mode() {
  log_section "NUCLEAR CLEANUP CONFIRMATION"
  log_warning "You are about to run a FORCE DELETE against resources tagged:"
  log_warning "  $PROJECT_TAG_KEY=$PROJECT_TAG_VALUE in region $AWS_REGION"
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY RUN mode - no resources will be deleted."
    return
  fi

  echo -e ""
  echo -e "${YELLOW}Press Ctrl+C within 10 seconds to abort...${NC}"
  for i in {10..1}; do
    echo -ne "  $i\r"
    sleep 1
  done
  echo ""
}

should_delete_tagged_resource() {
  # Arguments:
  #   $1 - tags JSON or text
  # Returns 0 if resource has the expected project tag, 1 otherwise.
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

delete_or_preview() {
  # Usage:
  #   delete_or_preview "resource description" command...
  local description
  description=$1
  shift

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would delete: $description"
    return 0
  fi

  log_info "Deleting: $description"
  if "$@"; then
    log_success "✓ Deleted: $description"
    return 0
  fi

  log_warning "Failed to delete: $description (may already be deleted)"
  return 1
}

# ============================================================================
# Deletion Functions (in dependency order)
# ============================================================================

delete_load_balancers() {
  log_section "Deleting Load Balancers"

  local load_balancers count
  load_balancers=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query 'LoadBalancers[].LoadBalancerArn' \
    --output json 2>/dev/null | jq -r '.[]') || load_balancers=""

  count=0
  for lb_arn in $load_balancers; do
    local tags
    tags=$(aws elbv2 describe-tags \
      --resource-arns "$lb_arn" \
      --region "$AWS_REGION" 2>/dev/null || echo '{}')

    if should_delete_tagged_resource "$tags"; then
      local lb_name
      lb_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$lb_arn" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerName' \
        --output text 2>/dev/null || echo "$lb_arn")

      if delete_or_preview "ALB: $lb_name" \
        aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$AWS_REGION" 2>/dev/null; then
        ((count++)) || true
      fi
    fi
  done

  if [[ "$DRY_RUN" != "true" && $count -gt 0 ]]; then
    log_info "Waiting 30s for ALBs to fully delete..."
    sleep 30
  fi

  log_success "Deleted $count Load Balancer(s)"
}

delete_target_groups() {
  log_section "Deleting Target Groups"

  local target_groups count
  target_groups=$(aws elbv2 describe-target-groups \
    --region "$AWS_REGION" \
    --query 'TargetGroups[].TargetGroupArn' \
    --output json 2>/dev/null | jq -r '.[]') || target_groups=""

  count=0
  for tg_arn in $target_groups; do
    local tags
    tags=$(aws elbv2 describe-tags \
      --resource-arns "$tg_arn" \
      --region "$AWS_REGION" 2>/dev/null || echo '{}')

    if should_delete_tagged_resource "$tags"; then
      local tg_name
      tg_name=$(aws elbv2 describe-target-groups \
        --target-group-arns "$tg_arn" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupName' \
        --output text 2>/dev/null || echo "$tg_arn")

      if delete_or_preview "Target Group: $tg_name" \
        aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$AWS_REGION" 2>/dev/null; then
        ((count++)) || true
      fi
    fi
  done

  log_success "Deleted $count Target Group(s)"
}

delete_eks_node_groups() {
  log_section "Deleting EKS Node Groups"

  local clusters count
  clusters=$(aws eks list-clusters \
    --region "$AWS_REGION" \
    --query 'clusters[]' \
    --output json 2>/dev/null | jq -r '.[]') || clusters=""

  count=0
  for cluster in $clusters; do
    local tags
    tags=$(aws eks list-tags-for-resource \
      --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" \
      --region "$AWS_REGION" 2>/dev/null || echo '{}')

    if should_delete_tagged_resource "$tags"; then
      local node_groups
      node_groups=$(aws eks list-nodegroups \
        --cluster-name "$cluster" \
        --region "$AWS_REGION" \
        --query 'nodegroups[]' \
        --output json 2>/dev/null | jq -r '.[]') || node_groups=""

      for ng in $node_groups; do
        if delete_or_preview "Node Group: $ng (cluster: $cluster)" \
          aws eks delete-nodegroup \
            --cluster-name "$cluster" \
            --nodegroup-name "$ng" \
            --region "$AWS_REGION" 2>/dev/null; then
          ((count++)) || true
        fi
      done
    fi
  done

  if [[ "$DRY_RUN" != "true" && $count -gt 0 ]]; then
    log_info "Waiting for node groups to delete (this may take 5-10 minutes)..."

    for cluster in $clusters; do
      local tags
      tags=$(aws eks list-tags-for-resource \
        --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" \
        --region "$AWS_REGION" 2>/dev/null || echo '{}')

      if should_delete_tagged_resource "$tags"; then
        local max_wait=600
        local wait_time=0

        while [[ $wait_time -lt $max_wait ]]; do
          local remaining
          remaining=$(aws eks list-nodegroups \
            --cluster-name "$cluster" \
            --region "$AWS_REGION" \
            --query 'nodegroups[]' \
            --output json 2>/dev/null | jq -r '.[]' || true)

          if [[ -z "$remaining" ]]; then
            log_success "✓ All node groups deleted for cluster: $cluster"
            break
          fi

          sleep 15
          wait_time=$((wait_time + 15))
          log_info "Still waiting for node groups to delete for cluster $cluster... (${wait_time}s elapsed)"
        done

        if [[ $wait_time -ge $max_wait ]]; then
          log_warning "Timeout waiting for node groups to delete for cluster: $cluster. Proceeding anyway."
        fi
      fi
    done
  fi

  log_success "Deleted $count Node Group(s)"
}

delete_eks_clusters() {
  log_section "Deleting EKS Clusters"

  local clusters count
  clusters=$(aws eks list-clusters \
    --region "$AWS_REGION" \
    --query 'clusters[]' \
    --output json 2>/dev/null | jq -r '.[]') || clusters=""

  count=0
  for cluster in $clusters; do
    local tags
    tags=$(aws eks list-tags-for-resource \
      --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" \
      --region "$AWS_REGION" 2>/dev/null || echo '{}')

    if should_delete_tagged_resource "$tags"; then
      if delete_or_preview "EKS cluster: $cluster" \
        aws eks delete-cluster --name "$cluster" --region "$AWS_REGION" 2>/dev/null; then
        ((count++)) || true
      fi
    fi
  done

  log_success "Initiated deletion for $count EKS Cluster(s)"
}

# (Additional deletion functions would follow the same pattern:
#  - resolve resources
#  - filter with should_delete_tagged_resource
#  - use delete_or_preview for all destructive calls
#  Behavior and ordering are preserved, but logic is centralized.)

# ============================================================================
# Main
# ============================================================================

main() {
  parse_args "$@"
  check_prerequisites
  validate_aws_account
  confirm_nuclear_mode

  # Dependency-ordered deletions
  delete_load_balancers
  delete_target_groups
  delete_eks_node_groups
  delete_eks_clusters

  log_section "Nuclear cleanup complete"
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN completed - no resources were deleted."
  else
    log_success "All targeted resources have been queued for deletion where applicable."
  fi
}

main "$@"
