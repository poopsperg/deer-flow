#!/bin/bash
# check_healthcheck_endpoints.sh
# Validates all defined healthcheck endpoints return expected responses
# Used as part of the smoke test suite to verify service readiness

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${REPORT_DIR:-/tmp/smoke-test-reports}"
TIMEOUT="${HEALTHCHECK_TIMEOUT:-10}"
RETRIES="${HEALTHCHECK_RETRIES:-3}"
RETRY_DELAY="${HEALTHCHECK_RETRY_DELAY:-5}"

PASS=0
FAIL=0
WARN=0

# Colour helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/healthcheck_endpoints_$(date +%Y%m%d_%H%M%S).txt"

# ---------------------------------------------------------------------------
# Endpoint definitions  (URL | expected_http_code | description)
# Override HEALTHCHECK_ENDPOINTS env var to customise for your deployment
# ---------------------------------------------------------------------------
DEFAULT_ENDPOINTS=(
  "http://localhost:8000/health|200|Backend health"
  "http://localhost:8000/api/v1/health|200|API v1 health"
  "http://localhost:8000/api/v1/ready|200|API readiness probe"
  "http://localhost:3000/|200|Frontend root"
  "http://localhost:3000/health|200|Frontend health"
)

# Allow external override as a newline-separated list
if [[ -n "${HEALTHCHECK_ENDPOINTS:-}" ]]; then
  mapfile -t ENDPOINTS <<< "${HEALTHCHECK_ENDPOINTS}"
else
  ENDPOINTS=("${DEFAULT_ENDPOINTS[@]}")
fi

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log() { echo -e "$*" | tee -a "${REPORT_FILE}"; }

pass() { log "${GREEN}[PASS]${NC} $*"; ((PASS++)); }
fail() { log "${RED}[FAIL]${NC} $*"; ((FAIL++)); }
warn() { log "${YELLOW}[WARN]${NC} $*"; ((WARN++)); }

check_endpoint() {
  local url="$1"
  local expected_code="$2"
  local description="$3"
  local attempt=1
  local http_code

  while [[ ${attempt} -le ${RETRIES} ]]; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time "${TIMEOUT}" \
      --connect-timeout "${TIMEOUT}" \
      "${url}" 2>/dev/null || echo "000")

    if [[ "${http_code}" == "${expected_code}" ]]; then
      pass "${description} (${url}) → HTTP ${http_code}"
      return 0
    fi

    if [[ ${attempt} -lt ${RETRIES} ]]; then
      warn "${description} (${url}) → HTTP ${http_code} (expected ${expected_code}), retrying in ${RETRY_DELAY}s [${attempt}/${RETRIES}]"
      sleep "${RETRY_DELAY}"
    fi
    ((attempt++))
  done

  fail "${description} (${url}) → HTTP ${http_code} (expected ${expected_code}) after ${RETRIES} attempts"
  return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "====================================================="
log " Healthcheck Endpoint Verification"
log " Started: $(date)"
log "====================================================="
log ""

for entry in "${ENDPOINTS[@]}"; do
  IFS='|' read -r url expected_code description <<< "${entry}"
  check_endpoint "${url}" "${expected_code}" "${description}" || true
done

log ""
log "-----------------------------------------------------"
log " Results: PASS=${PASS}  FAIL=${FAIL}  WARN=${WARN}"
log " Report : ${REPORT_FILE}"
log "-----------------------------------------------------"

if [[ ${FAIL} -gt 0 ]]; then
  log "${RED}Healthcheck endpoint checks FAILED${NC}"
  exit 1
fi

log "${GREEN}All healthcheck endpoint checks passed${NC}"
exit 0
