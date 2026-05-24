#!/usr/bin/env bash
# check_dependencies.sh - Verify all required dependencies are installed and meet version requirements

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source common utilities if available
if [[ -f "${SCRIPT_DIR}/utils.sh" ]]; then
  source "${SCRIPT_DIR}/utils.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Tracking
DEPS_OK=0
DEPS_MISSING=0
DEPS_OUTDATED=0

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Compare semver strings: returns 0 if $1 >= $2
version_gte() {
  local actual="$1"
  local required="$2"
  # Strip any leading 'v'
  actual="${actual#v}"
  required="${required#v}"
  printf '%s\n%s' "$required" "$actual" | sort -V -C
}

check_command() {
  local cmd="$1"
  local min_version="${2:-}"
  local version_flag="${3:---version}"

  if ! command -v "$cmd" &>/dev/null; then
    log_error "Missing required dependency: ${cmd}"
    (( DEPS_MISSING++ ))
    return 1
  fi

  if [[ -n "$min_version" ]]; then
    local actual_version
    actual_version=$("$cmd" "$version_flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
    if [[ -z "$actual_version" ]]; then
      log_warn "${cmd}: could not determine version (required >= ${min_version})"
      (( DEPS_OUTDATED++ ))
      return 0
    fi
    if version_gte "$actual_version" "$min_version"; then
      log_info "${cmd} ${actual_version} ✓  (required >= ${min_version})"
      (( DEPS_OK++ ))
    else
      log_warn "${cmd} ${actual_version} is below required version ${min_version}"
      (( DEPS_OUTDATED++ ))
    fi
  else
    log_info "${cmd} found ✓"
    (( DEPS_OK++ ))
  fi
}

check_python_package() {
  local package="$1"
  local min_version="${2:-}"

  if ! python3 -c "import ${package}" &>/dev/null; then
    log_error "Missing Python package: ${package}"
    (( DEPS_MISSING++ ))
    return 1
  fi

  if [[ -n "$min_version" ]]; then
    local actual_version
    actual_version=$(python3 -c "import ${package}; print(getattr(${package}, '__version__', '0.0.0'))" 2>/dev/null || echo "0.0.0")
    if version_gte "$actual_version" "$min_version"; then
      log_info "python:${package} ${actual_version} ✓  (required >= ${min_version})"
      (( DEPS_OK++ ))
    else
      log_warn "python:${package} ${actual_version} is below required version ${min_version}"
      (( DEPS_OUTDATED++ ))
    fi
  else
    log_info "python:${package} found ✓"
    (( DEPS_OK++ ))
  fi
}

main() {
  echo "======================================="
  echo "  Dependency Check"
  echo "======================================="

  # Core system tools
  check_command "curl"    "7.0.0"
  check_command "jq"      "1.5.0"
  check_command "git"     "2.0.0"

  # Python runtime
  check_command "python3" "3.10.0"
  check_command "pip3"    "21.0.0"

  # Node / frontend toolchain
  check_command "node"    "18.0.0"
  check_command "npm"     "8.0.0"

  # Container tooling (optional but warn)
  if command -v docker &>/dev/null; then
    check_command "docker"         "20.10.0"
    check_command "docker" "2.0.0" "compose version"
  else
    log_warn "docker not found — Docker-based tests will be skipped"
  fi

  # Key Python packages used by deer-flow
  check_python_package "fastapi"  "0.100.0"
  check_python_package "uvicorn"  "0.20.0"
  check_python_package "httpx"    "0.24.0"

  echo "---------------------------------------"
  echo "  Results: OK=${DEPS_OK}  OUTDATED=${DEPS_OUTDATED}  MISSING=${DEPS_MISSING}"
  echo "======================================="

  if (( DEPS_MISSING > 0 )); then
    log_error "One or more required dependencies are missing. Please install them before running smoke tests."
    exit 1
  fi

  if (( DEPS_OUTDATED > 0 )); then
    log_warn "Some dependencies are below the recommended version. Tests may still pass, but results could be unreliable."
    exit 0
  fi

  log_info "All dependencies satisfied."
  exit 0
}

main "$@"
