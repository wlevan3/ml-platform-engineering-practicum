#!/usr/bin/env bash
#
# End-to-End Minikube Deployment and Testing Script
#
# This script:
# 1. Validates prerequisites (minikube, kubectl, docker)
# 2. Starts Minikube cluster (or verifies it's running)
# 3. Builds Docker image in Minikube's Docker daemon
# 4. Deploys Kubernetes manifests
# 5. Waits for pods to be ready
# 6. Runs comprehensive endpoint tests
# 7. Shows logs and provides cleanup instructions
#
# Usage:
#   ./scripts/deploy-to-minikube.sh [--clean]
#
# Options:
#   --clean    Clean up existing deployment before starting
#

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Source shared logging library
# shellcheck disable=SC1091
source "$(dirname "$0")/lib/logging.sh"

# Configuration
DOCKER_IMAGE="ml-platform-api:v1.0.0"
DEPLOYMENT_NAME="ml-platform-api"
TIMEOUT="120s"

# Parse arguments
CLEAN_DEPLOY=false
if [[ "${1:-}" == "--clean" ]]; then
	CLEAN_DEPLOY=true
	log_info "Clean deployment requested"
fi

# ============================================================================
# STEP 1: Validate Prerequisites
# ============================================================================
log_step "1/8 - Validating Prerequisites"

log_info "Checking for required tools..."

if ! command -v minikube &>/dev/null; then
	error_exit "minikube not found. Install: macOS: 'brew install minikube' | Ubuntu: 'apt-get install -y minikube'"
fi
log_success "✓ minikube found: $(minikube version --short)"

if ! command -v kubectl &>/dev/null; then
	error_exit "kubectl not found. Install: macOS: 'brew install kubectl' | Ubuntu: 'apt-get install -y kubectl'"
fi
log_success "✓ kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

if ! command -v docker &>/dev/null; then
	error_exit "docker not found. Install Docker Desktop"
fi
log_success "✓ docker found: $(docker --version)"

if ! command -v curl &>/dev/null; then
	error_exit "curl not found"
fi
log_success "✓ curl found"

# Check if k8s manifests exist
if [[ ! -f "k8s/deployment.yaml" ]] || [[ ! -f "k8s/service.yaml" ]]; then
	error_exit "Kubernetes manifests not found in k8s/ directory"
fi
log_success "✓ Kubernetes manifests found"

# ============================================================================
# STEP 2: Start/Verify Minikube Cluster
# ============================================================================
log_step "2/8 - Starting Minikube Cluster"

# Use exit code-based check (more robust than parsing output)
if minikube status >/dev/null 2>&1; then
	log_success "✓ Minikube is already running"
	minikube status
else
	log_info "Starting Minikube cluster..."
	log_info "This may take 2-3 minutes..."

	# Start with appropriate resources for ML workload
	minikube start \
		--cpus=2 \
		--memory=4096 \
		--disk-size=20g \
		--driver=docker \
		--kubernetes-version=stable

	log_success "✓ Minikube cluster started"
fi

# Verify kubectl context
CURRENT_CONTEXT=$(kubectl config current-context)
if [[ "$CURRENT_CONTEXT" != "minikube" ]]; then
	log_warning "Current kubectl context is '$CURRENT_CONTEXT', switching to 'minikube'"
	kubectl config use-context minikube
fi
log_success "✓ kubectl context: $CURRENT_CONTEXT"

# Show cluster info
log_info "Cluster info:"
kubectl cluster-info | head -2

# ============================================================================
# STEP 3: Configure Docker Environment
# ============================================================================
log_step "3/8 - Configuring Docker Environment"

log_info "Switching to Minikube's Docker daemon..."
log_info "This ensures Docker images are built inside Minikube"

# Set Docker environment variables
eval "$(minikube docker-env)"

log_success "✓ Docker environment configured"
log_info "Docker host: $DOCKER_HOST"

# ============================================================================
# STEP 4: Build Docker Image
# ============================================================================
log_step "4/8 - Building Docker Image"

log_info "Building Docker image: $DOCKER_IMAGE"
log_info "This may take 2-3 minutes for first build..."

# Build with explicit context
docker build -t "$DOCKER_IMAGE" .

log_success "✓ Docker image built: $DOCKER_IMAGE"

# Verify image exists (tag-agnostic check)
if ! docker inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
	error_exit "Docker image not found after build"
fi

# Show image info
log_info "Image details:"
docker images "$DOCKER_IMAGE" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

# ============================================================================
# STEP 5: Clean Up Existing Deployment (if requested)
# ============================================================================
if [[ "$CLEAN_DEPLOY" == true ]]; then
	log_step "5/8 - Cleaning Up Existing Deployment"

	log_info "Deleting existing resources..."
	kubectl delete -f k8s/ --ignore-not-found=true

	log_info "Waiting for pods to terminate..."
	POD_COUNT=$(kubectl get pods -l app="$DEPLOYMENT_NAME" --no-headers 2>/dev/null | wc -l)
	if [[ "$POD_COUNT" -gt 0 ]]; then
		if ! kubectl wait --for=delete pod -l app="$DEPLOYMENT_NAME" --timeout=60s; then
			log_warning "Pod termination timed out or failed; proceeding anyway (may cause conflicts)"
		else
			log_success "✓ Pods terminated cleanly"
		fi
	else
		log_info "No pods found to wait for termination"
	fi

	log_success "✓ Cleanup complete"
else
	log_step "5/8 - Skipping Cleanup (use --clean to force cleanup)"
fi

# ============================================================================
# STEP 6: Deploy to Kubernetes
# ============================================================================
log_step "6/8 - Deploying to Kubernetes"

log_info "Applying Kubernetes manifests..."

# Apply manifests
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

log_success "✓ Manifests applied"

# Show deployment status
log_info "Deployment status:"
kubectl get deployment "$DEPLOYMENT_NAME"

log_info "Service status:"
kubectl get service "$DEPLOYMENT_NAME"

# ============================================================================
# STEP 7: Wait for Deployment to be Ready
# ============================================================================
log_step "7/8 - Waiting for Deployment to be Ready"

log_info "Waiting for pods to be ready (timeout: $TIMEOUT)..."
log_info "This includes model loading time (~30 seconds)"

# Wait for deployment to be ready
if ! kubectl wait --for=condition=available deployment/"$DEPLOYMENT_NAME" --timeout="$TIMEOUT"; then
	log_error "Deployment did not become available in time"

	log_info "Pod status:"
	kubectl get pods -l app="$DEPLOYMENT_NAME"

	log_info "Recent events:"
	kubectl get events --sort-by='.lastTimestamp' | tail -20

	log_info "Pod logs:"
	kubectl logs -l app="$DEPLOYMENT_NAME" --tail=50

	error_exit "Deployment failed - see logs above"
fi

log_success "✓ Deployment is ready"

# Show pod details
log_info "Pod details:"
kubectl get pods -l app="$DEPLOYMENT_NAME" -o wide

# Show pod logs (last 20 lines)
log_info "Recent pod logs:"
kubectl logs -l app="$DEPLOYMENT_NAME" --tail=20

# ============================================================================
# STEP 8: Run End-to-End Tests
# ============================================================================
log_step "8/8 - Running End-to-End Tests"

log_info "Getting service URL..."
# Get Minikube IP and NodePort (avoids tunnel requirement on macOS Docker driver)
MINIKUBE_IP=$(minikube ip 2>/dev/null || true)
if [[ -z "$MINIKUBE_IP" ]]; then
	error_exit "Failed to get Minikube IP address"
fi

NODE_PORT=$(kubectl get service "$DEPLOYMENT_NAME" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
if [[ -z "$NODE_PORT" ]]; then
	error_exit "Failed to get NodePort for service $DEPLOYMENT_NAME"
fi

SERVICE_URL="http://${MINIKUBE_IP}:${NODE_PORT}"
log_success "✓ Service URL: $SERVICE_URL"

# Global flag to track test failures
test_failed=false

# Test function
run_test() {
	local test_name="$1"
	local endpoint="$2"
	local method="${3:-GET}"
	local data="${4:-}"
	local expected_status="${5:-200}"

	log_info "Testing: $test_name"
	log_info "  Endpoint: $method $endpoint"

	if [[ -n "$data" ]]; then
		response=$(curl -s -w "\n%{http_code}" -X "$method" \
			-H "Content-Type: application/json" \
			-d "$data" \
			"$SERVICE_URL$endpoint")
	else
		response=$(curl -s -w "\n%{http_code}" "$SERVICE_URL$endpoint")
	fi

	# Split response body and status code
	body=$(echo "$response" | head -n -1)
	status=$(echo "$response" | tail -n 1)

	if [[ "$status" == "$expected_status" ]]; then
		log_success "  ✓ Status: $status (expected $expected_status)"
		log_info "  Response: $(echo "$body" | jq -c '.' 2>/dev/null || echo "$body")"
	else
		log_error "  ✗ Status: $status (expected $expected_status)"
		log_error "  Response: $body"
		test_failed=true # Set flag instead of returning
	fi
}

# Run tests
log_info "Running comprehensive endpoint tests..."
echo ""

# Test 1: Root endpoint
run_test "Root endpoint" "/" "GET" "" "200"

# Test 2: Liveness probe
run_test "Liveness probe" "/health/live" "GET" "" "200"

# Test 3: Readiness probe
run_test "Readiness probe" "/health/ready" "GET" "" "200"

# Test 4: Model info
run_test "Model info" "/model/info" "GET" "" "200"

# Test 5: Prediction - Setosa
run_test "Prediction (setosa)" "/predict" "POST" \
	'{"features": [5.1, 3.5, 1.4, 0.2]}' "200"

# Test 6: Prediction - Versicolor
run_test "Prediction (versicolor)" "/predict" "POST" \
	'{"features": [6.0, 2.7, 5.1, 1.6]}' "200"

# Test 7: Prediction - Virginica
run_test "Prediction (virginica)" "/predict" "POST" \
	'{"features": [6.5, 3.0, 5.5, 1.8]}' "200"

# Test 8: Invalid input (missing features)
run_test "Invalid input (missing features)" "/predict" "POST" \
	'{"features": [5.1, 3.5]}' "422"

# Test 9: OpenAPI docs
run_test "OpenAPI docs" "/openapi.json" "GET" "" "200"

# Check if any test failed
if [[ "$test_failed" == true ]]; then
	error_exit "One or more tests failed"
fi

log_success "✓ All tests completed"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DEPLOYMENT SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
log_info "Service URL: $SERVICE_URL"
log_info "API Documentation: $SERVICE_URL/docs"
echo ""
log_info "Useful commands:"
echo "  # View pods"
echo "    kubectl get pods -l app=$DEPLOYMENT_NAME"
echo ""
echo "  # View logs (live tail)"
echo "    kubectl logs -f -l app=$DEPLOYMENT_NAME"
echo ""
echo "  # View service"
echo "    kubectl get service $DEPLOYMENT_NAME"
echo ""
echo "  # Port forward (alternative to minikube service)"
echo "    kubectl port-forward service/$DEPLOYMENT_NAME 8000:8000"
echo ""
echo "  # Test endpoints"
echo "    curl $SERVICE_URL/health/live"
echo "    curl $SERVICE_URL/health/ready"
echo "    curl -X POST $SERVICE_URL/predict \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"features\": [5.1, 3.5, 1.4, 0.2]}'"
echo ""
log_info "Cleanup commands:"
echo "  # Delete deployment"
echo "    kubectl delete -f k8s/"
echo ""
echo "  # Stop Minikube"
echo "    minikube stop"
echo ""
echo "  # Delete Minikube cluster"
echo "    minikube delete"
echo ""
