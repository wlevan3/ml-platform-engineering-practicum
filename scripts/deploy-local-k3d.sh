#!/usr/bin/env bash
#
# Fast Local Development with k3d
#
# This script provides rapid iteration for local Kubernetes development:
# 1. Creates/verifies k3d cluster (30 seconds vs 2-3 minutes with Minikube)
# 2. Builds Docker image
# 3. Loads image into k3d
# 4. Deploys Kubernetes manifests
# 5. Exposes service on localhost:8000
#
# Usage:
#   ./scripts/deploy-local-k3d.sh [--clean]
#
# Options:
#   --clean    Delete existing cluster and start fresh
#
# Requirements:
#   - k3d: brew install k3d (macOS) or curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
#   - kubectl: brew install kubectl
#   - docker: Docker Desktop
#

set -euo pipefail

# Source shared logging library
# shellcheck disable=SC1091
source "$(dirname "$0")/lib/logging.sh"

# Configuration
CLUSTER_NAME="ml-platform-dev"
DOCKER_IMAGE="ml-platform-api:v1.0.0"
DEPLOYMENT_NAME="ml-platform-api"
NAMESPACE="ml-platform"
TIMEOUT="120s"
LOCAL_PORT="8000"

# Parse arguments
CLEAN_DEPLOY=false
if [[ "${1:-}" == "--clean" ]]; then
	CLEAN_DEPLOY=true
	log_info "Clean deployment requested"
fi

# ============================================================================
# STEP 1: Validate Prerequisites
# ============================================================================
log_step "1/6 - Validating Prerequisites"

log_info "Checking for required tools..."

if ! command -v k3d &>/dev/null; then
	log_error "k3d not found"
	log_info "Install k3d:"
	log_info "  macOS:  brew install k3d"
	log_info "  Linux:  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
	error_exit "k3d is required for local development"
fi
log_success "✓ k3d found: $(k3d version | head -1)"

if ! command -v kubectl &>/dev/null; then
	error_exit "kubectl not found. Install: brew install kubectl"
fi
log_success "✓ kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

if ! command -v docker &>/dev/null; then
	error_exit "docker not found. Install Docker Desktop"
fi
log_success "✓ docker found: $(docker --version)"

# Check if k8s manifests exist
if [[ ! -f "k8s/namespace.yaml" ]] || [[ ! -f "k8s/deployment.yaml" ]] || [[ ! -f "k8s/service.yaml" ]]; then
	error_exit "Kubernetes manifests not found in k8s/ directory"
fi
log_success "✓ Kubernetes manifests found"

# ============================================================================
# STEP 2: Create/Verify k3d Cluster
# ============================================================================
log_step "2/6 - Setting Up k3d Cluster"

if [[ "$CLEAN_DEPLOY" == true ]]; then
	log_info "Deleting existing cluster (if any)..."
	k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
	log_success "✓ Cleanup complete"
fi

# Check if cluster exists
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
	log_success "✓ k3d cluster '$CLUSTER_NAME' already exists"
else
	log_info "Creating k3d cluster: $CLUSTER_NAME"
	log_info "This takes ~30 seconds..."

	# Create cluster with:
	# - 2 worker nodes (matches EKS dev config)
	# - Port mapping for service access
	# - Faster startup than Minikube
	k3d cluster create "$CLUSTER_NAME" \
		--agents 2 \
		--port "${LOCAL_PORT}:80@loadbalancer" \
		--wait

	log_success "✓ k3d cluster created"
fi

# Switch kubectl context
kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null
log_success "✓ kubectl context: k3d-$CLUSTER_NAME"

# Show cluster info
log_info "Cluster nodes:"
kubectl get nodes

# ============================================================================
# STEP 3: Build Docker Image
# ============================================================================
log_step "3/6 - Building Docker Image"

log_info "Building Docker image: $DOCKER_IMAGE"

# Build image (much faster on subsequent builds due to layer caching)
docker build -t "$DOCKER_IMAGE" -q . || docker build -t "$DOCKER_IMAGE" .

log_success "✓ Docker image built: $DOCKER_IMAGE"

# ============================================================================
# STEP 4: Load Image into k3d
# ============================================================================
log_step "4/6 - Loading Image into k3d"

log_info "Importing image into k3d cluster..."

# Load image into k3d's containerd (avoids pulling from registry)
k3d image import "$DOCKER_IMAGE" -c "$CLUSTER_NAME"

log_success "✓ Image loaded into k3d"

# ============================================================================
# STEP 5: Deploy to Kubernetes
# ============================================================================
log_step "5/6 - Deploying to Kubernetes"

log_info "Applying Kubernetes manifests..."

# Create namespace
kubectl apply -f k8s/namespace.yaml

# Apply deployment and service
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

log_success "✓ Manifests applied"

# Show deployment status
log_info "Deployment status:"
kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

# ============================================================================
# STEP 6: Wait for Deployment and Test
# ============================================================================
log_step "6/6 - Waiting for Deployment"

log_info "Waiting for pods to be ready (timeout: $TIMEOUT)..."

# Wait for deployment
if ! kubectl wait --for=condition=available deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout="$TIMEOUT"; then
	log_error "Deployment did not become available"

	log_info "Pod status:"
	kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME"

	log_info "Pod logs:"
	kubectl logs -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" --tail=50

	error_exit "Deployment failed"
fi

log_success "✓ Deployment is ready"

# Show pod details
log_info "Pods:"
kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" -o wide

# ============================================================================
# Test Endpoints
# ============================================================================
echo ""
log_info "Testing endpoints..."

SERVICE_URL="http://localhost:${LOCAL_PORT}"

# Wait a moment for service to be fully ready
sleep 2

# Test health endpoint
log_info "Testing: $SERVICE_URL/health/live"
if curl -sf "$SERVICE_URL/health/live" >/dev/null; then
	log_success "✓ Liveness check passed"
else
	log_warning "Liveness check failed (service may not be ready yet)"
fi

log_info "Testing: $SERVICE_URL/health/ready"
if curl -sf "$SERVICE_URL/health/ready" >/dev/null; then
	log_success "✓ Readiness check passed"
	RESPONSE=$(curl -s "$SERVICE_URL/health/ready" | jq -c '.')
	log_info "  Response: $RESPONSE"
else
	log_warning "Readiness check failed (model may still be loading)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LOCAL DEPLOYMENT SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
log_success "Service URL: $SERVICE_URL"
log_success "API Documentation: $SERVICE_URL/docs"
echo ""
log_info "Quick test commands:"
echo "  curl $SERVICE_URL/health/live"
echo "  curl $SERVICE_URL/health/ready"
echo "  curl -X POST $SERVICE_URL/predict \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"features\": [5.1, 3.5, 1.4, 0.2]}'"
echo ""
log_info "Development commands:"
echo "  # View pods"
echo "    kubectl get pods -n $NAMESPACE"
echo ""
echo "  # View logs (live tail)"
echo "    kubectl logs -f -n $NAMESPACE -l app=$DEPLOYMENT_NAME"
echo ""
echo "  # Restart deployment (after code changes)"
echo "    docker build -t $DOCKER_IMAGE ."
echo "    k3d image import $DOCKER_IMAGE -c $CLUSTER_NAME"
echo "    kubectl rollout restart deployment/$DEPLOYMENT_NAME -n $NAMESPACE"
echo ""
echo "  # Delete deployment (keep cluster)"
echo "    kubectl delete -f k8s/deployment.yaml -f k8s/service.yaml"
echo ""
log_info "Cluster management:"
echo "  # Stop cluster (saves memory, keeps data)"
echo "    k3d cluster stop $CLUSTER_NAME"
echo ""
echo "  # Start cluster"
echo "    k3d cluster start $CLUSTER_NAME"
echo ""
echo "  # Delete cluster"
echo "    k3d cluster delete $CLUSTER_NAME"
echo ""
log_info "Why k3d?"
echo "  ⚡ 30 seconds vs 2-3 minutes (Minikube)"
echo "  💚 Low memory usage (512MB vs 2GB)"
echo "  🚀 Perfect for daily development iteration"
echo "  ☁️  Use EKS for AWS-specific features (ALB, IAM, ECR)"
echo ""
