#!/usr/bin/env bash
#
# Shared helpers for platform-level AWS cleanup/inventory/verify scripts.
#
# IMPORTANT:
# - This file is ONLY for:
#     - platform/scripts/aws-nuclear-cleanup.sh
#     - platform/scripts/aws-resource-inventory.sh
#     - platform/scripts/verify-cleanup.sh
# - It MUST NOT be sourced by CI workflows or other scripts without explicit review
#   to avoid unintended coupling or breaking GitHub Actions behavior.
#
# This file is intentionally self-contained and safe to source from:
# - The repository root via: source "platform/scripts/aws-cleanup-common.sh"
# - A sibling script via:   source "$(dirname "$0")/aws-cleanup-common.sh"
#
set -euo pipefail

# Guard against multiple sourcing
if [[ -n "${AWS_CLEANUP_COMMON_SH_INCLUDED:-}" ]]; then
  return 0
fi
AWS_CLEANUP_COMMON_SH_INCLUDED=true

# -----------------------------------------------------------------------------
# AWS account / region / tagging configuration (shared, read-only)
# -----------------------------------------------------------------------------

# Exported for compatibility with existing scripts (they already rely on this).
export AWS_PROFILE="${AWS_PROFILE:-kodekloud}"

# Expected KodeKloud sandbox account ID (do not change without coordinated review).
readonly EXPECTED_ACCOUNT_ID="984479408136"

# Default region resolution:
# - Use existing AWS_REGION if set
# - Otherwise default to us-west-2 (as in existing scripts)
if [[ -z "${AWS_REGION:-}" ]]; then
  AWS_REGION="us-west-2"
fi
export AWS_REGION

# Shared tag scoping for project resources
readonly PROJECT_TAG_KEY="Project"
readonly PROJECT_TAG_VALUE="ml-platform-engineering-practicum"

# -----------------------------------------------------------------------------
# Logging helpers (mirrors existing behavior used in cleanup scripts)
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

log_section() {
  # Style chosen to be compatible with all three scripts.
  echo ""
  echo -e "${MAGENTA}=== $* ===${NC}"
}

# For verify-cleanup: mark when resources are found while preserving semantics.
# Scripts may choose to set/initialize RESOURCES_FOUND themselves.
log_resource_found() {
  echo -e "${MAGENTA}[FOUND]${NC} $*"
  RESOURCES_FOUND=true
}

# -----------------------------------------------------------------------------
# Safety / preflight helpers
# -----------------------------------------------------------------------------

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
    log_error "This helper is hardcoded to only run against the KodeKloud sandbox account."
    log_error "Exiting to prevent accidental operations in wrong account."
    exit 1
  fi

  log_success "✅ Correct AWS account verified: $account_id (KodeKloud sandbox)"
}

# -----------------------------------------------------------------------------
# Tag helpers
# -----------------------------------------------------------------------------

# Returns 0 if the given tags JSON/text contains the expected project tag.
should_match_project_tag() {
  local tags_json=${1:-}

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

# Returns 0 if resource should be included in inventory based on project tag.
should_include_tagged_resource() {
  should_match_project_tag "${1:-}"
}

# Returns 0 if resource should be deleted (same condition as include).
should_delete_tagged_resource() {
  should_match_project_tag "${1:-}"
}

# -----------------------------------------------------------------------------
# Deletion helper (used by aws-nuclear-cleanup.sh)
# -----------------------------------------------------------------------------

# delete_or_preview "description" command...
# Uses DRY_RUN flag when defined by the caller script.
delete_or_preview() {
  local description=$1
  shift || true

  # Default DRY_RUN to false if not set by caller script
  local dry_run="${DRY_RUN:-false}"

  if [[ "$dry_run" == "true" ]]; then
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

# ... existing code ...
