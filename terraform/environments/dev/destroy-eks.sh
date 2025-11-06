#!/bin/bash
# destroy-eks.sh - Destroy EKS infrastructure while keeping security services
#
# This script destroys the EKS cluster, VPC, and related resources
# but KEEPS CloudTrail, Budgets, and Terraform state to save costs.
#
# Usage: ./destroy-eks.sh
#
# Destroyed resources:
#   - EKS cluster ($2.40/day)
#   - EC2 worker nodes ($1.92/day)
#   - NAT Gateway ($1.08/day)
#   - Load Balancers ($0.54/day)
#   - VPC, subnets, security groups
#
# Preserved resources:
#   - CloudTrail (~$0.50/month)
#   - AWS Budgets (FREE)
#   - S3 state bucket (~$0.10/month)
#   - ECR repository (if images exist)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  EKS Infrastructure Destruction (Security Services Kept)  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirm AWS profile
echo -e "${YELLOW}→ Using AWS profile:${NC} ${AWS_PROFILE:-default}"
aws sts get-caller-identity || {
	echo -e "${RED}✗ AWS authentication failed. Set AWS_PROFILE or configure credentials.${NC}"
	exit 1
}
echo ""

# Confirm cluster exists
echo -e "${YELLOW}→ Checking for EKS cluster...${NC}"
CLUSTER_NAME=$(aws eks list-clusters --region us-west-2 --query 'clusters[0]' --output text 2>/dev/null || echo "")

if [ "$CLUSTER_NAME" == "None" ] || [ -z "$CLUSTER_NAME" ]; then
	echo -e "${GREEN}✓ No EKS cluster found. Already destroyed?${NC}"
	echo ""
	echo -e "${GREEN}Current state:${NC}"
	echo "  - EKS cluster: Not found"
	echo "  - CloudTrail: $(aws cloudtrail list-trails --region us-west-2 --query 'Trails[0].Name' --output text 2>/dev/null || echo 'Not found')"
	ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
	echo "  - Budgets: $(aws budgets describe-budgets --account-id "$ACCOUNT_ID" --query 'Budgets[0].BudgetName' --output text 2>/dev/null || echo 'Not found')"
	echo ""
	echo -e "${GREEN}💰 Estimated monthly cost: ~$0.60 (CloudTrail + Budgets)${NC}"
	exit 0
fi

echo -e "${YELLOW}✓ Found cluster: ${CLUSTER_NAME}${NC}"
echo ""

# Calculate current session cost
echo -e "${YELLOW}→ Calculating costs...${NC}"
echo -e "${RED}⚠️  EKS cluster running costs approximately:${NC}"
echo "    • $0.10/hour (EKS control plane)"
echo "    • $0.08/hour (EC2 nodes)"
echo "    • $0.045/hour (NAT Gateway)"
echo "    • $0.0225/hour (ALB, if created)"
echo "    ─────────────────────────────"
echo "    • $0.26/hour total"
echo ""

# Confirm destruction
echo -e "${RED}⚠️  This will destroy:${NC}"
echo "    ✗ EKS cluster (${CLUSTER_NAME})"
echo "    ✗ EC2 worker nodes"
echo "    ✗ VPC, subnets, NAT gateway"
echo "    ✗ Load balancers"
echo "    ✗ Security groups"
echo ""
echo -e "${GREEN}✓ This will KEEP:${NC}"
echo "    ✓ CloudTrail logs (audit history)"
echo "    ✓ AWS Budgets (cost monitoring)"
echo "    ✓ S3 state bucket (Terraform state)"
echo "    ✓ ECR repository (container images)"
echo ""
echo -e "${YELLOW}💰 After destruction, monthly cost: ~$0.60${NC}"
echo ""

read -p "Continue with destruction? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
	echo -e "${YELLOW}Destruction cancelled.${NC}"
	exit 1
fi

# Change to Terraform directory
cd "$(dirname "$0")"

echo -e "${YELLOW}→ Destroying Helm releases...${NC}"
terraform destroy -target=helm_release.aws_load_balancer_controller --auto-approve || true
echo ""

echo -e "${YELLOW}→ Destroying IAM roles...${NC}"
terraform destroy -target=module.load_balancer_controller_irsa_role --auto-approve || true
echo ""

echo -e "${YELLOW}→ Destroying EKS cluster...${NC}"
terraform destroy -target=module.eks --auto-approve
echo ""

echo -e "${YELLOW}→ Destroying VPC and networking...${NC}"
terraform destroy -target=module.vpc --auto-approve
echo ""

echo -e "${YELLOW}→ Destroying ECR lifecycle policy...${NC}"
terraform destroy -target=aws_ecr_lifecycle_policy.ml_platform_api --auto-approve || true
echo ""

# Verify destruction
echo -e "${YELLOW}→ Verifying destruction...${NC}"
REMAINING_CLUSTERS=$(aws eks list-clusters --region us-west-2 --query 'clusters | length(@)' --output text 2>/dev/null || echo "0")

if [ "$REMAINING_CLUSTERS" == "0" ]; then
	echo -e "${GREEN}✓ EKS cluster successfully destroyed${NC}"
else
	echo -e "${RED}⚠️  Warning: $REMAINING_CLUSTERS cluster(s) still exist${NC}"
fi
echo ""

# Show final state
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Destruction Complete                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Destroyed resources:${NC}"
echo "  - EKS cluster"
echo "  - EC2 nodes"
echo "  - VPC, subnets, NAT gateway"
echo "  - Load balancers"
echo ""
echo -e "${GREEN}✓ Preserved resources:${NC}"
echo "  - CloudTrail: $(aws cloudtrail list-trails --region us-west-2 --query 'Trails[0].Name' --output text 2>/dev/null || echo 'Not configured')"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  - Budgets: $(aws budgets describe-budgets --account-id "$ACCOUNT_ID" --query 'Budgets[0].BudgetName' --output text 2>/dev/null || echo 'Not configured')"
echo "  - S3 state bucket: ml-platform-terraform-state"
echo ""
echo -e "${GREEN}💰 New monthly cost: ~$0.60 (CloudTrail + S3)${NC}"
echo -e "${GREEN}💡 To recreate: terraform apply${NC}"
echo ""
