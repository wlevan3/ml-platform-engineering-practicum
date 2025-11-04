#!/usr/bin/env bash
#
# Shared Logging Library
#
# Provides consistent colored logging functions for all project scripts.
#
# Usage:
#   source "$(dirname "$0")/lib/logging.sh"  # For scripts in scripts/
#   source "$(dirname "$0")/../scripts/lib/logging.sh"  # For scripts in subdirectories
#
# Functions:
#   log_info <message>     - Blue [INFO] prefix
#   log_success <message>  - Green [SUCCESS] prefix
#   log_warning <message>  - Yellow [WARNING] prefix
#   log_error <message>    - Red [ERROR] prefix
#   log_section <message>  - Magenta section header (=== message ===)
#   log_step <message>     - Blue step header with separator lines
#   error_exit <message>   - Log error and exit with status 1
#

# Prevent multiple sourcing
[[ -n "${__LOGGING_LIB_SOURCED__:-}" ]] && return 0
readonly __LOGGING_LIB_SOURCED__=1

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Core logging functions
log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Section headers
log_section() {
	echo -e "\n${MAGENTA}=== $1 ===${NC}"
}

log_step() {
	echo ""
	echo -e "${BLUE}========================================${NC}"
	echo -e "${BLUE}STEP: $1${NC}"
	echo -e "${BLUE}========================================${NC}"
}

# Error handler with exit
error_exit() {
	log_error "$1"
	exit 1
}
