#!/usr/bin/env bash
# Thin wrapper; delegates to platform/scripts/aws-validation-tools.sh
# Canonical implementation: platform/scripts/aws-validation-tools.sh (verify-aws-resources-deleted)
#
# Usage:
#   CLUSTER_NAME=ml-platform-dev ./scripts/verify-aws-resources-deleted.sh
#
# Exit codes:
#   0 - All resources deleted (0 found in AWS)
#   1 - Resources still exist in AWS or validation error
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

exec "${PROJECT_ROOT}/platform/scripts/aws-validation-tools.sh" verify-aws-resources-deleted "$@"
