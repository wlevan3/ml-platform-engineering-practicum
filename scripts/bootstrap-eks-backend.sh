#!/bin/bash
set -euo pipefail

# =============================================================================
# Bootstrap Script: EKS Terraform Backend
# =============================================================================
#
# Purpose: One-time setup for Terraform remote state backend (S3 + DynamoDB)
#
# This script creates the required AWS resources for Terraform state management:
#   - S3 bucket for storing terraform.tfstate files
#   - DynamoDB table for state locking (prevents concurrent applies)
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials/profile
#   - Permissions: s3:CreateBucket, dynamodb:CreateTable, s3:PutBucketVersioning, etc.
#
# Usage:
#   ./scripts/bootstrap-eks-backend.sh [profile]
#
# Examples:
#   ./scripts/bootstrap-eks-backend.sh           # Uses default AWS profile
#   ./scripts/bootstrap-eks-backend.sh dev       # Uses 'dev' profile
#
# Cost:
#   - S3: ~$0.10-0.50/month (state file storage + versioning)
#   - DynamoDB: FREE (on-demand billing, minimal lock operations)
#
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

BUCKET_NAME="ml-platform-terraform-state"
TABLE_NAME="ml-platform-terraform-locks"
REGION="us-west-2"
AWS_PROFILE="${1:-default}" # Use first argument or default profile

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
	echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
	echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
	echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
	echo -e "${RED}❌ $1${NC}"
}

# -----------------------------------------------------------------------------
# Main Script
# -----------------------------------------------------------------------------

echo ""
echo "=================================================="
echo "  EKS Terraform Backend Bootstrap"
echo "=================================================="
echo ""

log_info "Configuration:"
echo "  - S3 Bucket: ${BUCKET_NAME}"
echo "  - DynamoDB Table: ${TABLE_NAME}"
echo "  - Region: ${REGION}"
echo "  - AWS Profile: ${AWS_PROFILE}"
echo ""

# Verify AWS credentials
log_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" --region "${REGION}" >/dev/null 2>&1; then
	log_error "Failed to authenticate with AWS profile '${AWS_PROFILE}'"
	log_error "Please configure AWS credentials: aws configure --profile ${AWS_PROFILE}"
	exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query Account --output text)
log_success "Authenticated as account: ${ACCOUNT_ID}"
echo ""

# -----------------------------------------------------------------------------
# Create S3 Bucket
# -----------------------------------------------------------------------------

log_info "Creating S3 bucket: ${BUCKET_NAME}"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --profile "${AWS_PROFILE}" 2>/dev/null; then
	log_warning "S3 bucket already exists: ${BUCKET_NAME}"
else
	# Create bucket (us-east-1 doesn't need LocationConstraint, others do)
	if [ "${REGION}" == "us-east-1" ]; then
		aws s3api create-bucket \
			--bucket "${BUCKET_NAME}" \
			--profile "${AWS_PROFILE}" \
			--region "${REGION}"
	else
		aws s3api create-bucket \
			--bucket "${BUCKET_NAME}" \
			--profile "${AWS_PROFILE}" \
			--region "${REGION}" \
			--create-bucket-configuration LocationConstraint="${REGION}"
	fi

	log_success "S3 bucket created: ${BUCKET_NAME}"
fi

# -----------------------------------------------------------------------------
# Enable S3 Bucket Versioning
# -----------------------------------------------------------------------------

log_info "Enabling versioning on S3 bucket..."

aws s3api put-bucket-versioning \
	--bucket "${BUCKET_NAME}" \
	--versioning-configuration Status=Enabled \
	--profile "${AWS_PROFILE}"

log_success "Versioning enabled (protects against accidental state deletion)"

# -----------------------------------------------------------------------------
# Enable S3 Bucket Encryption
# -----------------------------------------------------------------------------

log_info "Enabling server-side encryption..."

aws s3api put-bucket-encryption \
	--bucket "${BUCKET_NAME}" \
	--server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }' \
	--profile "${AWS_PROFILE}"

log_success "Encryption enabled (AES-256)"

# -----------------------------------------------------------------------------
# Block Public Access
# -----------------------------------------------------------------------------

log_info "Blocking public access to S3 bucket..."

aws s3api put-public-access-block \
	--bucket "${BUCKET_NAME}" \
	--public-access-block-configuration \
	"BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
	--profile "${AWS_PROFILE}"

log_success "Public access blocked (security best practice)"

# -----------------------------------------------------------------------------
# Create DynamoDB Table
# -----------------------------------------------------------------------------

log_info "Creating DynamoDB table: ${TABLE_NAME}"

# Check if table exists
if aws dynamodb describe-table \
	--table-name "${TABLE_NAME}" \
	--profile "${AWS_PROFILE}" \
	--region "${REGION}" >/dev/null 2>&1; then
	log_warning "DynamoDB table already exists: ${TABLE_NAME}"
else
	aws dynamodb create-table \
		--table-name "${TABLE_NAME}" \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		--profile "${AWS_PROFILE}" \
		--region "${REGION}" \
		--tags Key=Project,Value=ml-platform-engineering-practicum \
		Key=ManagedBy,Value=bootstrap-script \
		>/dev/null

	log_success "DynamoDB table created: ${TABLE_NAME}"
fi

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------

echo ""
log_info "Verifying resources..."

# Verify S3 bucket
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --profile "${AWS_PROFILE}" 2>/dev/null; then
	VERSIONING=$(aws s3api get-bucket-versioning --bucket "${BUCKET_NAME}" --profile "${AWS_PROFILE}" --query Status --output text)
	log_success "S3 bucket verified (versioning: ${VERSIONING})"
else
	log_error "S3 bucket verification failed"
	exit 1
fi

# Verify DynamoDB table
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --profile "${AWS_PROFILE}" --region "${REGION}" >/dev/null 2>&1; then
	TABLE_STATUS=$(aws dynamodb describe-table --table-name "${TABLE_NAME}" --profile "${AWS_PROFILE}" --region "${REGION}" --query Table.TableStatus --output text)
	log_success "DynamoDB table verified (status: ${TABLE_STATUS})"
else
	log_error "DynamoDB table verification failed"
	exit 1
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=================================================="
echo "  ✅ Bootstrap Complete!"
echo "=================================================="
echo ""
echo "Resources created:"
echo "  • S3 Bucket: s3://${BUCKET_NAME}"
echo "  • DynamoDB Table: ${TABLE_NAME}"
echo ""
echo "Next steps:"
echo "  1. Initialize Terraform:"
echo "     cd terraform/environments/dev"
echo "     terraform init -backend-config=\"profile=${AWS_PROFILE}\""
echo ""
echo "  2. Deploy infrastructure:"
echo "     terraform plan -out=tfplan"
echo "     terraform apply tfplan"
echo ""
echo "  3. Or use GitHub Actions workflow:"
echo "     gh workflow run eks-deploy.yml -f action=deploy"
echo ""
echo "Cost estimate:"
echo "  • S3 storage: ~\$0.10-0.50/month"
echo "  • DynamoDB: FREE (pay-per-request)"
echo ""
echo "=================================================="
echo ""
