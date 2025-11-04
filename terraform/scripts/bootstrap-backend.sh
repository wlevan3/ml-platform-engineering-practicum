#!/usr/bin/env bash
#
# Bootstrap Terraform Remote State Backend
#
# This script creates the S3 bucket and DynamoDB table required for Terraform
# remote state management. Must be run BEFORE `terraform init`.
#
# Resources created:
# - S3 bucket: ml-platform-terraform-state (versioned, encrypted)
# - DynamoDB table: ml-platform-terraform-locks (for state locking)
#
# Usage:
#   ./terraform/scripts/bootstrap-backend.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - AWS_PROFILE set (or use --profile flag)
#

set -euo pipefail

# Source shared logging library
# shellcheck disable=SC1091
source "$(dirname "$0")/../../scripts/lib/logging.sh"

# ============================================================================
# AWS PROFILE CONFIGURATION - HARDCODED FOR SAFETY (SAFE TO COMMIT)
# ============================================================================
export AWS_PROFILE="kodekloud"
export AWS_REGION="us-west-2"

# Expected KodeKloud sandbox account ID
readonly EXPECTED_ACCOUNT_ID="984479408136"

# Configuration
S3_BUCKET="ml-platform-terraform-state"
DYNAMODB_TABLE="ml-platform-terraform-locks"

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v aws &>/dev/null; then
	log_error "AWS CLI not found. Install with: brew install awscli"
	exit 1
fi
log_success "✓ AWS CLI found: $(aws --version 2>&1 | head -1)"

# Verify AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
	log_error "AWS credentials not configured or invalid"
	log_info "Set AWS_PROFILE environment variable or run 'aws configure'"
	exit 1
fi
log_success "✓ AWS credentials valid"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_info "AWS Account: $ACCOUNT_ID"
log_info "Region: $AWS_REGION"
log_info "Profile: $AWS_PROFILE"

# ============================================================================
# SAFETY CHECK: Verify we're using the correct AWS account
# ============================================================================
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
	log_error "❌ Wrong AWS account!"
	log_error "   Expected: $EXPECTED_ACCOUNT_ID (KodeKloud sandbox)"
	log_error "   Current:  $ACCOUNT_ID"
	log_error "   Profile:  $AWS_PROFILE"
	log_error ""
	log_error "This script is hardcoded to only run against the KodeKloud sandbox account."
	log_error "Exiting to prevent accidental resource creation in wrong account."
	exit 1
fi
log_success "✅ Correct AWS account verified: $ACCOUNT_ID (KodeKloud sandbox)"
echo ""

# Create S3 bucket for state
log_info "Creating S3 bucket for Terraform state..."

if aws s3 ls "s3://${S3_BUCKET}" 2>/dev/null; then
	log_warning "S3 bucket '${S3_BUCKET}' already exists, skipping creation"
else
	# Create bucket
	if [ "$AWS_REGION" == "us-east-1" ]; then
		# us-east-1 doesn't require LocationConstraint
		aws s3api create-bucket \
			--bucket "${S3_BUCKET}" \
			--region "${AWS_REGION}"
	else
		# Other regions require LocationConstraint
		aws s3api create-bucket \
			--bucket "${S3_BUCKET}" \
			--region "${AWS_REGION}" \
			--create-bucket-configuration LocationConstraint="${AWS_REGION}"
	fi

	log_success "✓ S3 bucket created: ${S3_BUCKET}"

	# Enable versioning
	log_info "Enabling versioning on S3 bucket..."
	aws s3api put-bucket-versioning \
		--bucket "${S3_BUCKET}" \
		--versioning-configuration Status=Enabled

	log_success "✓ Versioning enabled"

	# Enable encryption
	log_info "Enabling encryption on S3 bucket..."
	aws s3api put-bucket-encryption \
		--bucket "${S3_BUCKET}" \
		--server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'

	log_success "✓ Encryption enabled (AES256)"

	# Block public access
	log_info "Blocking public access to S3 bucket..."
	aws s3api put-public-access-block \
		--bucket "${S3_BUCKET}" \
		--public-access-block-configuration \
		"BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

	log_success "✓ Public access blocked"

	# Add lifecycle policy (optional - retains last 30 versions)
	log_info "Adding lifecycle policy..."
	aws s3api put-bucket-lifecycle-configuration \
		--bucket "${S3_BUCKET}" \
		--lifecycle-configuration '{
            "Rules": [
                {
                    "Id": "DeleteOldVersions",
                    "Status": "Enabled",
                    "NoncurrentVersionExpiration": {
                        "NoncurrentDays": 90
                    }
                },
                {
                    "Id": "KeepLast30Versions",
                    "Status": "Enabled",
                    "NoncurrentVersionExpiration": {
                        "NewerNoncurrentVersions": 30,
                        "NoncurrentDays": 1
                    }
                }
            ]
        }'

	log_success "✓ Lifecycle policy added (retain 30 versions, delete after 90 days)"
fi

# Create DynamoDB table for state locking
log_info "Creating DynamoDB table for state locking..."

if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
	log_warning "DynamoDB table '${DYNAMODB_TABLE}' already exists, skipping creation"
else
	aws dynamodb create-table \
		--table-name "${DYNAMODB_TABLE}" \
		--region "${AWS_REGION}" \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		--tags Key=Project,Value=ml-platform-engineering-practicum \
		Key=ManagedBy,Value=Script \
		Key=Purpose,Value=TerraformStateLocking

	log_success "✓ DynamoDB table created: ${DYNAMODB_TABLE}"

	# Wait for table to be active
	log_info "Waiting for DynamoDB table to be active..."
	aws dynamodb wait table-exists \
		--table-name "${DYNAMODB_TABLE}" \
		--region "${AWS_REGION}"

	log_success "✓ DynamoDB table is active"
fi

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}BACKEND BOOTSTRAP COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
log_info "Resources created:"
echo "  S3 Bucket:       ${S3_BUCKET}"
echo "  DynamoDB Table:  ${DYNAMODB_TABLE}"
echo "  Region:          ${AWS_REGION}"
echo ""
log_info "Next steps:"
echo "  1. cd terraform/environments/dev"
echo "  2. terraform init"
echo "  3. terraform plan"
echo "  4. terraform apply"
echo ""
log_info "Verify resources:"
echo "  aws s3 ls s3://${S3_BUCKET}"
echo "  aws dynamodb describe-table --table-name ${DYNAMODB_TABLE}"
echo ""
