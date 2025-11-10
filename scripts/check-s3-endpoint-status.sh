#!/bin/bash
# Thin wrapper; delegates to platform/scripts/s3-endpoint-tools.sh
# Canonical implementation: platform/scripts/s3-endpoint-tools.sh (check-status)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

exec "${PROJECT_ROOT}/platform/scripts/s3-endpoint-tools.sh" check-status "$@"
