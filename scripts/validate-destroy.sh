#!/usr/bin/env bash
# Thin wrapper; delegates to platform/scripts/validate-destroy.sh
# Canonical implementation lives in: platform/scripts/validate-destroy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

exec "${PROJECT_ROOT}/platform/scripts/validate-destroy.sh" "$@"
