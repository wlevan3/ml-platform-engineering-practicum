#!/bin/bash
#
# validate-destroy.sh - Terraform Destroy Plan Validator
#
# Validates a Terraform destroy plan before execution.
# Shows exactly what will be deleted, validates against critical resources,
# and provides human-readable analysis.
#
# Usage:
#   terraform plan -destroy -out=tfplan
#   ./scripts/validate-destroy.sh tfplan
#
# The script analyzes the plan and fails if:
#   - No plan file provided
#   - Plan file doesn't exist
#   - Plan is NOT a destroy plan (detects accidental plan reuse)
#   - Plan includes deletion of critical data-storage resources
#   - Plan is empty or unreadable
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# Configuration
PLAN_FILE="${1:-}"
TEMP_JSON=$(mktemp)
TEMP_ANALYSIS=$(mktemp)

# Cleanup on exit
cleanup() {
  rm -f "$TEMP_JSON" "$TEMP_ANALYSIS"
}
trap cleanup EXIT

# ============================================================================
# VALIDATION FUNCTIONS
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

# ============================================================================
# MAIN VALIDATION
# ============================================================================

print_header "Terraform Destroy Plan Validator"

# Check if plan file provided
if [ -z "$PLAN_FILE" ]; then
  print_error "No plan file provided"
  echo ""
  echo "Usage: $0 <plan_file>"
  echo "Example:"
  echo "  terraform plan -destroy -out=tfplan"
  echo "  $0 tfplan"
  exit 1
fi

# Check if plan file exists
if [ ! -f "$PLAN_FILE" ]; then
  print_error "Plan file not found: $PLAN_FILE"
  exit 1
fi

print_success "Plan file found: $PLAN_FILE"

# Convert plan to JSON
print_section "Converting plan to JSON format"
if ! terraform show -json "$PLAN_FILE" > "$TEMP_JSON" 2>/dev/null; then
  print_error "Failed to read plan file (may not be a valid Terraform plan)"
  exit 1
fi

# Verify plan is valid JSON
if ! jq empty "$TEMP_JSON" 2>/dev/null; then
  print_error "Plan is not valid JSON"
  exit 1
fi

print_success "Plan is valid Terraform format"

# ============================================================================
# ANALYZE PLAN CONTENTS
# ============================================================================

print_section "Analyzing plan contents"

# Extract plan metadata
RESOURCE_CHANGES=$(jq '.resource_changes | length' "$TEMP_JSON")
TOTAL_CHANGES=$(jq '[.resource_changes[] | .change.actions[]] | length' "$TEMP_JSON")

# Count by action using jq's index() to handle multi-action resources
CREATES=$(jq '[.resource_changes[] | select(.change.actions | index("create"))] | length' "$TEMP_JSON")
UPDATES=$(jq '[.resource_changes[] | select(.change.actions | index("update"))] | length' "$TEMP_JSON")
DELETES=$(jq '[.resource_changes[] | select(.change.actions | index("delete"))] | length' "$TEMP_JSON")
REPLACES=$(jq '[.resource_changes[] | select(.change.actions[] | length > 1)] | length' "$TEMP_JSON")

echo ""
echo "Resource Changes Summary:"
echo "  Total resources with changes: $RESOURCE_CHANGES"
echo "  Total actions: $TOTAL_CHANGES"
echo ""
echo "  Create: $CREATES"
echo "  Update: $UPDATES"
echo "  Delete: $DELETES"
echo "  Replace: $REPLACES"

# Check if this is actually a destroy plan
if [ "$DELETES" -eq 0 ] && [ "$CREATES" -eq 0 ] && [ "$UPDATES" -eq 0 ]; then
  print_warning "Plan is empty (no changes)"
  exit 0
fi

if [ "$DELETES" -eq 0 ]; then
  print_warning "Plan has no deletions - this doesn't look like a destroy plan!"
  print_warning "Are you sure you ran: terraform plan -destroy -out=tfplan"
  echo ""
  echo "Found instead:"
  if [ "$CREATES" -gt 0 ]; then
    echo "  - $CREATES resources to CREATE"
  fi
  if [ "$UPDATES" -gt 0 ]; then
    echo "  - $UPDATES resources to UPDATE"
  fi
  exit 1
fi

print_success "Destroy plan detected ($DELETES deletions)"

# ============================================================================
# DETAILED RESOURCE ANALYSIS
# ============================================================================

print_section "Resources to be DELETED"

# Extract deleted resources
jq -r '.resource_changes[] | select(.change.actions[] == "delete") | "\(.type) \(.name)"' "$TEMP_JSON" | sort > "$TEMP_ANALYSIS"

# Count by resource type
RESOURCE_TYPES=$(jq -r '.resource_changes[] | select(.change.actions[] == "delete") | .type' "$TEMP_JSON" | sort | uniq -c | sort -rn)

echo ""
echo "Breakdown by resource type:"
echo "$RESOURCE_TYPES" | while read -r count type; do
  printf "  %3d × %s\n" "$count" "$type"
done

# Show full list
echo ""
echo "Full list of resources to delete:"
jq -r '.resource_changes[] | select(.change.actions[] == "delete") | "  - \(.type).\(.name)"' "$TEMP_JSON" | sort

# ============================================================================
# SAFETY CHECKS
# ============================================================================

print_section "Safety checks"

# Check 1: Data-storage resources (RDS, DynamoDB)
STORAGE_DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete" and (.type | test("rds|dynamodb|elasticsearch|elasticache|redshift")))] | length' "$TEMP_JSON")

if [ "$STORAGE_DELETES" -gt 0 ]; then
  print_error "Plan includes deletion of data-storage resources!"
  jq -r '.resource_changes[] | select(.change.actions[] == "delete" and (.type | test("rds|dynamodb|elasticsearch|elasticache|redshift"))) | "   - \(.type).\(.name)"' "$TEMP_JSON"
  echo ""
  print_error "This is likely a MISTAKE. Data-storage deletions should be intentional."
  echo ""
  echo "⚠️  Double-check:"
  echo "   1. Is this really a destroy-all plan?"
  echo "   2. Have you backed up databases?"
  echo "   3. Are you sure about this?"
  exit 1
fi

print_success "No data-storage resources in deletion list"

# Check 2: Production-like resources (rds-prod, prod-, -prod, production)
PROD_DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete" and (.address | test("(?i)prod|production|prd")))] | length' "$TEMP_JSON")

if [ "$PROD_DELETES" -gt 0 ]; then
  print_warning "Plan includes resources that look like production!"
  jq -r '.resource_changes[] | select(.change.actions[] == "delete" and (.address | test("(?i)prod|production|prd"))) | "   - \(.address)"' "$TEMP_JSON"
  echo ""
  print_warning "Verify this is intentional before proceeding"
fi

# Check 3: Validate against environment
CURRENT_ENV=$(terraform workspace show 2>/dev/null || echo "default")
print_success "Current Terraform workspace: $CURRENT_ENV"

# ============================================================================
# ESTIMATED IMPACT
# ============================================================================

print_section "Estimated impact"

# Estimate costs (basic heuristic)
EKS_DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete" and (.type == "aws_eks_cluster"))] | length' "$TEMP_JSON")
EC2_DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete" and (.type | contains("instance")))] | length' "$TEMP_JSON")
RDS_DELETES=$(jq '[.resource_changes[] | select(.change.actions[] == "delete" and (.type | contains("rds")))] | length' "$TEMP_JSON")

echo ""
echo "Potential cost savings:"
if [ "$EKS_DELETES" -gt 0 ]; then
  echo "  • EKS clusters: ~\$0.10/hour (~\$72/month each)"
fi
if [ "$EC2_DELETES" -gt 0 ]; then
  echo "  • EC2 instances: ~\$0.02-0.10/hour each"
fi
if [ "$RDS_DELETES" -gt 0 ]; then
  echo "  • RDS databases: ~\$0.10-1.00+/hour each"
fi

# ============================================================================
# BEFORE/AFTER COMPARISON
# ============================================================================

print_section "State before/after"

# Current state count
CURRENT_STATE=$(terraform state list 2>/dev/null | wc -l || echo "unknown")
FUTURE_STATE=$((CURRENT_STATE - DELETES))

echo ""
echo "Terraform state:"
echo "  Before: ~$CURRENT_STATE resources"
echo "  After:  ~$FUTURE_STATE resources"
echo "  Deleted: $DELETES"

if [ "$FUTURE_STATE" -lt 0 ]; then
  print_warning "Expected future state is negative (possible counting error)"
fi

# ============================================================================
# VALIDATION SUMMARY
# ============================================================================

print_section "Validation summary"

echo ""
echo "Plan Analysis:"
echo "  ✓ Valid Terraform plan"
echo "  ✓ Is a destroy plan ($DELETES deletions)"
echo "  ✓ No data-storage resources in deletion list"
if [ "$PROD_DELETES" -eq 0 ]; then
  echo "  ✓ No production-looking resources"
fi
echo ""

# ============================================================================
# FINAL RECOMMENDATIONS
# ============================================================================

print_section "Before proceeding with terraform destroy"

echo ""
echo "Checklist:"
echo "  [ ] I have reviewed all resources above"
echo "  [ ] I understand what will be deleted"
echo "  [ ] I have backed up critical data"
echo "  [ ] I have verified the correct AWS account"
echo "  [ ] I understand this cannot be undone (state recovery only)"
echo ""

# ============================================================================
# SUCCESS
# ============================================================================

print_success "Destroy plan validation PASSED"
echo ""
echo "To proceed with destruction:"
echo "  terraform apply <plan_file>"
echo ""
echo "To view the plan again:"
echo "  terraform show $PLAN_FILE"
echo ""

exit 0
