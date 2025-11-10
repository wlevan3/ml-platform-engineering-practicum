#!/usr/bin/env bash
# Thin wrapper; delegates to platform/scripts/aws-validation-tools.sh
# Canonical implementation: platform/scripts/aws-validation-tools.sh (validate-terraform-state)
#
# Usage:
#   ./scripts/validate-terraform-state.sh [plan|destroy]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

exec "${PROJECT_ROOT}/platform/scripts/aws-validation-tools.sh" validate-terraform-state "$@"
