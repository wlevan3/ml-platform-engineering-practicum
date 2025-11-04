#!/usr/bin/env bash
#
# AWS Cleanup Verification Script - Layer 3 Verification
#
# This script performs comprehensive multi-service verification to ensure
# complete resource cleanup after terraform destroy and nuclear cleanup.
#
# Usage:
#   ./scripts/verify-cleanup.sh
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
# AWS PROFILE CONFIGURATION - HARDCODED FOR SAFETY (SAFE TO COMMIT)
# ============================================================================
export AWS_PROFILE="kodekloud"
export AWS_REGION="us-west-2"

# Expected KodeKloud sandbox account ID
readonly EXPECTED_ACCOUNT_ID="984479408136"

# Configuration
PROJECT_TAG_KEY="Project"
PROJECT_TAG_VALUE="ml-platform-engineering-practicum"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Tracking
RESOURCES_FOUND=false

# ============================================================================
# Logging Functions
# ============================================================================

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
# Account Validation
# ============================================================================

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

# ============================================================================
# Prerequisite Checks
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

	# Verify AWS credentials
	if ! aws sts get-caller-identity >/dev/null 2>&1; then
		log_error "AWS credentials not configured or invalid"
		log_info "Set AWS_PROFILE environment variable or run 'aws configure'"
		exit 1
	fi
	log_success "✓ AWS credentials valid"

	validate_aws_account
	echo ""
}

# ============================================================================
# Verification Functions
# ============================================================================

# Check EKS Clusters
verify_eks_clusters() {
	log_section "Checking EKS Clusters"

	local clusters
	clusters=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output json | jq -r '.[]')

	if [[ -z "$clusters" ]]; then
		log_success "✓ No EKS clusters found"
		return
	fi

	# Check each cluster for project tag
	for cluster in $clusters; do
		local tags
		tags=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.tags' --output json 2>/dev/null || echo "{}")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[\"$PROJECT_TAG_KEY\"] // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			log_resource_found "EKS Cluster: $cluster"
		fi
	done
}

# Check EC2 Instances
verify_ec2_instances() {
	log_section "Checking EC2 Instances"

	local instances
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	instances=$(aws ec2 describe-instances --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name,InstanceType]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$instances" ]]; then
		log_success "✓ No EC2 instances found"
		return
	fi

	while IFS=$'\t' read -r instance_id state instance_type; do
		log_resource_found "EC2 Instance: $instance_id (State: $state, Type: $instance_type)"
	done <<<"$instances"
}

# Check Load Balancers (ALB/NLB)
verify_load_balancers() {
	log_section "Checking Load Balancers"

	local load_balancers
	load_balancers=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancers[].LoadBalancerArn' --output json | jq -r '.[]')

	if [[ -z "$load_balancers" ]]; then
		log_success "✓ No load balancers found"
		return
	fi

	for lb_arn in $load_balancers; do
		local tags
		tags=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --region "$AWS_REGION" --query 'TagDescriptions[0].Tags' --output json 2>/dev/null || echo "[]")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[] | select(.Key == \"$PROJECT_TAG_KEY\") | .Value // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			local lb_name
			lb_name=$(aws elbv2 describe-load-balancers --load-balancer-arns "$lb_arn" --region "$AWS_REGION" --query 'LoadBalancers[0].LoadBalancerName' --output text)
			log_resource_found "Load Balancer: $lb_name (ARN: $lb_arn)"
		fi
	done
}

# Check Target Groups
verify_target_groups() {
	log_section "Checking Target Groups"

	local target_groups
	target_groups=$(aws elbv2 describe-target-groups --region "$AWS_REGION" --query 'TargetGroups[].TargetGroupArn' --output json | jq -r '.[]')

	if [[ -z "$target_groups" ]]; then
		log_success "✓ No target groups found"
		return
	fi

	for tg_arn in $target_groups; do
		local tags
		tags=$(aws elbv2 describe-tags --resource-arns "$tg_arn" --region "$AWS_REGION" --query 'TagDescriptions[0].Tags' --output json 2>/dev/null || echo "[]")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[] | select(.Key == \"$PROJECT_TAG_KEY\") | .Value // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			local tg_name
			tg_name=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --region "$AWS_REGION" --query 'TargetGroups[0].TargetGroupName' --output text)
			log_resource_found "Target Group: $tg_name (ARN: $tg_arn)"
		fi
	done
}

# Check NAT Gateways
verify_nat_gateways() {
	log_section "Checking NAT Gateways"

	local nat_gateways
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	nat_gateways=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
		--filter "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'NatGateways[?State!=`deleted`].[NatGatewayId,State]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$nat_gateways" ]]; then
		log_success "✓ No NAT gateways found"
		return
	fi

	while IFS=$'\t' read -r nat_id state; do
		log_resource_found "NAT Gateway: $nat_id (State: $state)"
	done <<<"$nat_gateways"
}

# Check Elastic IPs
verify_elastic_ips() {
	log_section "Checking Elastic IPs"

	local eips
	eips=$(aws ec2 describe-addresses --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Addresses[].[AllocationId,PublicIp,AssociationId]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$eips" ]]; then
		log_success "✓ No Elastic IPs found"
		return
	fi

	while IFS=$'\t' read -r allocation_id public_ip association_id; do
		if [[ -n "$association_id" ]]; then
			log_resource_found "Elastic IP: $allocation_id ($public_ip) - ASSOCIATED"
		else
			log_resource_found "Elastic IP: $allocation_id ($public_ip) - UNASSOCIATED"
		fi
	done <<<"$eips"
}

# Check EBS Volumes
verify_ebs_volumes() {
	log_section "Checking EBS Volumes"

	local volumes
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	volumes=$(aws ec2 describe-volumes --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Volumes[?State!=`deleted`].[VolumeId,State,Size,VolumeType]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$volumes" ]]; then
		log_success "✓ No EBS volumes found"
		return
	fi

	while IFS=$'\t' read -r volume_id state size volume_type; do
		log_resource_found "EBS Volume: $volume_id (State: $state, Size: ${size}GB, Type: $volume_type)"
	done <<<"$volumes"
}

# Check Security Groups
verify_security_groups() {
	log_section "Checking Security Groups"

	local security_groups
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	security_groups=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName,VpcId]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$security_groups" ]]; then
		log_success "✓ No security groups found"
		return
	fi

	while IFS=$'\t' read -r group_id group_name vpc_id; do
		log_resource_found "Security Group: $group_id ($group_name in VPC $vpc_id)"
	done <<<"$security_groups"
}

# Check Subnets
verify_subnets() {
	log_section "Checking Subnets"

	local subnets
	subnets=$(aws ec2 describe-subnets --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,VpcId]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$subnets" ]]; then
		log_success "✓ No subnets found"
		return
	fi

	while IFS=$'\t' read -r subnet_id cidr_block az vpc_id; do
		log_resource_found "Subnet: $subnet_id ($cidr_block in $az, VPC $vpc_id)"
	done <<<"$subnets"
}

# Check Route Tables
verify_route_tables() {
	log_section "Checking Route Tables"

	local route_tables
	route_tables=$(aws ec2 describe-route-tables --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'RouteTables[].[RouteTableId,VpcId]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$route_tables" ]]; then
		log_success "✓ No route tables found"
		return
	fi

	while IFS=$'\t' read -r route_table_id vpc_id; do
		# Check if this is the main route table
		local is_main
		# shellcheck disable=SC2016
		# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
		is_main=$(aws ec2 describe-route-tables --route-table-ids "$route_table_id" --region "$AWS_REGION" \
			--query 'RouteTables[0].Associations[?Main==`true`]' --output json | jq -r 'length')

		if [[ "$is_main" -gt 0 ]]; then
			log_resource_found "Route Table: $route_table_id (MAIN, VPC $vpc_id)"
		else
			log_resource_found "Route Table: $route_table_id (VPC $vpc_id)"
		fi
	done <<<"$route_tables"
}

# Check Internet Gateways
verify_internet_gateways() {
	log_section "Checking Internet Gateways"

	local igws
	igws=$(aws ec2 describe-internet-gateways --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'InternetGateways[].[InternetGatewayId,Attachments[0].VpcId]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$igws" ]]; then
		log_success "✓ No internet gateways found"
		return
	fi

	while IFS=$'\t' read -r igw_id vpc_id; do
		if [[ -n "$vpc_id" ]]; then
			log_resource_found "Internet Gateway: $igw_id (ATTACHED to VPC $vpc_id)"
		else
			log_resource_found "Internet Gateway: $igw_id (DETACHED)"
		fi
	done <<<"$igws"
}

# Check VPCs
verify_vpcs() {
	log_section "Checking VPCs"

	local vpcs
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	vpcs=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Vpcs[?IsDefault==`false`].[VpcId,CidrBlock,State]' \
		--output json | jq -r '.[] | @tsv')

	if [[ -z "$vpcs" ]]; then
		log_success "✓ No VPCs found"
		return
	fi

	while IFS=$'\t' read -r vpc_id cidr_block state; do
		log_resource_found "VPC: $vpc_id ($cidr_block, State: $state)"
	done <<<"$vpcs"
}

# Check ECR Repositories
verify_ecr_repositories() {
	log_section "Checking ECR Repositories"

	local repositories
	repositories=$(aws ecr describe-repositories --region "$AWS_REGION" --query 'repositories[].repositoryName' --output json | jq -r '.[]')

	if [[ -z "$repositories" ]]; then
		log_success "✓ No ECR repositories found"
		return
	fi

	for repo in $repositories; do
		local tags
		tags=$(aws ecr list-tags-for-resource --resource-arn "arn:aws:ecr:$AWS_REGION:$EXPECTED_ACCOUNT_ID:repository/$repo" --region "$AWS_REGION" --query 'tags' --output json 2>/dev/null || echo "[]")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[] | select(.Key == \"$PROJECT_TAG_KEY\") | .Value // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			local image_count
			image_count=$(aws ecr list-images --repository-name "$repo" --region "$AWS_REGION" --query 'imageIds | length(@)' --output text)
			log_resource_found "ECR Repository: $repo ($image_count images)"
		fi
	done
}

# Check IAM Roles
verify_iam_roles() {
	log_section "Checking IAM Roles"

	local roles
	roles=$(aws iam list-roles --query 'Roles[].RoleName' --output json | jq -r '.[]')

	if [[ -z "$roles" ]]; then
		log_success "✓ No IAM roles found"
		return
	fi

	for role in $roles; do
		local tags
		tags=$(aws iam list-role-tags --role-name "$role" --query 'Tags' --output json 2>/dev/null || echo "[]")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[] | select(.Key == \"$PROJECT_TAG_KEY\") | .Value // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			log_resource_found "IAM Role: $role"
		fi
	done
}

# Check S3 Buckets
verify_s3_buckets() {
	log_section "Checking S3 Buckets"

	local buckets
	buckets=$(aws s3api list-buckets --query 'Buckets[].Name' --output json | jq -r '.[]')

	if [[ -z "$buckets" ]]; then
		log_success "✓ No S3 buckets found"
		return
	fi

	for bucket in $buckets; do
		local tags
		tags=$(aws s3api get-bucket-tagging --bucket "$bucket" --query 'TagSet' --output json 2>/dev/null || echo "[]")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[] | select(.Key == \"$PROJECT_TAG_KEY\") | .Value // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			# Get object count
			local object_count
			object_count=$(aws s3 ls "s3://$bucket" --recursive 2>/dev/null | wc -l | xargs)
			log_resource_found "S3 Bucket: $bucket ($object_count objects)"
		fi
	done
}

# Check DynamoDB Tables
verify_dynamodb_tables() {
	log_section "Checking DynamoDB Tables"

	local tables
	tables=$(aws dynamodb list-tables --region "$AWS_REGION" --query 'TableNames[]' --output json | jq -r '.[]')

	if [[ -z "$tables" ]]; then
		log_success "✓ No DynamoDB tables found"
		return
	fi

	for table in $tables; do
		local tags
		tags=$(aws dynamodb list-tags-of-resource --resource-arn "arn:aws:dynamodb:$AWS_REGION:$EXPECTED_ACCOUNT_ID:table/$table" --region "$AWS_REGION" --query 'Tags' --output json 2>/dev/null || echo "[]")

		local project_tag
		project_tag=$(echo "$tags" | jq -r ".[] | select(.Key == \"$PROJECT_TAG_KEY\") | .Value // empty")

		if [[ "$project_tag" == "$PROJECT_TAG_VALUE" ]]; then
			local item_count
			item_count=$(aws dynamodb describe-table --table-name "$table" --region "$AWS_REGION" --query 'Table.ItemCount' --output text)
			log_resource_found "DynamoDB Table: $table ($item_count items)"
		fi
	done
}

# Check CloudWatch Log Groups
verify_cloudwatch_logs() {
	log_section "Checking CloudWatch Log Groups"

	# Use Resource Groups Tagging API for consistent tag-based filtering
	# (CloudWatch Logs API doesn't support tag filters, but Resource Groups API does)
	local log_group_arns
	log_group_arns=$(aws resourcegroupstaggingapi get-resources \
		--region "$AWS_REGION" \
		--resource-type-filters "logs:log-group" \
		--tag-filters "Key=$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'ResourceTagMappingList[].ResourceARN' \
		--output json 2>/dev/null | jq -r '.[]')

	if [[ -z "$log_group_arns" ]]; then
		log_success "✓ No CloudWatch log groups found"
		return
	fi

	for log_group_arn in $log_group_arns; do
		# Extract log group name from ARN (format: arn:aws:logs:region:account:log-group:name:*)
		local temp="${log_group_arn##*:log-group:}" # Remove prefix up to :log-group:
		local log_group_name="${temp%%:*}"          # Remove suffix from next : onwards

		local log_streams
		log_streams=$(aws logs describe-log-streams --log-group-name "$log_group_name" --region "$AWS_REGION" --query 'logStreams | length(@)' --output text 2>/dev/null || echo "0")
		log_resource_found "CloudWatch Log Group: $log_group_name ($log_streams streams)"
	done
}

# ============================================================================
# Main Function
# ============================================================================

main() {
	echo ""
	echo -e "${GREEN}========================================${NC}"
	echo -e "${GREEN}AWS CLEANUP VERIFICATION SCRIPT${NC}"
	echo -e "${GREEN}========================================${NC}"
	echo ""
	log_info "Project: $PROJECT_TAG_VALUE"
	log_info "Region: $AWS_REGION"
	log_info "Account: $EXPECTED_ACCOUNT_ID (KodeKloud sandbox)"
	echo ""

	check_prerequisites

	log_section "Starting Resource Verification"
	log_info "Checking 16 AWS service categories for project resources..."
	echo ""

	# Run all verification checks
	verify_eks_clusters
	verify_ec2_instances
	verify_load_balancers
	verify_target_groups
	verify_nat_gateways
	verify_elastic_ips
	verify_ebs_volumes
	verify_security_groups
	verify_subnets
	verify_route_tables
	verify_internet_gateways
	verify_vpcs
	verify_ecr_repositories
	verify_iam_roles
	verify_s3_buckets
	verify_dynamodb_tables
	verify_cloudwatch_logs

	# Final summary
	echo ""
	log_section "Verification Complete"

	if [[ "$RESOURCES_FOUND" == "true" ]]; then
		log_error "❌ CLEANUP INCOMPLETE - Resources still exist!"
		echo ""
		log_warning "Next steps:"
		echo "  1. Review resources listed above"
		echo "  2. Run nuclear cleanup script: ./scripts/aws-nuclear-cleanup.sh"
		echo "  3. Or manually delete resources via AWS Console"
		echo ""
		exit 1
	else
		log_success "✅ ALL CLEAN - No project resources found!"
		echo ""
		log_info "All AWS resources for project '$PROJECT_TAG_VALUE' have been successfully deleted."
		echo ""
		exit 0
	fi
}

# Run main function
main "$@"
