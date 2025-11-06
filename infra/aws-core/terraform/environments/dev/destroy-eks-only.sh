#!/bin/bash
# destroy-eks-only.sh - Destroy only EKS cluster, keep VPC for faster recreation
#
# This strategy:
#   - Destroys: EKS cluster ($2.40/day), EC2 nodes ($1.92/day)
#   - Keeps: VPC, NAT Gateway ($1.08/day), subnets (free)
#
# Benefits:
#   - Faster recreation: 8-10 minutes (vs. 15-20 minutes)
#   - Keeps networking in place
#
# Cost:
#   - With NAT running: $1.08/day ($32/month)
#   - Destroyed resources: $4.32/day savings
#   - Net cost: $1.60/day vs. $0.05/day (full destruction)
#
# Best for: Daily testing where 8-10 min startup is acceptable

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Destroy EKS Only (Keep VPC for Faster Restart)  ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Confirm AWS profile
echo -e "${YELLOW}→ Using AWS profile:${NC} ${AWS_PROFILE:-default}"
aws sts get-caller-identity || {
	echo -e "${RED}✗ AWS authentication failed.${NC}"
	exit 1
}
echo ""

# AWS region (configurable via environment variable)
AWS_REGION="${AWS_REGION:-us-west-2}"

# Check for cluster
CLUSTER_NAME=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[0]' --output text 2>/dev/null || echo "")

if [ "$CLUSTER_NAME" == "None" ] || [ -z "$CLUSTER_NAME" ]; then
	echo -e "${GREEN}✓ No EKS cluster found. Already destroyed.${NC}"
	exit 0
fi

echo -e "${YELLOW}✓ Found cluster: ${CLUSTER_NAME}${NC}"
echo ""

# Show cost comparison
echo -e "${RED}⚠️  This will destroy:${NC}"
echo "    ✗ EKS cluster ($0.10/hour = $2.40/day)"
echo "    ✗ EC2 worker nodes ($0.08/hour = $1.92/day)"
echo "    ✗ Load balancers ($0.0225/hour = $0.54/day)"
echo ""
echo -e "${YELLOW}⚠️  This will KEEP (for faster recreation):${NC}"
echo "    ✓ VPC, subnets, route tables (FREE)"
echo "    ✓ NAT Gateway ($0.045/hour = $1.08/day)"
echo "    ✓ Security groups (FREE)"
echo ""
echo -e "${YELLOW}💰 Cost comparison:${NC}"
echo "    • Full destruction: $0.05/day (CloudTrail only)"
echo "    • This approach: $1.60/day (CloudTrail + NAT)"
echo "    • Savings vs. 24/7 EKS: $4.67/day"
echo ""
echo -e "${GREEN}⏱️  Recreation time:${NC}"
echo "    • Full recreation: 15-20 minutes"
echo "    • With VPC kept: 8-10 minutes"
echo "    • Time saved: 7-10 minutes per session"
echo ""

read -p "Continue? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
	echo -e "${YELLOW}Cancelled.${NC}"
	exit 1
fi

cd "$(dirname "$0")"

echo -e "${YELLOW}→ Destroying EKS cluster (keeping VPC)...${NC}"
terraform destroy \
	-target=helm_release.aws_load_balancer_controller \
	-target=module.load_balancer_controller_irsa_role \
	-target=module.eks \
	--auto-approve

echo ""
echo -e "${GREEN}✓ EKS destroyed, VPC kept for faster recreation${NC}"
echo -e "${GREEN}💰 Current cost: ~$1.60/day${NC}"
echo -e "${GREEN}⏱️  Next 'terraform apply' will take 8-10 minutes${NC}"
echo ""
