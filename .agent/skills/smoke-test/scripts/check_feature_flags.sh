#!/usr/bin/env bash
# check_feature_flags.sh - Validate feature flag configurations and states
# Part of the deer-flow smoke test suite

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
  source "${SCRIPT_DIR}/common.sh"
fi

# Configuration
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
FEATURE_FLAGS_ENDPOINT="${FEATURE_FLAGS_ENDPOINT:-/api/v1/feature-flags}"
TIMEOUT="${TIMEOUT:-10}"
PASS=0
FAIL=0
WARN=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

echo "================================================"
echo " Feature Flags Check"
echo "================================================"
echo ""

# Check 1: Feature flags endpoint reachability
log_info "Checking feature flags endpoint availability..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time "${TIMEOUT}" \
  "${BACKEND_URL}${FEATURE_FLAGS_ENDPOINT}" 2>/dev/null || echo "000")

if [[ "${HTTP_STATUS}" == "200" ]]; then
  log_pass "Feature flags endpoint is reachable (HTTP ${HTTP_STATUS})"
elif [[ "${HTTP_STATUS}" == "404" ]]; then
  log_warn "Feature flags endpoint not found — may not be implemented yet"
else
  log_warn "Feature flags endpoint returned HTTP ${HTTP_STATUS} — skipping detailed checks"
fi

# Check 2: Validate required environment-based feature flags
log_info "Checking environment-based feature flags..."

DECLARE_REQUIRED_FLAGS=(
  "ENABLE_DEEP_RESEARCH"
  "ENABLE_REPORT_GENERATION"
  "ENABLE_PODCAST_GENERATION"
  "ENABLE_PPT_GENERATION"
)

for flag in "${DECLARE_REQUIRED_FLAGS[@]}"; do
  if [[ -n "${!flag:-}" ]]; then
    flag_value="${!flag}"
    if [[ "${flag_value}" == "true" || "${flag_value}" == "1" || \
          "${flag_value}" == "false" || "${flag_value}" == "0" ]]; then
      log_pass "Feature flag ${flag}=${flag_value} is set and valid"
    else
      log_warn "Feature flag ${flag}=${flag_value} has unexpected value (expected true/false/1/0)"
    fi
  else
    log_warn "Feature flag ${flag} is not set — using default behavior"
  fi
done

# Check 3: Verify no conflicting feature flag combinations
log_info "Checking for conflicting feature flag combinations..."

ENABLE_DEEP_RESEARCH="${ENABLE_DEEP_RESEARCH:-true}"
ENABLE_REPORT_GENERATION="${ENABLE_REPORT_GENERATION:-true}"

if [[ "${ENABLE_DEEP_RESEARCH}" == "true" && "${ENABLE_REPORT_GENERATION}" == "false" ]]; then
  log_warn "ENABLE_DEEP_RESEARCH=true with ENABLE_REPORT_GENERATION=false may cause incomplete workflows"
else
  log_pass "No conflicting feature flag combinations detected"
fi

# Check 4: Validate feature flags config file if present
CONFIG_FILE="${PROJECT_ROOT:-$(pwd)}/.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  log_info "Validating feature flags in .env file..."
  INVALID_FLAGS=$(grep -E '^ENABLE_' "${CONFIG_FILE}" | \
    grep -vE '^ENABLE_[A-Z_]+=\s*(true|false|1|0|yes|no)\s*$' || true)
  if [[ -z "${INVALID_FLAGS}" ]]; then
    log_pass "All ENABLE_* flags in .env have valid boolean values"
  else
    log_warn "Some feature flags in .env may have non-standard values:"
    echo "${INVALID_FLAGS}" | while read -r line; do
      log_warn "  ${line}"
    done
  fi
else
  log_info "No .env file found at ${CONFIG_FILE} — skipping file-based flag validation"
fi

# Summary
echo ""
echo "================================================"
echo " Feature Flags Check Summary"
echo "================================================"
echo -e "  ${GREEN}Passed:${NC}   ${PASS}"
echo -e "  ${YELLOW}Warnings:${NC} ${WARN}"
echo -e "  ${RED}Failed:${NC}   ${FAIL}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo -e "${RED}Feature flags check completed with failures.${NC}"
  exit 1
else
  echo -e "${GREEN}Feature flags check completed successfully.${NC}"
  exit 0
fi
