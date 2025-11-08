#!/usr/bin/env bash
# =============================================================================
# EKS Cluster Access Verification Script
# =============================================================================
# Purpose: Verify kubectl is configured for EKS cluster access
# Usage: ./scripts/verify-eks-access.sh
# Issue: #106 - Configure kubectl for EKS cluster access
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="ml-platform-dev"
REGION="us-west-2"
NAMESPACE="ml-platform"

# Track warnings
WARNING_COUNT=0

echo "======================================================================"
echo "EKS Cluster Access Verification"
echo "======================================================================"
echo ""

# Function to print status
print_status() {
	local status=$1
	local message=$2
	if [ "$status" == "OK" ]; then
		echo -e "${GREEN}✓${NC} $message"
	elif [ "$status" == "FAIL" ]; then
		echo -e "${RED}✗${NC} $message"
	else
		echo -e "${YELLOW}⚠${NC} $message"
		WARNING_COUNT=$((WARNING_COUNT + 1))
	fi
}

# Test 1: Update kubeconfig
echo "Step 1: Updating kubeconfig for EKS cluster..."
if aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
	print_status "OK" "Kubeconfig updated successfully"
else
	print_status "FAIL" "Failed to update kubeconfig"
	exit 1
fi
echo ""

# Test 2: Verify current context
echo "Step 2: Verifying kubectl context..."
if ! CURRENT_CONTEXT=$(kubectl config current-context 2>&1); then
	print_status "FAIL" "kubectl not configured or context not set: $CURRENT_CONTEXT"
	exit 1
fi

if echo "$CURRENT_CONTEXT" | grep -q "$CLUSTER_NAME"; then
	print_status "OK" "Context points to EKS cluster: $CURRENT_CONTEXT"
else
	print_status "FAIL" "Context does not point to EKS: $CURRENT_CONTEXT"
	exit 1
fi
echo ""

# Test 3: Verify cluster access - list nodes
echo "Step 3: Verifying cluster access (kubectl get nodes)..."
if kubectl get nodes >/dev/null 2>&1; then
	NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
	print_status "OK" "Cluster access verified - found $NODE_COUNT node(s)"
	echo ""
	echo "Nodes:"
	kubectl get nodes -o wide
else
	print_status "FAIL" "Cannot access cluster nodes"
	exit 1
fi
echo ""

# Test 4: Verify namespaces
echo "Step 4: Verifying namespaces..."
if kubectl get namespaces | grep -q "$NAMESPACE"; then
	print_status "OK" "Namespace '$NAMESPACE' exists"
else
	print_status "WARN" "Namespace '$NAMESPACE' not found"
fi
echo ""
echo "All namespaces:"
kubectl get namespaces
echo ""

# Test 5: Verify ml-platform namespace resources
echo "Step 5: Checking ml-platform namespace resources..."
RESOURCE_COUNT=$(kubectl get all -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESOURCE_COUNT" -gt 0 ]; then
	print_status "OK" "Found $RESOURCE_COUNT resource(s) in $NAMESPACE namespace"
	kubectl get all -n "$NAMESPACE"
else
	print_status "WARN" "No resources in $NAMESPACE namespace (expected if not deployed yet)"
fi
echo ""

# Test 6: Test RBAC permissions
echo "Step 6: Testing RBAC permissions..."
if kubectl auth can-i list pods -n "$NAMESPACE" 2>/dev/null | grep -q "yes"; then
	print_status "OK" "RBAC permissions verified - can list pods in $NAMESPACE"
else
	print_status "FAIL" "Insufficient RBAC permissions"
	exit 1
fi
echo ""

# Test 7: Cluster info
echo "Step 7: Getting cluster info..."
kubectl cluster-info | head -3
echo ""

# Test 8: Node details
echo "Step 8: Node instance details..."
echo "Instance Type and Capacity:"

# Check if jq is available
if ! command -v jq &>/dev/null; then
	print_status "WARN" "jq not installed - skipping detailed node information"
	echo "Install jq for detailed node information: brew install jq (macOS) or apt-get install jq (Linux)"
else
	kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.metadata.labels."node.kubernetes.io/instance-type" // .metadata.labels."beta.kubernetes.io/instance-type" // "unknown") - CPU: \(.status.capacity.cpu), Memory: \(.status.capacity.memory)"'
fi
echo ""

# Summary
echo "======================================================================"
if [ "$WARNING_COUNT" -eq 0 ]; then
	echo -e "${GREEN}✓ All verification checks passed!${NC}"
else
	echo -e "${YELLOW}⚠ Verification completed with $WARNING_COUNT warning(s)${NC}"
	echo "Warnings are acceptable for initial cluster setup (e.g., missing namespace resources)"
fi
echo "======================================================================"
echo ""
echo "kubectl is now configured to access EKS cluster: $CLUSTER_NAME"
echo "Current context: $CURRENT_CONTEXT"
echo ""
echo "Next steps:"
echo "  - Install AWS Load Balancer Controller (Issue #107)"
echo "  - Set up ArgoCD for GitOps (Issue #100)"
echo "  - Deploy ML platform services"
echo ""
