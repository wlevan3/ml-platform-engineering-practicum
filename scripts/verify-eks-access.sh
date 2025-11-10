#!/usr/bin/env bash
# Thin wrapper; delegates to platform/scripts/aws-validation-tools.sh
# Canonical implementation: platform/scripts/aws-validation-tools.sh (verify-eks-access)
#
# Usage:
#   ./scripts/verify-eks-access.sh
#
# Exit codes:
#   0 - EKS access verification passed (with or without warnings)
#   1 - Verification failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &gt;&amp; /dev/null &amp;&amp; pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." &gt;&amp; /dev/null &amp;&amp; pwd)"

exec "${PROJECT_ROOT}/platform/scripts/aws-validation-tools.sh" verify-eks-access "$@"
