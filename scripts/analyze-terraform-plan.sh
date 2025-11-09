#!/bin/bash
#
# analyze-terraform-plan.sh - Terraform Plan Analysis for PRs
#
# Analyzes a Terraform plan JSON output to detect destructive changes
# and provide warnings/rejections based on configurable thresholds.
#
# Usage:
#   terraform plan -out=tfplan
#   terraform show -json tfplan > plan.json
#   ./scripts/analyze-terraform-plan.sh plan.json
#
# Environment Variables:
#   PLAN_FILE - Path to the JSON plan file (default: plan.json)
#   CRITICAL_FAILURE - Set to "false" to convert critical failures to warnings (default: true)
#
# Exits:
#   0 - Success (no critical issues)
#   1 - Plan analysis failed (invalid JSON, missing file)
#   2 - Critical resource deletions detected (if CRITICAL_FAILURE=true)
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# Configuration
PLAN_FILE="${PLAN_FILE:-plan.json}"
CRITICAL_FAILURE="${CRITICAL_FAILURE:-true}"
TEMP_ANALYSIS=$(mktemp)

# Cleanup on exit
cleanup() {
  rm -f "$TEMP_ANALYSIS"
}
trap cleanup EXIT

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
  local title=$1
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}$title${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

print_section() {
  local title=$1
  echo ""
  echo -e "${BLUE}■ $title${NC}"
}

print_success() {
  local msg=$1
  echo -e "${GREEN}✅ $msg${NC}"
}

print_warning() {
  local msg=$1
  echo -e "${YELLOW}⚠️  $msg${NC}"
}

print_error() {
  local msg=$1
  echo -e "${RED}❌ $msg${NC}"
}

# Set GitHub Actions output
gha_output() {
  local key=$1
  local value=$2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "$key=$value" >> "$GITHUB_OUTPUT"
  fi
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_inputs() {
  print_header "Terraform Plan Analysis for PRs"

  # Check if plan file exists
  if [ ! -f "$PLAN_FILE" ]; then
    print_error "Plan file not found: $PLAN_FILE"
    echo ""
    echo "Usage: $0 [plan_file]"
    echo "Make sure to run: terraform show -json tfplan > plan.json"
    exit 1
  fi

  # Verify plan is valid JSON
  if ! jq empty "$PLAN_FILE" 2>/dev/null; then
    print_error "Plan file is not valid JSON"
    exit 1
  fi

  print_success "Plan file found and valid: $PLAN_FILE"
}

# ============================================================================
# ANALYSIS FUNCTIONS
# ============================================================================

analyze_plan_structure() {
  print_section "Analyzing plan structure"

  # Extract plan metadata
  RESOURCE_CHANGES=$(jq '.resource_changes | length' "$PLAN_FILE")
  TOTAL_CHANGES=$(jq '[.resource_changes[] | .change.actions[]] | length' "$PLAN_FILE")

  # Initialize GitHub Actions outputs
  gha_output "total_changes" "$RESOURCE_CHANGES"
  gha_output "has_changes" "$([ "$RESOURCE_CHANGES" -gt 0 ] && echo "true" || echo "false")"

  echo "Resource Changes Summary:"
  echo "  Total resources with changes: $RESOURCE_CHANGES"
  echo "  Total actions: $TOTAL_CHANGES"

  # Check if plan is empty
  if [ "$RESOURCE_CHANGES" -eq 0 ]; then
    echo ""
    print_success "No changes detected"
    gha_output "analysis_complete" "true"
    exit 0
  fi
}

analyze_change_types() {
  print_section "Analyzing change types"

  # Count by action type
  CREATES=$(jq '[.resource_changes[] | select(.change.actions[] == "create")] | length' "$PLAN_FILE")
  UPDATES=$(jq '[.resource_changes[] | select(.change.actions[] == "update")] | length' "$PLAN_FILE")
  DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete")] | length' "$PLAN_FILE")
  REPLACES=$(jq '[.resource_changes[] | select(.change.actions | contains(["delete", "create"]))] | length' "$PLAN_FILE")

  # Set GitHub Actions outputs
  gha_output "creates" "$CREATES"
  gha_output "updates" "$UPDATES"
  gha_output "deletions" "$DELETES"
  gha_output "replacements" "$REPLACES"
  gha_output "has_deletions" "$([ "$DELETES" -gt 0 ] && echo "true" || echo "false")"
  gha_output "has_replacements" "$([ "$REPLACES" -gt 0 ] && echo "true" || echo "false")"

  echo ""
  echo "Change Type Breakdown:"
  echo "  Create: $CREATES"
  echo "  Update: $UPDATES"
  echo "  Delete: $DELETES"
  echo "  Replace: $REPLACES"

  # Large changes warning (>10 resources)
  if [ "$RESOURCE_CHANGES" -gt 10 ]; then
    echo ""
    print_warning "Large-scale change detected: $RESOURCE_CHANGES resources (threshold: 10)"
    gha_output "large_changes_warning" "true"
    gha_output "large_changes_count" "$RESOURCE_CHANGES"
  else
    gha_output "large_changes_warning" "false"
  fi
}

analyze_deletions() {
  if [ "$DELETES" -eq 0 ]; then
    gha_output "deletions_list" ""
    return 0
  fi

  print_section "Resource deletions analysis"

  # Extract deleted resources for listing
  jq -r '.resource_changes[] | select(.change.actions[] == "delete") | .address' "$PLAN_FILE" | sort > "$TEMP_ANALYSIS"

  local deletions_list
  deletions_list=$(paste -sd "," "$TEMP_ANALYSIS")
  gha_output "deletions_list" "$deletions_list"

  echo ""
  echo "Resources to be deleted:"
  while IFS= read -r resource; do
    echo "  - $resource"
  done < "$TEMP_ANALYSIS"

  echo ""
  print_warning "Plan includes $DELETES deletion(s) - review carefully"
}

analyze_critical_resources() {
  if [ "$DELETES" -eq 0 ]; then
    gha_output "has_critical_deletions" "false"
    gha_output "critical_deletions_list" ""
    return 0
  fi

  print_section "Critical resource safety checks"

  # Define critical resource patterns
  # EKS clusters, RDS instances, S3 buckets (production ones)
  local critical_patterns="aws_eks_cluster|aws_rds_instance|aws_s3_bucket"

  # Find critical resource deletions
  local critical_deletes
  critical_deletes=$(jq --arg pattern "$critical_patterns" '[.resource_changes[] | select(.change.actions[] == "delete") | select(.type | test($pattern))] | length' "$PLAN_FILE")

  gha_output "critical_deletions_count" "$critical_deletes"

  if [ "$critical_deletes" -gt 0 ]; then
    # Extract critical resource addresses
    local critical_list
    critical_list=$(jq -r --arg pattern "$critical_patterns" '.resource_changes[] | select(.change.actions[] == "delete") | select(.type | test($pattern)) | .address' "$PLAN_FILE" | paste -sd "," -)
    gha_output "critical_deletions_list" "$critical_list"
    gha_output "has_critical_deletions" "true"

    echo ""
    print_error "CRITICAL: Plan deletes $critical_deletes critical resources!"

    jq -r --arg pattern "$critical_patterns" '.resource_changes[] | select(.change.actions[] == "delete") | select(.type | test($pattern)) | "   - \(.address)"' "$PLAN_FILE"

    echo ""
    echo "🚨 This is usually a MISTAKE. Critical infrastructure deletions should:"
    echo "   1. Be intentional and well-planned"
    echo "   2. Have proper backups and migration plans"
    echo "   3. Be reviewed by multiple team members"
    echo "   4. Consider Geschäftskontinuität (business continuity)"

    if [ "$CRITICAL_FAILURE" = "true" ]; then
      echo ""
      print_error "Workflow FAILED due to critical resource deletions"
      exit 2
    else
      echo ""
      print_warning "CRITICAL_FAILURE=false - treating as warning instead of failure"
    fi
  else
    print_success "No critical resource deletions detected"
    gha_output "has_critical_deletions" "false"
    gha_output "critical_deletions_list" ""
  fi
}

analyze_production_resources() {
  if [ "$DELETES" -eq 0 ]; then
    return 0
  fi

  print_section "Production-like resource checks"

  # Check for production-like resources
  local prod_deletes
  prod_deletes=$(jq '[.resource_changes[] | select(.change.actions[] == "delete") | select(.address | test("(?i)prod|production|prd"))] | length' "$PLAN_FILE")

  if [ "$prod_deletes" -gt 0 ]; then
    echo ""
    print_warning "Plan includes resources that look like production!"
    echo ""
    jq -r '.resource_changes[] | select(.change.actions[] == "delete") | select(.address | test("(?i)prod|production|prd"))) | "   - \(.address)"' "$PLAN_FILE"
    echo ""
    print_warning "⚠️  Verify this is intentional before proceeding"
    gha_output "has_production_deletions" "true"
  else
    gha_output "has_production_deletions" "false"
  fi
}

generate_summary() {
  print_section "Analysis summary"

  echo ""
  echo "📊 Plan Analysis Complete:"
  echo "  ✅ Valid Terraform plan"
  echo "  📈 $RESOURCE_CHANGES resources changed"
  echo "  📝 $CREATES create operations"
  echo "  🔄 $UPDATES update operations"
  echo "  🗑️  $DELETES delete operations"
  echo "  🔄 $REPLACES replace operations"

  if [ "$DELETES" -gt 0 ]; then
    echo "  ⚠️  Deletions detected - review required"
  fi

  if [ "$RESOURCE_CHANGES" -gt 10 ]; then
    echo "  ⚠️  Large-scale change ($RESOURCE_CHANGES resources)"
  fi

  if [ "${has_critical_deletions:-false}" = "true" ]; then
    echo "  ❌ Critical resource deletions detected"
  fi

  echo ""
  print_success "Plan analysis completed successfully"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  # Run analysis pipeline
  validate_inputs
  analyze_plan_structure
  analyze_change_types
  analyze_deletions
  analyze_critical_resources
  analyze_production_resources
  generate_summary

  # Set final outputs
  gha_output "analysis_complete" "true"
  gha_output "analysis_status" "success"
}

# Execute if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
