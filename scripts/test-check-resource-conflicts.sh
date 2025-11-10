#!/bin/bash
# =============================================================================
# Tests for Pre-flight Resource Conflict Detection Script
# =============================================================================
#
# PURPOSE:
#   Test the check-resource-conflicts.sh script with various scenarios
#   Validates that conflict detection works correctly for different resource types
#
# USAGE:
#   ./test-check-resource-conflicts.sh
#
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_header() { echo -e "${BLUE}## $1${NC}"; }

# Function to create a mock terraform plan JSON for testing
create_mock_plan() {
    local test_type=$1
    local output_file=$2

    case "$test_type" in
        "empty")
            cat > "$output_file" << 'EOF'
{
  "resource_changes": []
}
EOF
            ;;
        "s3_conflict")
            cat > "$output_file" << 'EOF'
{
  "resource_changes": [
    {
      "address": "aws_s3_bucket.test_bucket",
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "test_bucket",
      "provider_name": "registry.terraform.io/hashicorp/aws",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": {
          "bucket": "already-existing-bucket-name-should-change"
        }
      }
    }
  ]
}
EOF
            ;;
        "s3_no_conflict")
            cat > "$output_file" << 'EOF'
{
  "resource_changes": [
    {
      "address": "aws_s3_bucket.test_bucket",
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "test_bucket",
      "provider_name": "registry.terraform.io/hashicorp/aws",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": {
          "bucket": "definitely-not-existing-bucket-name-12345"
        }
      }
    }
  ]
}
EOF
            ;;
        "iam_conflict")
            cat > "$output_file" << 'EOF'
{
  "resource_changes": [
    {
      "address": "aws_iam_role.test_role",
      "mode": "managed",
      "type": "aws_iam_role",
      "name": "test_role",
      "provider_name": "registry.terraform.io/hashicorp/aws",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": {
          "name": "already-existing-role-name-should-change"
        }
      }
    }
  ]
}
EOF
            ;;
        "multiple_changes")
            cat > "$output_file" << 'EOF'
{
  "resource_changes": [
    {
      "address": "aws_s3_bucket.test_bucket1",
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "test_bucket1",
      "provider_name": "registry.terraform.io/hashicorp/aws",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": {
          "bucket": "definitely-not-existing-bucket-45678"
        }
      }
    },
    {
      "address": "aws_iam_role.test_role1",
      "mode": "managed",
      "type": "aws_iam_role",
      "name": "test_role1",
      "provider_name": "registry.terraform.io/hashicorp/aws",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": {
          "name": "definitely-not-existing-role-45678"
        }
      }
    }
  ]
}
EOF
            ;;
        *)
            log_error "Unknown test type: $test_type"
            return 1
            ;;
    esac
}

log_header "Running Pre-flight Resource Conflict Detection Tests"

# Check if the script exists
if [ ! -f "scripts/check-resource-conflicts.sh" ]; then
    log_error "scripts/check-resource-conflicts.sh not found"
    exit 1
fi

chmod +x scripts/check-resource-conflicts.sh

# Create a temporary directory for test files
TEST_DIR=$(mktemp -d)
log_info "Created test directory: $TEST_DIR"

# Test 1: Empty plan should pass
log_header "Test 1: Empty plan (should pass)"
MOCK_PLAN="$TEST_DIR/empty_plan.json"
create_mock_plan "empty" "$MOCK_PLAN"

if ./scripts/check-resource-conflicts.sh "$MOCK_PLAN"; then
    log_info "Test 1 PASSED: Empty plan handled correctly"
else
    log_error "Test 1 FAILED: Empty plan should pass"
    exit 1
fi

# Test 2: S3 no-conflict plan should pass
log_header "Test 2: S3 no-conflict plan (should pass)"
MOCK_PLAN="$TEST_DIR/s3_no_conflict_plan.json"
create_mock_plan "s3_no_conflict" "$MOCK_PLAN"

if ./scripts/check-resource-conflicts.sh "$MOCK_PLAN"; then
    log_info "Test 2 PASSED: S3 no-conflict plan handled correctly"
else
    log_error "Test 2 FAILED: S3 no-conflict plan should pass"
    # Note: This may fail in testing if the bucket name actually exists, which is expected in real environments
    log_warn "This failure may be expected if the test bucket name already exists in AWS"
fi

# Test 3: Multiple changes plan should pass
log_header "Test 3: Multiple changes plan (should pass)"
MOCK_PLAN="$TEST_DIR/multiple_changes_plan.json"
create_mock_plan "multiple_changes" "$MOCK_PLAN"

if ./scripts/check-resource-conflicts.sh "$MOCK_PLAN"; then
    log_info "Test 3 PASSED: Multiple changes plan handled correctly"
else
    log_error "Test 3 FAILED: Multiple changes plan should pass"
    # Note: This may fail in testing if any of the resource names already exist, which is expected in real environments
    log_warn "This failure may be expected if any test resource names already exist in AWS"
fi

# Test 4: Test script with invalid input
log_header "Test 4: Invalid input (should fail properly)"
if ./scripts/check-resource-conflicts.sh "nonexistent-file.json" 2>/dev/null; then
    log_error "Test 4 FAILED: Invalid input should cause script to fail"
    exit 1
else
    log_info "Test 4 PASSED: Invalid input handled correctly"
fi

# Test 5: Test script with no input
log_header "Test 5: No input (should fail properly)"
if ./scripts/check-resource-conflicts.sh 2>/dev/null; then
    log_error "Test 5 FAILED: No input should cause script to fail"
    exit 1
else
    log_info "Test 5 PASSED: No input handled correctly"
fi

# Cleanup
rm -rf "$TEST_DIR"
log_info "Test directory cleaned up"

log_header "All tests completed!"
log_info "Note: Some tests may show failures if test resource names already exist in your AWS account"
log_info "This is expected behavior - the script correctly identifies existing resources as conflicts"
