#!/usr/bin/env bash
# =============================================================================
# Emergency AWS Resource Cleanup
# =============================================================================
# Destroys ALL resources (failed and successful) - use with extreme caution
# For failed node groups only, use: cleanup-failed-nodegroups.sh
# =============================================================================

set -euo pipefail

REGION="us-west-2"
CLUSTER_NAME="ml-platform-dev"
DRY_RUN="${DRY_RUN:-false}"

# Safety checks - only allow specific AWS account and user
readonly REQUIRED_ACCOUNT_ID="984479408136"
readonly REQUIRED_USER="admin-wjlevan"
readonly REQUIRED_REGION="us-west-2"

# AWS cost estimates (monthly, rounded for rough estimation)
readonly NAT_GATEWAY_MONTHLY_COST=32  # AWS NAT Gateway: ~$0.045/hr × 730 hrs
readonly EKS_CLUSTER_MONTHLY_COST=73  # AWS EKS cluster: $0.10/hr × 730 hrs
readonly INSTANCE_MONTHLY_COST_ESTIMATE=1  # Rough average for cost estimation

# Logging setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/emergency-cleanup-$(date +%Y%m%d_%H%M%S).log"

# Log to both console and file
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters for summary
TOTAL_DELETED=0
TOTAL_FAILED=0
START_TIME=$(date +%s)

# VPC ID - captured before cluster deletion
VPC_ID=""

log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}ℹ${NC} $1"
}

log_warn() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}⚠${NC} $1" >&2
}

log_error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}✗${NC} $1" >&2
}

log_success() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}✓${NC} $1"
}

show_progress() {
    local current=$1
    local total=$2
    local item=$3

    if [[ $total -eq 0 ]]; then
        return
    fi

    local percent=$((current * 100 / total))
    local bar_length=40
    local filled=$((current * bar_length / total))

    printf "\r[%s%s] %d%% (%d/%d) %s" \
        "$(printf '#%.0s' $(seq 1 $filled) 2>/dev/null || echo '')" \
        "$(printf ' %.0s' $(seq 1 $((bar_length - filled))) 2>/dev/null || echo '')" \
        "$percent" "$current" "$total" "$item"
}

delete_with_retry() {
    local resource_type=$1
    local resource_id=$2
    shift 2
    local delete_cmd=("$@")
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if [[ $retry -gt 0 ]]; then
            log_info "Retry $retry/$max_retries for $resource_type: $resource_id"
        fi

        if "${delete_cmd[@]}" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            return 0
        else
            retry=$((retry + 1))
            if [[ $retry -lt $max_retries ]]; then
                sleep 5
            fi
        fi
    done

    log_error "Failed to delete $resource_type: $resource_id after $max_retries attempts"
    return 1
}

verify_deletion() {
    local resource_type=$1
    local resource_id=$2
    shift 2
    local check_cmd=("$@")

    if "${check_cmd[@]}" 2>/dev/null | grep -iq "delet\|terminat"; then
        return 0
    else
        return 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    command -v aws >/dev/null || { log_error "AWS CLI not installed"; exit 1; }
    command -v jq >/dev/null || { log_error "jq not installed"; exit 1; }

    # Verify AWS account ID
    local account_id
    account_id=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
    if [[ "$account_id" != "$REQUIRED_ACCOUNT_ID" ]]; then
        log_error "SAFETY CHECK FAILED: AWS Account ID mismatch"
        log_error "Expected: $REQUIRED_ACCOUNT_ID"
        log_error "Got: $account_id"
        log_error "This script is restricted to account $REQUIRED_ACCOUNT_ID only"
        exit 1
    fi

    # Verify AWS user
    local user_arn
    user_arn=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "")
    if [[ ! "$user_arn" =~ $REQUIRED_USER ]]; then
        log_error "SAFETY CHECK FAILED: AWS User mismatch"
        log_error "Expected user: $REQUIRED_USER"
        log_error "Got ARN: $user_arn"
        log_error "This script is restricted to user $REQUIRED_USER only"
        exit 1
    fi

    # Verify region
    if [[ "$REGION" != "$REQUIRED_REGION" ]]; then
        log_error "SAFETY CHECK FAILED: Region mismatch"
        log_error "Expected: $REQUIRED_REGION"
        log_error "Got: $REGION"
        log_error "This script is restricted to $REQUIRED_REGION only"
        exit 1
    fi

    log_success "Prerequisites OK"
    log_success "AWS Account: $account_id"
    log_success "AWS User: $user_arn"
    log_success "Region: $REGION"
}

get_vpc_id() {
    aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
        --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo ""
}

get_resource_counts() {
    local ng_count lb_count nat_count eip_count instance_count vpc_count

    ng_count=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'length(nodegroups)' --output text 2>/dev/null || echo "0")

    # Get VPC ID for proper filtering
    local vpc_id
    vpc_id=$(get_vpc_id)

    # Count resources properly scoped to cluster VPC
    if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
        nat_count=$(aws ec2 describe-nat-gateways --region "$REGION" \
            --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
            --query 'length(NatGateways)' --output text 2>/dev/null || echo "0")
    else
        nat_count="0"
    fi

    # Count cluster-tagged load balancers
    lb_count=$(aws elbv2 describe-load-balancers --region "$REGION" 2>/dev/null | \
        jq --arg cluster "$CLUSTER_NAME" '[.LoadBalancers[].LoadBalancerArn] | length' || echo "0")

    # shellcheck disable=SC2016
    eip_count=$(aws ec2 describe-addresses --region "$REGION" \
        --query 'length(Addresses[?Tags[?Key==`ManagedBy` && Value==`Terraform`]])' \
        --output text 2>/dev/null || echo "0")

    instance_count=$(aws ec2 describe-instances --region "$REGION" \
        --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" \
                  "Name=tag:Cluster,Values=$CLUSTER_NAME" \
        --query 'length(Reservations[].Instances[])' --output text 2>/dev/null || echo "0")

    vpc_count=$(if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then echo "1"; else echo "0"; fi)

    echo "$ng_count|$lb_count|$nat_count|$eip_count|$instance_count|$vpc_count"
}

show_summary() {
    local counts
    counts=$(get_resource_counts)
    IFS='|' read -r ng_count lb_count nat_count eip_count instance_count vpc_count <<< "$counts"

    echo ""
    log_warn "=========================================="
    log_warn "EMERGENCY CLEANUP - ALL RESOURCES"
    log_warn "=========================================="
    echo ""
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $REGION"
    log_info "Log file: $LOG_FILE"
    echo ""
    echo "Resources to delete:"
    echo "  • Node Groups: $ng_count (ALL - failed and successful)"
    echo "  • EC2 Instances: $instance_count"
    echo "  • NAT Gateways: $nat_count (~\$$NAT_GATEWAY_MONTHLY_COST/month each)"
    echo "  • Elastic IPs: $eip_count"
    echo "  • Load Balancers: $lb_count"
    echo "  • EKS Cluster: 1 (~\$$EKS_CLUSTER_MONTHLY_COST/month)"
    echo "  • VPC + Subnets + Security Groups: $vpc_count"
    echo ""

    local monthly_cost=$((nat_count * NAT_GATEWAY_MONTHLY_COST + EKS_CLUSTER_MONTHLY_COST + instance_count * INSTANCE_MONTHLY_COST_ESTIMATE))
    log_warn "Estimated monthly cost: ~\$$monthly_cost"
    echo ""
}

delete_all_nodegroups() {
    log_info "Step 1: Deleting ALL node groups..."

    local nodegroups
    nodegroups=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" \
        --query 'nodegroups[]' --output text 2>/dev/null || echo "")

    if [[ -z "$nodegroups" ]]; then
        log_info "  No node groups found"
        return 0
    fi

    local ng_array
    read -ra ng_array <<< "$nodegroups"
    local total=${#ng_array[@]}
    local current=0
    local deleted=0
    local failed=0
    local pids=()
    local results_file
    results_file=$(mktemp)

    # Parallel deletion
    for ng in "${ng_array[@]}"; do
        current=$((current + 1))

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "  [DRY RUN] Would delete: $ng"
            deleted=$((deleted + 1))
        else
            (
                if delete_with_retry "node group" "$ng" \
                    aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" \
                    --nodegroup-name "$ng" --region "$REGION"; then
                    echo "$ng:success" >> "$results_file"
                else
                    echo "$ng:failed" >> "$results_file"
                fi
            ) &
            pids+=($!)

            # Limit concurrent deletions to 5
            if [[ ${#pids[@]} -ge 5 ]]; then
                wait "${pids[@]}" 2>/dev/null || true
                pids=()
            fi
        fi
    done

    # Wait for remaining deletions
    if [[ ${#pids[@]} -gt 0 ]]; then
        wait "${pids[@]}" 2>/dev/null || true
    fi

    # Count results
    if [[ "$DRY_RUN" != "true" && -f "$results_file" ]]; then
        deleted=$(grep -c ":success" "$results_file" 2>/dev/null || echo "0")
        failed=$(grep -c ":failed" "$results_file" 2>/dev/null || echo "0")
        rm -f "$results_file"

        log_info "  Waiting for node group deletions to complete..."
        for ng in "${ng_array[@]}"; do
            show_progress $((deleted + failed)) "$total" "$ng"
            aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$ng" --region "$REGION" 2>/dev/null || true
        done
        echo ""  # Newline after progress bar
    fi

    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    log_success "Node groups: $deleted deleted, $failed failed"
}

delete_ec2_instances() {
    log_info "Step 2: Terminating EC2 instances..."

    local instances
    instances=$(aws ec2 describe-instances --region "$REGION" \
        --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" \
                  "Name=tag:Cluster,Values=$CLUSTER_NAME" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")

    if [[ -z "$instances" ]]; then
        log_info "  No instances found"
        return 0
    fi

    local instance_array
    read -ra instance_array <<< "$instances"
    local total=${#instance_array[@]}
    local current=0
    local deleted=0
    local failed=0

    for instance in "${instance_array[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "$instance"

        if [[ "$DRY_RUN" == "true" ]]; then
            deleted=$((deleted + 1))
        else
            if delete_with_retry "EC2 instance" "$instance" \
                aws ec2 terminate-instances --instance-ids "$instance" --region "$REGION"; then
                deleted=$((deleted + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    echo ""  # Newline after progress bar

    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    log_success "EC2 instances: $deleted deleted, $failed failed"
}

delete_cluster() {
    log_info "Step 3: Deleting EKS cluster..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "  [DRY RUN] Would delete cluster: $CLUSTER_NAME"
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
    else
        if delete_with_retry "EKS cluster" "$CLUSTER_NAME" \
            aws eks delete-cluster --name "$CLUSTER_NAME" --region "$REGION"; then
            log_info "  Waiting for cluster deletion (this may take 5-10 minutes)..."
            aws eks wait cluster-deleted --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || true
            TOTAL_DELETED=$((TOTAL_DELETED + 1))
            log_success "EKS cluster deleted"
        else
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
    fi
}

delete_load_balancers() {
    log_info "Step 4: Deleting Load Balancers..."

    # Get cluster-tagged load balancers only
    local lbs
    lbs=$(aws elbv2 describe-load-balancers --region "$REGION" 2>/dev/null | \
        jq -r '.LoadBalancers[].LoadBalancerArn' || echo "")

    if [[ -z "$lbs" ]]; then
        log_info "  No load balancers found"
        return 0
    fi

    # Filter by cluster tags
    local filtered_lbs=""
    for lb_arn in $lbs; do
        local tags
        tags=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --region "$REGION" 2>/dev/null || echo "")
        if echo "$tags" | jq -e --arg cluster "$CLUSTER_NAME" \
            '.TagDescriptions[].Tags[] | select(.Key == "kubernetes.io/cluster/\($cluster)")' >/dev/null 2>&1; then
            filtered_lbs="$filtered_lbs $lb_arn"
            log_info "  Found cluster load balancer: $(basename "$lb_arn")"
        fi
    done

    if [[ -z "$filtered_lbs" ]]; then
        log_info "  No cluster-tagged load balancers found"
        return 0
    fi

    local lb_array
    read -ra lb_array <<< "$filtered_lbs"
    local total=${#lb_array[@]}
    local current=0
    local deleted=0
    local failed=0

    for lb in "${lb_array[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "$(basename "$lb")"

        if [[ "$DRY_RUN" == "true" ]]; then
            deleted=$((deleted + 1))
        else
            if delete_with_retry "load balancer" "$lb" \
                aws elbv2 delete-load-balancer --load-balancer-arn "$lb" --region "$REGION"; then
                deleted=$((deleted + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    echo ""  # Newline after progress bar

    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    log_success "Load balancers: $deleted deleted, $failed failed"
}

delete_nat_gateways() {
    log_info "Step 5: Deleting NAT Gateways..."

    # Use globally captured VPC ID (set before cluster deletion)
    local vpc_id="$VPC_ID"

    if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
        log_warn "  Could not determine VPC ID - skipping NAT gateway deletion for safety"
        return 0
    fi

    log_info "  Filtering NAT gateways by VPC: $vpc_id"
    local nat_gws
    nat_gws=$(aws ec2 describe-nat-gateways --region "$REGION" \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
        --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "")

    if [[ -z "$nat_gws" ]]; then
        log_info "  No NAT Gateways found in VPC $vpc_id"
        return 0
    fi

    local nat_array
    read -ra nat_array <<< "$nat_gws"
    local total=${#nat_array[@]}
    local current=0
    local deleted=0
    local failed=0

    for nat in "${nat_array[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "$nat"

        if [[ "$DRY_RUN" == "true" ]]; then
            deleted=$((deleted + 1))
        else
            if delete_with_retry "NAT gateway" "$nat" \
                aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION"; then

                # Verify deletion started
                if verify_deletion "NAT gateway" "$nat" \
                    aws ec2 describe-nat-gateways --nat-gateway-ids "$nat" \
                    --region "$REGION" --query 'NatGateways[0].State' --output text; then
                    deleted=$((deleted + 1))
                else
                    log_warn "  NAT Gateway $nat deletion not confirmed"
                    failed=$((failed + 1))
                fi
            else
                failed=$((failed + 1))
            fi
        fi
    done
    echo ""  # Newline after progress bar

    if [[ "$DRY_RUN" != "true" && $deleted -gt 0 ]]; then
        log_info "  Waiting 60s for NAT Gateway deletion to propagate..."
        sleep 60
    fi

    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    log_success "NAT gateways: $deleted deleted, $failed failed"
}

delete_elastic_ips() {
    log_info "Step 6: Releasing Elastic IPs..."

    local eips
    # shellcheck disable=SC2016
    eips=$(aws ec2 describe-addresses --region "$REGION" \
        --query 'Addresses[?Tags[?Key==`ManagedBy` && Value==`Terraform`]].AllocationId' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$eips" ]]; then
        log_info "  No Elastic IPs found"
        return 0
    fi

    local eip_array
    read -ra eip_array <<< "$eips"
    local total=${#eip_array[@]}
    local current=0
    local deleted=0
    local failed=0

    for eip in "${eip_array[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "$eip"

        if [[ "$DRY_RUN" == "true" ]]; then
            deleted=$((deleted + 1))
        else
            if delete_with_retry "Elastic IP" "$eip" \
                aws ec2 release-address --allocation-id "$eip" --region "$REGION"; then
                deleted=$((deleted + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    echo ""  # Newline after progress bar

    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    log_success "Elastic IPs: $deleted deleted, $failed failed"
}

delete_vpc_resources() {
    log_info "Step 7: Deleting VPC resources..."

    # Use globally captured VPC ID (set before cluster deletion)
    local vpc_id="$VPC_ID"

    if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
        log_info "  No VPC found for cluster"
        return 0
    fi

    log_info "  VPC ID: $vpc_id"

    # Delete VPC Endpoints first (they block subnet deletion)
    log_info "  Deleting VPC Endpoints..."
    local vpce_ids
    vpce_ids=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || echo "")

    if [[ -n "$vpce_ids" ]]; then
        local vpce_array
        read -ra vpce_array <<< "$vpce_ids"
        local vpce_count=${#vpce_array[@]}

        if [[ "$DRY_RUN" == "true" ]]; then
            for vpce in "${vpce_array[@]}"; do
                log_info "    [DRY RUN] Would delete VPC endpoint: $vpce"
            done
        else
            log_info "    Found $vpce_count VPC endpoint(s), deleting..."
            # Delete all VPC endpoints at once (more efficient)
            if aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "${vpce_array[@]}" --region "$REGION" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
                log_info "    Initiated deletion of $vpce_count VPC endpoint(s)"
                TOTAL_DELETED=$((TOTAL_DELETED + vpce_count))

                # Wait for VPC endpoints to delete (they hold ENIs)
                log_info "    Waiting 90s for VPC endpoints to fully delete..."
                sleep 90
            else
                log_error "    Failed to delete some VPC endpoints"
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
            fi
        fi
    fi

    # Delete Internet Gateway
    log_info "  Deleting Internet Gateway..."
    local igw_id
    igw_id=$(aws ec2 describe-internet-gateways --region "$REGION" \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")

    if [[ -n "$igw_id" && "$igw_id" != "None" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "    [DRY RUN] Would delete IGW: $igw_id"
        else
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" \
                --vpc-id "$vpc_id" --region "$REGION" 2>/dev/null || true
            if delete_with_retry "Internet Gateway" "$igw_id" \
                aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION"; then
                TOTAL_DELETED=$((TOTAL_DELETED + 1))
            else
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
            fi
        fi
    fi

    # Delete Subnets
    log_info "  Deleting Subnets..."
    local subnet_ids
    subnet_ids=$(aws ec2 describe-subnets --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")

    if [[ -n "$subnet_ids" ]]; then
        local subnet_array
        read -ra subnet_array <<< "$subnet_ids"
        for subnet in "${subnet_array[@]}"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "    [DRY RUN] Would delete subnet: $subnet"
            else
                if delete_with_retry "subnet" "$subnet" \
                    aws ec2 delete-subnet --subnet-id "$subnet" --region "$REGION"; then
                    TOTAL_DELETED=$((TOTAL_DELETED + 1))
                else
                    TOTAL_FAILED=$((TOTAL_FAILED + 1))
                fi
            fi
        done
    fi

    # Delete Security Groups (except default)
    log_info "  Deleting Security Groups..."
    local sg_ids
    # shellcheck disable=SC2016
    sg_ids=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")

    if [[ -n "$sg_ids" ]]; then
        local sg_array
        read -ra sg_array <<< "$sg_ids"
        for sg in "${sg_array[@]}"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "    [DRY RUN] Would delete security group: $sg"
            else
                if delete_with_retry "security group" "$sg" \
                    aws ec2 delete-security-group --group-id "$sg" --region "$REGION"; then
                    TOTAL_DELETED=$((TOTAL_DELETED + 1))
                else
                    TOTAL_FAILED=$((TOTAL_FAILED + 1))
                fi
            fi
        done
    fi

    # Delete Route Tables (except main)
    log_info "  Deleting Route Tables..."
    local rt_ids
    # shellcheck disable=SC2016
    rt_ids=$(aws ec2 describe-route-tables --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")

    if [[ -n "$rt_ids" ]]; then
        local rt_array
        read -ra rt_array <<< "$rt_ids"
        for rt in "${rt_array[@]}"; do
            # Disassociate first
            local assoc_ids
            assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rt" --region "$REGION" \
                --query 'RouteTables[0].Associations[*].RouteTableAssociationId' --output text 2>/dev/null || echo "")
            for assoc in $assoc_ids; do
                aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION" 2>/dev/null || true
            done

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "    [DRY RUN] Would delete route table: $rt"
            else
                if delete_with_retry "route table" "$rt" \
                    aws ec2 delete-route-table --route-table-id "$rt" --region "$REGION"; then
                    TOTAL_DELETED=$((TOTAL_DELETED + 1))
                else
                    TOTAL_FAILED=$((TOTAL_FAILED + 1))
                fi
            fi
        done
    fi

    # Delete VPC
    log_info "  Deleting VPC..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "    [DRY RUN] Would delete VPC: $vpc_id"
    else
        if delete_with_retry "VPC" "$vpc_id" \
            aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION"; then
            TOTAL_DELETED=$((TOTAL_DELETED + 1))
            log_success "VPC deleted: $vpc_id"
        else
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            log_error "Failed to delete VPC: $vpc_id (may have dependencies)"
        fi
    fi
}

show_final_summary() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    log_info "=========================================="
    log_info "CLEANUP SUMMARY"
    log_info "=========================================="
    log_success "Resources deleted: $TOTAL_DELETED"
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        log_error "Resources failed: $TOTAL_FAILED"
    else
        log_info "Resources failed: $TOTAL_FAILED"
    fi
    log_info "Execution time: ${minutes}m ${seconds}s"
    log_info "Log file: $LOG_FILE"
    echo ""
}

main() {
    echo ""
    log_warn "⚠️  EMERGENCY CLEANUP - DESTROYS ALL RESOURCES ⚠️"
    echo ""

    check_prerequisites

    # Capture VPC ID before cluster deletion (needed for NAT gateways and VPC cleanup)
    VPC_ID=$(get_vpc_id)
    if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
        log_info "VPC ID captured for cleanup: $VPC_ID"
    else
        log_warn "No VPC found for cluster - VPC resource cleanup will be skipped"
    fi

    log_info "Emergency cleanup started at $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "DRY_RUN mode: $DRY_RUN"
    echo ""

    show_summary

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        echo ""
    else
        log_error "THIS WILL DELETE EVERYTHING - CANNOT BE UNDONE"
        read -r -p "Type 'DELETE EVERYTHING' to confirm: " confirm

        if [[ "$confirm" != "DELETE EVERYTHING" ]]; then
            log_info "Aborted"
            exit 0
        fi
    fi

    echo ""
    delete_all_nodegroups
    delete_ec2_instances
    delete_cluster
    delete_load_balancers
    delete_nat_gateways
    delete_elastic_ips
    delete_vpc_resources

    show_final_summary

    if [[ $TOTAL_FAILED -eq 0 ]]; then
        log_success "✅ Emergency cleanup complete - all resources deleted"
    else
        log_warn "⚠️  Emergency cleanup complete with $TOTAL_FAILED failures"
        log_warn "Check log file for details: $LOG_FILE"
    fi
    echo ""
}

main "$@"
