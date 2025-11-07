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
# AWS PROFILE CONFIGURATION - HARDCODED FOR SAFETY (SAFE TO COMMIT)
# ============================================================================
export AWS_PROFILE="kodekloud"
readonly EXPECTED_ACCOUNT_ID="984479408136"

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
PROJECT_TAG_KEY="Project"
PROJECT_TAG_VALUE="ml-platform-engineering-practicum"

# Colors for output
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

# Check prerequisites
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

# Verify AWS account
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

# Get EKS clusters with project tag
get_eks_clusters() {
	local clusters
	clusters=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output json 2>/dev/null | jq -r '.[]')

	local tagged_clusters=()
	for cluster in $clusters; do
		local tags
		tags=$(aws eks list-tags-for-resource --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags.\"$PROJECT_TAG_KEY\" // empty")

		if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
			tagged_clusters+=("$cluster")
		fi
	done

	printf '%s\n' "${tagged_clusters[@]}"
}

# Get EC2 instances with project tag
get_ec2_instances() {
	aws ec2 describe-instances \
		--region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
		--query 'Reservations[].Instances[].InstanceId' \
		--output json 2>/dev/null | jq -r '.[]'
}

# Get VPCs with project tag
get_vpcs() {
	aws ec2 describe-vpcs \
		--region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Vpcs[].VpcId' \
		--output json 2>/dev/null | jq -r '.[]'
}

# Get NAT Gateways with project tag
get_nat_gateways() {
	aws ec2 describe-nat-gateways \
		--region "$AWS_REGION" \
		--filter "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" "Name=state,Values=available,pending" \
		--query 'NatGateways[].NatGatewayId' \
		--output json 2>/dev/null | jq -r '.[]'
}

# Get Load Balancers (ALB/NLB) with project tag
get_load_balancers() {
	aws elbv2 describe-load-balancers \
		--region "$AWS_REGION" \
		--query 'LoadBalancers[].LoadBalancerArn' \
		--output json 2>/dev/null | jq -r '.[]' | while read -r arn; do
		local tags
		tags=$(aws elbv2 describe-tags --resource-arns "$arn" --region "$AWS_REGION" 2>/dev/null | jq -r ".TagDescriptions[0].Tags[] | select(.Key == \"$PROJECT_TAG_KEY\" and .Value == \"$PROJECT_TAG_VALUE\") | .Value")

		if [[ -n "$tags" ]]; then
			echo "$arn"
		fi
	done
}

# Get ECR repositories with project tag
get_ecr_repositories() {
	aws ecr describe-repositories \
		--region "$AWS_REGION" \
		--query 'repositories[].repositoryName' \
		--output json 2>/dev/null | jq -r '.[]' | while read -r repo; do
		local tags
		tags=$(aws ecr list-tags-for-resource --resource-arn "arn:aws:ecr:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):repository/$repo" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags[] | select(.Key == \"$PROJECT_TAG_KEY\" and .Value == \"$PROJECT_TAG_VALUE\") | .Value")

		if [[ -n "$tags" ]]; then
			echo "$repo"
		fi
	done
}

# Get EBS volumes with project tag
get_ebs_volumes() {
	aws ec2 describe-volumes \
		--region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Volumes[].VolumeId' \
		--output json 2>/dev/null | jq -r '.[]'
}

# Get Elastic IPs with project tag
get_elastic_ips() {
	aws ec2 describe-addresses \
		--region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'Addresses[].AllocationId' \
		--output json 2>/dev/null | jq -r '.[]'
}

# Get Security Groups with project tag (exclude default)
get_security_groups() {
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	aws ec2 describe-security-groups \
		--region "$AWS_REGION" \
		--filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" \
		--query 'SecurityGroups[?GroupName!=`default`].GroupId' \
		--output json 2>/dev/null | jq -r '.[]'
}

# Get S3 buckets with project tag
get_s3_buckets() {
	aws s3api list-buckets --query 'Buckets[].Name' --output json 2>/dev/null | jq -r '.[]' | while read -r bucket; do
		local tags
		tags=$(aws s3api get-bucket-tagging --bucket "$bucket" 2>/dev/null | jq -r ".TagSet[] | select(.Key == \"$PROJECT_TAG_KEY\" and .Value == \"$PROJECT_TAG_VALUE\") | .Value")

		if [[ -n "$tags" ]]; then
			echo "$bucket"
		fi
	done
}

# Get DynamoDB tables with project tag
get_dynamodb_tables() {
	aws dynamodb list-tables --region "$AWS_REGION" --query 'TableNames[]' --output json 2>/dev/null | jq -r '.[]' | while read -r table; do
		local tags
		tags=$(aws dynamodb list-tags-of-resource --resource-arn "arn:aws:dynamodb:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):table/$table" --region "$AWS_REGION" 2>/dev/null | jq -r ".Tags[] | select(.Key == \"$PROJECT_TAG_KEY\" and .Value == \"$PROJECT_TAG_VALUE\") | .Value")

		if [[ -n "$tags" ]]; then
			echo "$table"
		fi
	done
}

# Calculate estimated costs (rough approximation)
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

# Helper function to count lines safely
count_lines() {
	local input=$1
	if [[ -z "$input" ]]; then
		echo "0"
	else
		echo "$input" | wc -l | tr -d ' '
	fi
}

# Helper function to print items with indent
print_items_with_indent() {
	local items=$1
	while IFS= read -r line; do
		echo "    - $line"
	done <<<"$items"
}

# Collect inventory
collect_inventory() {
	log_info "Collecting resource inventory for project: $PROJECT_TAG_VALUE"
	log_info "Region: $AWS_REGION"
	echo ""

	local inventory="{}"

	log_section "EKS Clusters"
	local eks_clusters
	local eks_count
	eks_clusters=$(get_eks_clusters)
	eks_count=$(count_lines "$eks_clusters")
	inventory=$(echo "$inventory" | jq --argjson count "$eks_count" --arg items "$eks_clusters" '.eks_clusters = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $eks_count"
	if [[ $eks_count -gt 0 ]]; then
		print_items_with_indent "$eks_clusters"
	fi

	log_section "EC2 Instances"
	local ec2_instances
	local ec2_count
	ec2_instances=$(get_ec2_instances)
	ec2_count=$(count_lines "$ec2_instances")
	inventory=$(echo "$inventory" | jq --argjson count "$ec2_count" --arg items "$ec2_instances" '.ec2_instances = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $ec2_count"
	if [[ $ec2_count -gt 0 ]]; then
		print_items_with_indent "$ec2_instances"
	fi

	log_section "VPCs"
	local vpcs
	local vpc_count
	vpcs=$(get_vpcs)
	vpc_count=$(count_lines "$vpcs")
	inventory=$(echo "$inventory" | jq --argjson count "$vpc_count" --arg items "$vpcs" '.vpcs = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $vpc_count"
	if [[ $vpc_count -gt 0 ]]; then
		print_items_with_indent "$vpcs"
	fi

	log_section "NAT Gateways"
	local nat_gateways
	local nat_count
	nat_gateways=$(get_nat_gateways)
	nat_count=$(count_lines "$nat_gateways")
	inventory=$(echo "$inventory" | jq --argjson count "$nat_count" --arg items "$nat_gateways" '.nat_gateways = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $nat_count"
	if [[ $nat_count -gt 0 ]]; then
		print_items_with_indent "$nat_gateways"
	fi

	log_section "Load Balancers"
	local load_balancers
	local lb_count
	load_balancers=$(get_load_balancers)
	lb_count=$(count_lines "$load_balancers")
	inventory=$(echo "$inventory" | jq --argjson count "$lb_count" --arg items "$load_balancers" '.load_balancers = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $lb_count"
	if [[ $lb_count -gt 0 ]]; then
		print_items_with_indent "$load_balancers"
	fi

	log_section "ECR Repositories"
	local ecr_repos
	local ecr_count
	ecr_repos=$(get_ecr_repositories)
	ecr_count=$(count_lines "$ecr_repos")
	inventory=$(echo "$inventory" | jq --argjson count "$ecr_count" --arg items "$ecr_repos" '.ecr_repositories = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $ecr_count"
	if [[ $ecr_count -gt 0 ]]; then
		print_items_with_indent "$ecr_repos"
	fi

	log_section "EBS Volumes"
	local ebs_volumes
	local ebs_count
	ebs_volumes=$(get_ebs_volumes)
	ebs_count=$(count_lines "$ebs_volumes")
	inventory=$(echo "$inventory" | jq --argjson count "$ebs_count" --arg items "$ebs_volumes" '.ebs_volumes = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $ebs_count"
	if [[ $ebs_count -gt 0 ]]; then
		print_items_with_indent "$ebs_volumes"
	fi

	log_section "Elastic IPs"
	local elastic_ips
	local eip_count
	elastic_ips=$(get_elastic_ips)
	eip_count=$(count_lines "$elastic_ips")
	inventory=$(echo "$inventory" | jq --argjson count "$eip_count" --arg items "$elastic_ips" '.elastic_ips = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $eip_count"
	if [[ $eip_count -gt 0 ]]; then
		print_items_with_indent "$elastic_ips"
	fi

	log_section "Security Groups"
	local security_groups
	local sg_count
	security_groups=$(get_security_groups)
	sg_count=$(count_lines "$security_groups")
	inventory=$(echo "$inventory" | jq --argjson count "$sg_count" --arg items "$security_groups" '.security_groups = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $sg_count"
	if [[ $sg_count -gt 0 ]]; then
		print_items_with_indent "$security_groups"
	fi

	log_section "S3 Buckets"
	local s3_buckets
	local s3_count
	s3_buckets=$(get_s3_buckets)
	s3_count=$(count_lines "$s3_buckets")
	inventory=$(echo "$inventory" | jq --argjson count "$s3_count" --arg items "$s3_buckets" '.s3_buckets = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $s3_count"
	if [[ $s3_count -gt 0 ]]; then
		print_items_with_indent "$s3_buckets"
	fi

	log_section "DynamoDB Tables"
	local dynamodb_tables
	local ddb_count
	dynamodb_tables=$(get_dynamodb_tables)
	ddb_count=$(count_lines "$dynamodb_tables")
	inventory=$(echo "$inventory" | jq --argjson count "$ddb_count" --arg items "$dynamodb_tables" '.dynamodb_tables = {count: $count, items: ($items | split("\n") | map(select(length > 0)))}')
	echo "  Count: $ddb_count"
	if [[ $ddb_count -gt 0 ]]; then
		print_items_with_indent "$dynamodb_tables"
	fi

	# Calculate total resource count
	local total_count=$((eks_count + ec2_count + vpc_count + nat_count + lb_count + ecr_count + ebs_count + eip_count + sg_count + s3_count + ddb_count))
	inventory=$(echo "$inventory" | jq --argjson total "$total_count" '.total_resources = $total')

	# Calculate estimated hourly cost
	local hourly_cost
	hourly_cost=$(calculate_costs "$eks_count" "$ec2_count" "$nat_count" "$lb_count")
	inventory=$(echo "$inventory" | jq --arg cost "$hourly_cost" '.estimated_hourly_cost = $cost')

	# Add metadata
	inventory=$(echo "$inventory" | jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg region "$AWS_REGION" '.metadata = {timestamp: $timestamp, region: $region}')

	log_section "Summary"
	echo "  Total Resources: $total_count"
	printf "  Estimated Hourly Cost: \$%.4f (~\$%.2f/day)\n" "$hourly_cost" "$(echo "$hourly_cost * 24" | bc -l)"
	echo ""

	echo "$inventory"
}

# Export inventory to JSON file
export_inventory() {
	local output_file=$1
	local inventory
	inventory=$(collect_inventory)

	echo "$inventory" | jq '.' >"$output_file"
	log_success "Inventory exported to: $output_file"
}

# Compare current inventory against baseline
diff_inventory() {
	local baseline_file=$1

	if [[ ! -f "$baseline_file" ]]; then
		log_error "Baseline file not found: $baseline_file"
		exit 1
	fi

	log_info "Comparing current inventory against baseline: $baseline_file"
	echo ""

	local current_inventory
	current_inventory=$(collect_inventory)

	local baseline_inventory
	baseline_inventory=$(cat "$baseline_file")

	# Compare resource counts
	log_section "Resource Count Changes"

	local resource_types=("eks_clusters" "ec2_instances" "vpcs" "nat_gateways" "load_balancers" "ecr_repositories" "ebs_volumes" "elastic_ips" "security_groups" "s3_buckets" "dynamodb_tables")

	for resource_type in "${resource_types[@]}"; do
		local current_count
		current_count=$(echo "$current_inventory" | jq -r ".$resource_type.count")
		local baseline_count
		baseline_count=$(echo "$baseline_inventory" | jq -r ".$resource_type.count")
		local delta=$((current_count - baseline_count))

		if [[ $delta -gt 0 ]]; then
			echo -e "  ${resource_type}: ${baseline_count} → ${current_count} ${GREEN}(+${delta})${NC}"
		elif [[ $delta -lt 0 ]]; then
			echo -e "  ${resource_type}: ${baseline_count} → ${current_count} ${RED}(${delta})${NC}"
		else
			echo "  ${resource_type}: ${baseline_count} → ${current_count} (no change)"
		fi
	done

	# Cost comparison
	log_section "Cost Estimate"
	local current_cost
	current_cost=$(echo "$current_inventory" | jq -r '.estimated_hourly_cost')
	local baseline_cost
	baseline_cost=$(echo "$baseline_inventory" | jq -r '.estimated_hourly_cost')
	local cost_delta
	cost_delta=$(echo "$current_cost - $baseline_cost" | bc -l)

	printf "  Baseline: \$%.4f/hour\n" "$baseline_cost"
	printf "  Current:  \$%.4f/hour\n" "$current_cost"
	if (($(echo "$cost_delta > 0" | bc -l))); then
		printf "  ${GREEN}Change: +\$%.4f/hour (+\$%.2f/day)${NC}\n" "$cost_delta" "$(echo "$cost_delta * 24" | bc -l)"
	elif (($(echo "$cost_delta < 0" | bc -l))); then
		printf "  ${RED}Change: \$%.4f/hour (\$%.2f/day)${NC}\n" "$cost_delta" "$(echo "$cost_delta * 24" | bc -l)"
	else
		echo "  Change: \$0.0000/hour (no change)"
	fi

	echo ""
}

# Verify inventory is empty (for cleanup verification)
verify_empty() {
	local inventory
	inventory=$(collect_inventory)

	local total_resources
	total_resources=$(echo "$inventory" | jq -r '.total_resources')

	if [[ $total_resources -eq 0 ]]; then
		log_success "✓ All resources successfully deleted! Total resources: 0"
		exit 0
	else
		log_error "✗ Resources still remain! Total resources: $total_resources"

		log_section "Remaining Resources"
		local resource_types=("eks_clusters" "ec2_instances" "vpcs" "nat_gateways" "load_balancers" "ecr_repositories" "ebs_volumes" "elastic_ips" "security_groups" "s3_buckets" "dynamodb_tables")

		for resource_type in "${resource_types[@]}"; do
			local count
			count=$(echo "$inventory" | jq -r ".$resource_type.count")
			if [[ $count -gt 0 ]]; then
				echo -e "  ${RED}${resource_type}: ${count}${NC}"
				echo "$inventory" | jq -r ".$resource_type.items[]" | sed 's/^/    - /'
			fi
		done

		echo ""
		log_error "Run './platform/scripts/aws-nuclear-cleanup.sh' to force delete remaining resources"
		exit 1
	fi
}

# Main script
main() {
	check_prerequisites
	validate_aws_account

	case "${1:-}" in
	--export)
		if [[ -z "${2:-}" ]]; then
			log_error "Usage: $0 --export <output-file.json>"
			exit 1
		fi
		export_inventory "$2"
		;;
	--diff)
		if [[ -z "${2:-}" ]]; then
			log_error "Usage: $0 --diff <baseline-file.json>"
			exit 1
		fi
		diff_inventory "$2"
		;;
	--verify-empty)
		verify_empty
		;;
	"")
		collect_inventory
		;;
	*)
		log_error "Unknown option: $1"
		echo ""
		echo "Usage:"
		echo "  $0                    # Display current inventory"
		echo "  $0 --export file.json # Export to JSON"
		echo "  $0 --diff before.json # Compare against baseline"
		echo "  $0 --verify-empty     # Verify zero resources (exit 1 if any remain)"
		exit 1
		;;
	esac
}

main "$@"
