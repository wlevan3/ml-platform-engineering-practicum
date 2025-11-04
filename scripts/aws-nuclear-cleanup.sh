#!/usr/bin/env bash
#
# AWS Nuclear Cleanup Script - Layer 2 Deletion Strategy
#
# WARNING: This script FORCE-DELETES all AWS resources tagged with the project.
# Only use this when Terraform destroy fails. No confirmation prompts.
#
# Usage:
#   ./scripts/aws-nuclear-cleanup.sh
#   ./scripts/aws-nuclear-cleanup.sh --dry-run  # Preview deletions without executing
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Proper IAM permissions for resource deletion
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
DRY_RUN=false

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

# ============================================================================
# DELETION FUNCTIONS (in dependency order)
# ============================================================================

# Delete Load Balancers (must be before target groups)
delete_load_balancers() {
	log_section "Deleting Load Balancers"

	local load_balancers
	load_balancers=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancers[].LoadBalancerArn' --output json 2>/dev/null | jq -r '.[]')

	local count=0
	for lb_arn in $load_balancers; do
		local tags
		tags=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --region "$AWS_REGION" 2>/dev/null | jq -r ".TagDescriptions[].Tags[] | select(.Key==\"$PROJECT_TAG_KEY\" and .Value==\"$PROJECT_TAG_VALUE\") | .Value")

		if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
			local lb_name
			lb_name=$(aws elbv2 describe-load-balancers --load-balancer-arns "$lb_arn" --region "$AWS_REGION" --query 'LoadBalancers[0].LoadBalancerName' --output text)

			if [[ "$DRY_RUN" == "true" ]]; then
				log_info "[DRY RUN] Would delete ALB: $lb_name"
			else
				log_info "Deleting ALB: $lb_name"
				if aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$AWS_REGION" 2>/dev/null; then
					log_success "✓ Deleted ALB: $lb_name"
					((count++))
				else
					log_warning "Failed to delete ALB: $lb_name (may already be deleted)"
				fi
			fi
		fi
	done

	if [[ "$DRY_RUN" != "true" ]] && [[ $count -gt 0 ]]; then
		log_info "Waiting 30s for ALBs to fully delete..."
		sleep 30
	fi

	log_success "Deleted $count Load Balancer(s)"
}

# Delete Target Groups (must be after ALBs)
delete_target_groups() {
	log_section "Deleting Target Groups"

	local target_groups
	target_groups=$(aws elbv2 describe-target-groups --region "$AWS_REGION" --query 'TargetGroups[].TargetGroupArn' --output json 2>/dev/null | jq -r '.[]')

	local count=0
	for tg_arn in $target_groups; do
		local tags
		tags=$(aws elbv2 describe-tags --resource-arns "$tg_arn" --region "$AWS_REGION" 2>/dev/null | jq -r ".TagDescriptions[].Tags[] | select(.Key==\"$PROJECT_TAG_KEY\" and .Value==\"$PROJECT_TAG_VALUE\") | .Value")

		if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
			local tg_name
			tg_name=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --region "$AWS_REGION" --query 'TargetGroups[0].TargetGroupName' --output text)

			if [[ "$DRY_RUN" == "true" ]]; then
				log_info "[DRY RUN] Would delete Target Group: $tg_name"
			else
				log_info "Deleting Target Group: $tg_name"
				if aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$AWS_REGION" 2>/dev/null; then
					log_success "✓ Deleted Target Group: $tg_name"
					((count++))
				else
					log_warning "Failed to delete Target Group: $tg_name (may already be deleted)"
				fi
			fi
		fi
	done

	log_success "Deleted $count Target Group(s)"
}

# Delete EKS Node Groups (must be before cluster)
delete_eks_node_groups() {
	log_section "Deleting EKS Node Groups"

	local clusters
	clusters=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output json 2>/dev/null | jq -r '.[]')

	local count=0
	for cluster in $clusters; do
		# Check if cluster has project tag
		local tags
		tags=$(aws eks list-tags-for-resource --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags.\"$PROJECT_TAG_KEY\" // empty")

		if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
			# Get all node groups for this cluster
			local node_groups
			node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --region "$AWS_REGION" --query 'nodegroups[]' --output json 2>/dev/null | jq -r '.[]')

			for ng in $node_groups; do
				if [[ "$DRY_RUN" == "true" ]]; then
					log_info "[DRY RUN] Would delete Node Group: $ng (cluster: $cluster)"
				else
					log_info "Deleting Node Group: $ng (cluster: $cluster)"
					if aws eks delete-nodegroup --cluster-name "$cluster" --nodegroup-name "$ng" --region "$AWS_REGION" 2>/dev/null; then
						log_success "✓ Initiated deletion of Node Group: $ng"
						((count++))
					else
						log_warning "Failed to delete Node Group: $ng (may already be deleted)"
					fi
				fi
			done
		fi
	done

	# Wait for node groups to delete
	if [[ "$DRY_RUN" != "true" ]] && [[ $count -gt 0 ]]; then
		log_info "Waiting for node groups to delete (this may take 5-10 minutes)..."

		for cluster in $clusters; do
			local tags
			tags=$(aws eks list-tags-for-resource --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags.\"$PROJECT_TAG_KEY\" // empty")

			if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
				local max_wait=600 # 10 minutes
				local wait_time=0

				while [[ $wait_time -lt $max_wait ]]; do
					local node_groups
					node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --region "$AWS_REGION" --query 'nodegroups[]' --output json 2>/dev/null | jq -r '.[]')

					if [[ -z "$node_groups" ]]; then
						log_success "✓ All node groups deleted for cluster: $cluster"
						break
					fi

					sleep 15
					wait_time=$((wait_time + 15))
					log_info "Still waiting for node groups to delete... (${wait_time}s elapsed)"
				done

				if [[ $wait_time -ge $max_wait ]]; then
					log_warning "Timeout waiting for node groups to delete. Proceeding anyway."
				fi
			fi
		done
	fi

	log_success "Deleted $count Node Group(s)"
}

# Delete EKS Clusters
delete_eks_clusters() {
	log_section "Deleting EKS Clusters"

	local clusters
	clusters=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output json 2>/dev/null | jq -r '.[]')

	local count=0
	for cluster in $clusters; do
		local tags
		tags=$(aws eks list-tags-for-resource --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags.\"$PROJECT_TAG_KEY\" // empty")

		if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
			if [[ "$DRY_RUN" == "true" ]]; then
				log_info "[DRY RUN] Would delete EKS cluster: $cluster"
			else
				log_info "Deleting EKS cluster: $cluster"
				if aws eks delete-cluster --name "$cluster" --region "$AWS_REGION" 2>/dev/null; then
					log_success "✓ Initiated deletion of EKS cluster: $cluster"
					((count++))
				else
					log_warning "Failed to delete EKS cluster: $cluster (may already be deleted)"
				fi
			fi
		fi
	done

	# Wait for clusters to delete
	if [[ "$DRY_RUN" != "true" ]] && [[ $count -gt 0 ]]; then
		log_info "Waiting for EKS clusters to delete (this may take 5-10 minutes)..."

		for cluster in $clusters; do
			local tags
			tags=$(aws eks list-tags-for-resource --resource-arn "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$cluster" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags.\"$PROJECT_TAG_KEY\" // empty")

			if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
				aws eks wait cluster-deleted --name "$cluster" --region "$AWS_REGION" 2>/dev/null || log_warning "Wait timeout for cluster: $cluster"
			fi
		done
	fi

	log_success "Deleted $count EKS Cluster(s)"
}

# Delete EC2 Instances
delete_ec2_instances() {
	log_section "Deleting EC2 Instances"

	local instances
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	instances=$(aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output json | jq -r '.[]')

	local count=0
	for instance_id in $instances; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would terminate EC2 instance: $instance_id"
		else
			log_info "Terminating EC2 instance: $instance_id"
			if aws ec2 terminate-instances --instance-ids "$instance_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Terminated EC2 instance: $instance_id"
				((count++))
			else
				log_warning "Failed to terminate EC2 instance: $instance_id (may already be terminated)"
			fi
		fi
	done

	# Wait for instances to terminate
	if [[ "$DRY_RUN" != "true" ]] && [[ $count -gt 0 ]]; then
		log_info "Waiting for EC2 instances to terminate..."
		for instance_id in $instances; do
			aws ec2 wait instance-terminated --instance-ids "$instance_id" --region "$AWS_REGION" 2>/dev/null || log_warning "Wait timeout for instance: $instance_id"
		done
	fi

	log_success "Deleted $count EC2 Instance(s)"
}

# Delete NAT Gateways (must be before subnets)
delete_nat_gateways() {
	log_section "Deleting NAT Gateways"

	local nat_gateways
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	nat_gateways=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" --filter "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output json | jq -r '.[]')

	local count=0
	for nat_id in $nat_gateways; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete NAT Gateway: $nat_id"
		else
			log_info "Deleting NAT Gateway: $nat_id"
			if aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Initiated deletion of NAT Gateway: $nat_id"
				((count++))
			else
				log_warning "Failed to delete NAT Gateway: $nat_id (may already be deleted)"
			fi
		fi
	done

	# Wait for NAT gateways to delete
	if [[ "$DRY_RUN" != "true" ]] && [[ $count -gt 0 ]]; then
		log_info "Waiting for NAT Gateways to delete (this may take 2-3 minutes)..."
		sleep 120 # NAT gateways take time to delete
	fi

	log_success "Deleted $count NAT Gateway(s)"
}

# Release Elastic IPs
delete_elastic_ips() {
	log_section "Releasing Elastic IPs"

	local eips
	eips=$(aws ec2 describe-addresses --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'Addresses[].AllocationId' --output json | jq -r '.[]')

	local count=0
	for allocation_id in $eips; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would release Elastic IP: $allocation_id"
		else
			log_info "Releasing Elastic IP: $allocation_id"
			if aws ec2 release-address --allocation-id "$allocation_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Released Elastic IP: $allocation_id"
				((count++))
			else
				log_warning "Failed to release Elastic IP: $allocation_id (may be in use or already released)"
			fi
		fi
	done

	log_success "Released $count Elastic IP(s)"
}

# Delete EBS Volumes
delete_ebs_volumes() {
	log_section "Deleting EBS Volumes"

	local volumes
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	volumes=$(aws ec2 describe-volumes --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'Volumes[?State!=`deleted`].VolumeId' --output json | jq -r '.[]')

	local count=0
	for volume_id in $volumes; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete EBS volume: $volume_id"
		else
			log_info "Deleting EBS volume: $volume_id"
			if aws ec2 delete-volume --volume-id "$volume_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Deleted EBS volume: $volume_id"
				((count++))
			else
				log_warning "Failed to delete EBS volume: $volume_id (may be attached or already deleted)"
			fi
		fi
	done

	log_success "Deleted $count EBS Volume(s)"
}

# Delete Security Groups (must be after EC2 instances and ALBs)
delete_security_groups() {
	log_section "Deleting Security Groups"

	local security_groups
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	security_groups=$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output json | jq -r '.[]')

	local count=0
	for sg_id in $security_groups; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete Security Group: $sg_id"
		else
			log_info "Deleting Security Group: $sg_id"

			# First, remove all ingress rules
			aws ec2 revoke-security-group-ingress --group-id "$sg_id" --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$AWS_REGION" --query 'SecurityGroups[0].IpPermissions' --output json)" --region "$AWS_REGION" 2>/dev/null || true

			# Then, remove all egress rules
			aws ec2 revoke-security-group-egress --group-id "$sg_id" --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$AWS_REGION" --query 'SecurityGroups[0].IpPermissionsEgress' --output json)" --region "$AWS_REGION" 2>/dev/null || true

			# Finally, delete the security group
			if aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Deleted Security Group: $sg_id"
				((count++))
			else
				log_warning "Failed to delete Security Group: $sg_id (may be in use or already deleted)"
			fi
		fi
	done

	log_success "Deleted $count Security Group(s)"
}

# Delete Subnets (must be after NAT gateways, instances, ALBs)
delete_subnets() {
	log_section "Deleting Subnets"

	local subnets
	subnets=$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'Subnets[].SubnetId' --output json | jq -r '.[]')

	local count=0
	for subnet_id in $subnets; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete Subnet: $subnet_id"
		else
			log_info "Deleting Subnet: $subnet_id"
			if aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Deleted Subnet: $subnet_id"
				((count++))
			else
				log_warning "Failed to delete Subnet: $subnet_id (may have dependencies or already deleted)"
			fi
		fi
	done

	log_success "Deleted $count Subnet(s)"
}

# Delete Route Tables (must be after subnets)
delete_route_tables() {
	log_section "Deleting Route Tables"

	local route_tables
	route_tables=$(aws ec2 describe-route-tables --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'RouteTables[].RouteTableId' --output json | jq -r '.[]')

	local count=0
	for rt_id in $route_tables; do
		# Check if this is the main route table (can't be deleted)
		local is_main
		# shellcheck disable=SC2016
		# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
		is_main=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --region "$AWS_REGION" --query 'RouteTables[0].Associations[?Main==`true`]' --output json | jq 'length')

		if [[ "$is_main" -gt 0 ]]; then
			log_info "Skipping main route table: $rt_id (cannot be deleted)"
			continue
		fi

		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete Route Table: $rt_id"
		else
			log_info "Deleting Route Table: $rt_id"

			# Disassociate all subnets first
			local associations
			associations=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --region "$AWS_REGION" --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output json | jq -r '.[]')

			for assoc_id in $associations; do
				aws ec2 disassociate-route-table --association-id "$assoc_id" --region "$AWS_REGION" 2>/dev/null || true
			done

			if aws ec2 delete-route-table --route-table-id "$rt_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Deleted Route Table: $rt_id"
				((count++))
			else
				log_warning "Failed to delete Route Table: $rt_id (may have dependencies or already deleted)"
			fi
		fi
	done

	log_success "Deleted $count Route Table(s)"
}

# Delete Internet Gateways (must be before VPC)
delete_internet_gateways() {
	log_section "Deleting Internet Gateways"

	local igws
	igws=$(aws ec2 describe-internet-gateways --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'InternetGateways[].InternetGatewayId' --output json | jq -r '.[]')

	local count=0
	for igw_id in $igws; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete Internet Gateway: $igw_id"
		else
			log_info "Deleting Internet Gateway: $igw_id"

			# Detach from VPCs first
			local vpc_id
			vpc_id=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" --region "$AWS_REGION" --query 'InternetGateways[0].Attachments[0].VpcId' --output text 2>/dev/null || echo "")

			if [[ -n "$vpc_id" ]] && [[ "$vpc_id" != "None" ]]; then
				aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$AWS_REGION" 2>/dev/null || true
			fi

			if aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Deleted Internet Gateway: $igw_id"
				((count++))
			else
				log_warning "Failed to delete Internet Gateway: $igw_id (may be attached or already deleted)"
			fi
		fi
	done

	log_success "Deleted $count Internet Gateway(s)"
}

# Delete VPCs (must be last for network resources)
delete_vpcs() {
	log_section "Deleting VPCs"

	local vpcs
	# shellcheck disable=SC2016
	# Note: Backticks in JMESPath query are correct syntax (not shell expansion)
	vpcs=$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:$PROJECT_TAG_KEY,Values=$PROJECT_TAG_VALUE" --query 'Vpcs[?IsDefault==`false`].VpcId' --output json | jq -r '.[]')

	local count=0
	for vpc_id in $vpcs; do
		if [[ "$DRY_RUN" == "true" ]]; then
			log_info "[DRY RUN] Would delete VPC: $vpc_id"
		else
			log_info "Deleting VPC: $vpc_id"
			if aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$AWS_REGION" 2>/dev/null; then
				log_success "✓ Deleted VPC: $vpc_id"
				((count++))
			else
				log_warning "Failed to delete VPC: $vpc_id (may have dependencies or already deleted)"
			fi
		fi
	done

	log_success "Deleted $count VPC(s)"
}

# Delete ECR Repositories
delete_ecr_repositories() {
	log_section "Deleting ECR Repositories"

	local repos
	repos=$(aws ecr describe-repositories --region "$AWS_REGION" --query 'repositories[].repositoryName' --output json 2>/dev/null | jq -r '.[]')

	local count=0
	for repo in $repos; do
		local tags
		tags=$(aws ecr list-tags-for-resource --resource-arn "arn:aws:ecr:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):repository/$repo" --region "$AWS_REGION" 2>/dev/null | jq -r ".tags[] | select(.Key==\"$PROJECT_TAG_KEY\" and .Value==\"$PROJECT_TAG_VALUE\") | .Value")

		if [[ "$tags" == "$PROJECT_TAG_VALUE" ]]; then
			if [[ "$DRY_RUN" == "true" ]]; then
				log_info "[DRY RUN] Would delete ECR repository: $repo"
			else
				log_info "Deleting ECR repository: $repo"
				if aws ecr delete-repository --repository-name "$repo" --force --region "$AWS_REGION" 2>/dev/null; then
					log_success "✓ Deleted ECR repository: $repo"
					((count++))
				else
					log_warning "Failed to delete ECR repository: $repo (may already be deleted)"
				fi
			fi
		fi
	done

	log_success "Deleted $count ECR Repository(ies)"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
	# Parse arguments
	if [[ "${1:-}" == "--dry-run" ]]; then
		DRY_RUN=true
		log_warning "DRY RUN MODE - No resources will be deleted"
	fi

	check_prerequisites
	validate_aws_account

	if [[ "$DRY_RUN" != "true" ]]; then
		log_warning "⚠️  WARNING: This will FORCE-DELETE all AWS resources tagged with:"
		log_warning "   $PROJECT_TAG_KEY=$PROJECT_TAG_VALUE"
		log_warning ""
		log_warning "Press Ctrl+C within 10 seconds to cancel..."
		sleep 10
	fi

	log_section "Starting Nuclear Cleanup"
	log_info "AWS Account: $EXPECTED_ACCOUNT_ID (KodeKloud sandbox)"
	log_info "AWS Region: $AWS_REGION"
	log_info "Project Tag: $PROJECT_TAG_KEY=$PROJECT_TAG_VALUE"
	echo ""

	# Delete resources in proper dependency order
	delete_load_balancers
	delete_target_groups
	delete_eks_node_groups
	delete_eks_clusters
	delete_ec2_instances
	delete_nat_gateways
	delete_elastic_ips
	delete_ebs_volumes
	delete_security_groups
	delete_subnets
	delete_route_tables
	delete_internet_gateways
	delete_vpcs
	delete_ecr_repositories

	log_section "Nuclear Cleanup Complete"

	if [[ "$DRY_RUN" == "true" ]]; then
		log_success "DRY RUN completed - no resources were deleted"
	else
		log_success "All tagged resources have been deleted!"
		log_info ""
		log_info "Run './scripts/aws-resource-inventory.sh --verify-empty' to verify cleanup"
	fi
}

main "$@"
