#!/bin/bash
# deploy-to-ecr.sh - Build and push Docker image to ECR
#
# Usage: ./deploy-to-ecr.sh [IMAGE_TAG]
#   IMAGE_TAG: Version tag (default: v1.0.0)
#
# Example:
#   ./deploy-to-ecr.sh v1.0.0
#   ./deploy-to-ecr.sh v1.1.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║         Build and Push Docker Image to ECR                ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Change to Terraform directory
cd "$(dirname "$0")"

# Get image tag from argument or use default
IMAGE_TAG="${1:-v1.0.0}"
AWS_REGION="us-west-2"

echo -e "${YELLOW}→ Getting ECR repository URL...${NC}"
ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null)

if [ -z "$ECR_REPO" ]; then
	echo -e "${RED}✗ Failed to get ECR repository URL${NC}"
	echo -e "${RED}  Make sure Terraform has been applied first: terraform apply${NC}"
	exit 1
fi

echo -e "${GREEN}✓ ECR Repository: ${ECR_REPO}${NC}"
echo ""

# Authenticate Docker to ECR
echo -e "${YELLOW}→ Authenticating Docker to ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | \
	docker login --username AWS --password-stdin "${ECR_REPO}"
echo ""

# Build Docker image
echo -e "${YELLOW}→ Building Docker image: ml-platform-api:${IMAGE_TAG}${NC}"
cd ../../../  # Go to project root
docker build -t "ml-platform-api:${IMAGE_TAG}" .
echo ""

# Tag for ECR
echo -e "${YELLOW}→ Tagging image for ECR: ${ECR_REPO}:${IMAGE_TAG}${NC}"
docker tag "ml-platform-api:${IMAGE_TAG}" "${ECR_REPO}:${IMAGE_TAG}"
echo ""

# Push to ECR
echo -e "${YELLOW}→ Pushing to ECR...${NC}"
docker push "${ECR_REPO}:${IMAGE_TAG}"
echo ""

# Verify image in ECR
echo -e "${YELLOW}→ Verifying image in ECR...${NC}"
aws ecr describe-images --repository-name ml-platform-api --region "${AWS_REGION}" \
	--image-ids "imageTag=${IMAGE_TAG}" --output table
echo ""

# Show final summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  Image Pushed Successfully                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Image: ${ECR_REPO}:${IMAGE_TAG}${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Update k8s/deployment.yaml with new image URL:"
echo "     image: ${ECR_REPO}:${IMAGE_TAG}"
echo ""
echo "  2. Deploy to Kubernetes:"
echo "     kubectl apply -f k8s/deployment.yaml"
echo ""
echo "  3. Watch rollout:"
echo "     kubectl rollout status deployment/ml-platform-api -n ml-platform"
echo ""
