#!/usr/bin/env bash
# Shared validation and verification helpers for AWS + Terraform workflows.
#
# Centralizes logic used by thin wrappers:
#   - scripts/validate-terraform-state.sh
#   - scripts/verify-aws-resources-deleted.sh
#   - scripts/verify-eks-access.sh
#
# These helpers are canonical; top-level scripts in ./scripts/ delegate here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# validate-terraform-state (from original scripts/validate-terraform-state.sh)
# -----------------------------------------------------------------------------

aws_validation_validate_terraform_state() {
  local operation="${1:-plan}"
  local strict_refresh="${STRICT_REFRESH_FAILURE:-false}"

  # shellcheck source=/dev/null
  if [ -f "${SCRIPT_DIR}/../..//scripts/logging.sh" ]; then
    # Prefer shared logging if available via wrapper context
    :
  fi

  echo "Checking terraform state..."

  if [ ! -d ".terraform" ]; then
    echo "[ERROR] Terraform not initialized (.terraform directory not found)" >&2
    return 1
  fi

  echo "[INFO] Terraform initialized"

  if ! terraform state list &>/dev/null; then
    echo "[ERROR] Cannot read terraform state (corrupted or inaccessible)" >&2
    return 1
  fi

  echo "[INFO] State file is readable"

  if ! terraform validate -no-color &>/dev/null; then
    echo "[ERROR] Terraform validation failed" >&2
    return 1
  fi

  echo "[INFO] Terraform configuration is valid"

  local resource_count
  resource_count=$(terraform state list 2>/dev/null | awk 'NF {count++} END {print count+0}')

  case "$operation" in
    plan)
      if [ "$resource_count" -eq 0 ]; then
        echo "[WARN] No resources in state (might be first-time setup)"
      else
        echo "[INFO] Found $resource_count resources in state"
      fi
      if terraform state list 2>/dev/null | grep -q "aws_eks_cluster"; then
        echo "[INFO] EKS cluster found in state"
      elif [ "$resource_count" -gt 0 ]; then
        echo "[WARN] EKS cluster not found in state (may already be destroyed)"
      fi
      ;;
    destroy)
      if [ "$resource_count" -eq 0 ]; then
        echo "[INFO] State is empty (all resources destroyed)"
      else
        echo "[ERROR] $resource_count resources remain in state (destroy incomplete)" >&2
        echo ""
        echo "Remaining resources:"
        terraform state list | sed 's/^/  - /'
        return 1
      fi
      ;;
    *)
      echo "[ERROR] Unknown operation: $operation" >&2
      echo "Usage: validate-terraform-state [plan|destroy]" >&2
      return 1
      ;;
  esac

  echo "Checking for state integrity issues..."
  local refresh_output
  refresh_output=$(terraform refresh -no-color 2>&1 || true)
  if echo "$refresh_output" | grep -qiE "error|failed"; then
    case "${strict_refresh,,}" in
      true)
        echo "[ERROR] State refresh reported issues (STRICT_REFRESH_FAILURE=true)" >&2
        echo "$refresh_output"
        return 1
        ;;
      false)
        echo "[WARN] State refresh reported issues (may be non-critical; set STRICT_REFRESH_FAILURE=true to fail):"
        echo "$refresh_output"
        ;;
      *)
        echo "[ERROR] STRICT_REFRESH_FAILURE must be 'true' or 'false'; received '${strict_refresh}'." >&2
        return 1
        ;;
    esac
  else
    echo "[INFO] State refresh successful (no critical issues)"
  fi

  echo ""
  echo "[INFO] State validation passed"
}

# -----------------------------------------------------------------------------
# verify-aws-resources-deleted (from original scripts/verify-aws-resources-deleted.sh)
# -----------------------------------------------------------------------------

aws_validation_verify_aws_resources_deleted() {
  local cluster_name="${CLUSTER_NAME:-ml-platform-dev}"
  local region="${AWS_REGION:-us-west-2}"

  echo "Verifying all AWS resources deleted for cluster: $cluster_name"
  echo "Region: $region"
  echo ""

  if ! command -v aws &>/dev/null; then
    echo "[ERROR] AWS CLI not installed" >&2
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    echo "[ERROR] jq not installed" >&2
    return 1
  fi

  echo "[INFO] AWS CLI and jq available"
  echo ""

  local orphaned_found=false
  local orphaned_count=0

  _check_resource_type() {
    local resource_type=$1
    local type_label=$2

    echo "Checking $type_label..."

    local resources
    resources=$(aws resourcegroupstaggingapi get-resources \
      --resource-type-filter "$resource_type" \
      --tag-filter "Key=Cluster,Values=$cluster_name" \
      --region "$region" \
      --query 'ResourceTagMappingList' \
      --output json 2>/dev/null || echo "[]")

    local count
    count=$(echo "$resources" | jq 'length')

    if [ "$count" -eq 0 ]; then
      echo "[INFO] $type_label: 0 found"
    else
      echo "[ERROR] $type_label: Found $count resources (ORPHANED)"
      echo "$resources" | jq -r '.[] | .ResourceARN' | sed 's/^/  - /'
      echo "[WARN] Manual cleanup required for $type_label before verification can pass"
      orphaned_found=true
      orphaned_count=$((orphaned_count + count))
    fi

    echo ""
  }

  _check_resource_type "eks:cluster" "EKS Clusters"
  _check_resource_type "ec2:nat-gateway" "NAT Gateways"
  _check_resource_type "ec2:vpc-endpoint" "VPC Endpoints"
  _check_resource_type "ec2:elastic-ip" "Elastic IPs"
  _check_resource_type "ec2:security-group" "Security Groups"
  _check_resource_type "ec2:instance" "EC2 Instances"

  echo "=========================================="
  if [ "$orphaned_found" = false ]; then
    echo "[INFO] All resources deleted for cluster: $cluster_name"
    return 0
  else
    echo "[ERROR] Found $orphaned_count orphaned resources for cluster: $cluster_name"
    echo "[WARN] Please clean up remaining resources before considering destroy complete."
    return 1
  fi
}

# -----------------------------------------------------------------------------
# verify-eks-access (from original scripts/verify-eks-access.sh)
# -----------------------------------------------------------------------------

aws_validation_verify_eks_access() {
  local cluster_name="ml-platform-dev"
  local region="us-west-2"
  local namespace="ml-platform"
  local warning_count=0

  echo "======================================================================"
  echo "EKS Cluster Access Verification"
  echo "======================================================================"
  echo ""

  _status() {
    local level=$1
    local msg=$2
    case "$level" in
      OK)   echo "✓ $msg" ;;
      FAIL) echo "✗ $msg" ;;
      WARN) echo "⚠ $msg"; warning_count=$((warning_count + 1)) ;;
    esac
  }

  echo "Step 1: Updating kubeconfig for EKS cluster..."
  if aws eks update-kubeconfig --name "$cluster_name" --region "$region" >/dev/null 2>&1; then
    _status "OK" "Kubeconfig updated successfully"
  else
    _status "FAIL" "Failed to update kubeconfig"
    return 1
  fi
  echo ""

  echo "Step 2: Verifying kubectl context..."
  local current_context
  if ! current_context=$(kubectl config current-context 2>&1); then
    _status "FAIL" "kubectl not configured or context not set: $current_context"
    return 1
  fi

  if echo "$current_context" | grep -q "$cluster_name"; then
    _status "OK" "Context points to EKS cluster: $current_context"
  else
    _status "FAIL" "Context does not point to EKS: $current_context"
    return 1
  fi
  echo ""

  echo "Step 3: Verifying cluster access (kubectl get nodes)..."
  if kubectl get nodes >/dev/null 2>&1; then
    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    _status "OK" "Cluster access verified - found $node_count node(s)"
    echo ""
    echo "Nodes:"
    kubectl get nodes -o wide
  else
    _status "FAIL" "Cannot access cluster nodes"
    return 1
  fi
  echo ""

  echo "Step 4: Verifying namespaces..."
  if kubectl get namespaces | grep -q "$namespace"; then
    _status "OK" "Namespace '$namespace' exists"
  else
    _status "WARN" "Namespace '$namespace' not found"
  fi
  echo ""
  echo "All namespaces:"
  kubectl get namespaces
  echo ""

  echo "Step 5: Checking ml-platform namespace resources..."
  local resource_count
  resource_count=$(kubectl get all -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$resource_count" -gt 0 ]; then
    _status "OK" "Found $resource_count resource(s) in $namespace namespace"
    kubectl get all -n "$namespace"
  else
    _status "WARN" "No resources in $namespace namespace (expected if not deployed yet)"
  fi
  echo ""

  echo "Step 6: Testing RBAC permissions..."
  if kubectl auth can-i list pods -n "$namespace" 2>/dev/null | grep -q "yes"; then
    _status "OK" "RBAC permissions verified - can list pods in $namespace"
  else
    _status "FAIL" "Insufficient RBAC permissions"
    return 1
  fi
  echo ""

  echo "Step 7: Getting cluster info..."
  kubectl cluster-info | head -3 || true
  echo ""

  echo "Step 8: Node instance details..."
  if command -v jq >/dev/null 2>&1; then
    kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.metadata.labels."node.kubernetes.io/instance-type" // .metadata.labels."beta.kubernetes.io/instance-type" // "unknown") - CPU: \(.status.capacity.cpu), Memory: \(.status.capacity.memory)"'
  else
    _status "WARN" "jq not installed - skipping detailed node information"
  fi
  echo ""

  echo "======================================================================"
  if [ "$warning_count" -eq 0 ]; then
    echo "✓ All verification checks passed!"
  else
    echo "⚠ Verification completed with $warning_count warning(s)"
    echo "Warnings may be acceptable for initial cluster setup (e.g., missing namespace resources)"
  fi
  echo "======================================================================"
  echo ""
  echo "kubectl is now configured to access EKS cluster: $cluster_name"
  echo "Current context: $current_context"
}

# -----------------------------------------------------------------------------
# Entrypoint router (used by wrappers)
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    validate-terraform-state)
      shift
      aws_validation_validate_terraform_state "$@"
      ;;
    verify-aws-resources-deleted)
      shift
      aws_validation_verify_aws_resources_deleted "$@"
      ;;
    verify-eks-access)
      shift
      aws_validation_verify_eks_access "$@"
      ;;
    *)
      echo "Usage: $(basename "$0") {validate-terraform-state|verify-aws-resources-deleted|verify-eks-access} [args...]" >&2
      exit 1
      ;;
  esac
fi
