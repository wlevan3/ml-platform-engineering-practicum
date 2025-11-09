#!/usr/bin/env bash
# Logging helpers shared by cleanup/validation scripts

# Guard against multiple sourcing
if [[ -n "${ML_PLATFORM_LOGGING_SH_INCLUDED:-}" ]]; then
  return 0
fi
ML_PLATFORM_LOGGING_SH_INCLUDED=true

# Prevent accidental execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is intended to be sourced, not executed." >&2
  exit 1
fi

LOG_COLOR_RED='\033[0;31m'
LOG_COLOR_GREEN='\033[0;32m'
LOG_COLOR_YELLOW='\033[1;33m'
LOG_COLOR_BLUE='\033[0;34m'
LOG_COLOR_RESET='\033[0m'

log_info() {
  echo -e "${LOG_COLOR_BLUE}[INFO]${LOG_COLOR_RESET} $1"
}

log_success() {
  echo -e "${LOG_COLOR_GREEN}[SUCCESS]${LOG_COLOR_RESET} $1"
}

log_warn() {
  echo -e "${LOG_COLOR_YELLOW}[WARN]${LOG_COLOR_RESET} $1"
}

log_error() {
  echo -e "${LOG_COLOR_RED}[ERROR]${LOG_COLOR_RESET} $1"
}
