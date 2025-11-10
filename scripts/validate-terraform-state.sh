#!/usr/bin/env bash
# Thin wrapper; delegates to platform/scripts/aws-validation-tools.sh
# Canonical implementation: platform/scripts/aws-validation-tools.sh (validate-terraform-state)
#
# Usage:
#   ./scripts/validate-terraform-state.sh [plan|destroy]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &gt;&amp; /dev/null &amp;&amp; pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." &gt;&amp; /dev/null &amp;&amp; pwd)"

exec "${PROJECT_ROOT}/platform/scripts/aws-validation-tools.sh" validate-terraform-state "$@"
