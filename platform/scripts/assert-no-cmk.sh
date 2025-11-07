#!/usr/bin/env bash
# Fails if a Terraform plan references customer-managed KMS key resources.
# Expects human-readable plan output (use `terraform plan -no-color`).
# Usage: terraform plan -no-color | platform/scripts/assert-no-cmk.sh

set -euo pipefail

if [[ "${1:-}" != "" ]]; then
  if [[ ! -f "$1" ]]; then
    echo "error: plan file '$1' does not exist" >&2
    exit 2
  fi
  plan_output=$(cat "$1")
else
  plan_output=$(cat)
fi

if grep -qE '^[[:space:]]*[+~]\s+resource "aws_kms_key"' <<<"$plan_output"; then
  echo "error: Terraform plan contains customer-managed KMS key resources (aws_kms_key)." >&2
  exit 1
fi

exit 0
