#!/bin/bash
# check_monitoring.sh - Verify monitoring and observability stack is functional
# Checks metrics endpoints, log aggregation, and alerting systems

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Config
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
METRICS_PORT="${METRICS_PORT:-9090}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-10}"
PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

# Check if metrics endpoint is exposed
check_metrics_endpoint() {
  log_info "Checking /metrics endpoint..."
  local url="${BACKEND_URL}/metrics"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${HEALTH_TIMEOUT}" "${url}" 2>/dev/null || echo "000")

  if [[ "${http_code}" == "200" ]]; then
    log_pass "Metrics endpoint reachable (HTTP ${http_code})"
  elif [[ "${http_code}" == "404" ]]; then
    log_warn "Metrics endpoint not found (HTTP 404) — may not be enabled"
  else
    log_fail "Metrics endpoint returned HTTP ${http_code}"
  fi
}

# Check health endpoint returns structured response
check_health_response_structure() {
  log_info "Checking health endpoint response structure..."
  local url="${BACKEND_URL}/health"
  local body
  body=$(curl -s --max-time "${HEALTH_TIMEOUT}" "${url}" 2>/dev/null || echo "")

  if echo "${body}" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'status' in d" 2>/dev/null; then
    log_pass "Health response contains 'status' field"
  elif [[ -n "${body}" ]]; then
    log_warn "Health response present but missing 'status' field: ${body:0:80}"
  else
    log_fail "No response from health endpoint"
  fi
}

# Check Prometheus scrape target if running
check_prometheus() {
  log_info "Checking Prometheus availability on port ${METRICS_PORT}..."
  local url="http://localhost:${METRICS_PORT}/-/healthy"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${HEALTH_TIMEOUT}" "${url}" 2>/dev/null || echo "000")

  if [[ "${http_code}" == "200" ]]; then
    log_pass "Prometheus healthy (HTTP ${http_code})"
  else
    log_warn "Prometheus not reachable on port ${METRICS_PORT} — may not be deployed"
  fi
}

# Check that application logs are being written
check_log_output() {
  log_info "Checking application log output..."
  local log_file="${LOG_FILE:-/tmp/deerflow/app.log}"

  if [[ -f "${log_file}" ]]; then
    local lines
    lines=$(wc -l < "${log_file}" 2>/dev/null || echo 0)
    if [[ "${lines}" -gt 0 ]]; then
      log_pass "Log file exists and has ${lines} lines: ${log_file}"
    else
      log_warn "Log file exists but is empty: ${log_file}"
    fi
  else
    log_warn "Log file not found at ${log_file} — may use stdout only"
  fi
}

# Check Docker container stats if applicable
check_container_stats() {
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not available — skipping container stats check"
    return
  fi

  log_info "Checking running container stats..."
  local containers
  containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'deer\|deerflow' || true)

  if [[ -z "${containers}" ]]; then
    log_warn "No deerflow containers found running"
    return
  fi

  while IFS= read -r container; do
    local cpu_pct
    cpu_pct=$(docker stats --no-stream --format '{{.CPUPerc}}' "${container}" 2>/dev/null || echo "N/A")
    log_pass "Container '${container}' CPU usage: ${cpu_pct}"
  done <<< "${containers}"
}

# Summary
print_summary() {
  echo ""
  echo "=============================="
  echo " Monitoring Check Summary"
  echo "=============================="
  echo -e " ${GREEN}Passed:${NC}  ${PASS}"
  echo -e " ${YELLOW}Warnings:${NC} ${WARN}"
  echo -e " ${RED}Failed:${NC}  ${FAIL}"
  echo "=============================="

  if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
  fi
}

main() {
  echo "=== Monitoring & Observability Checks ==="
  check_metrics_endpoint
  check_health_response_structure
  check_prometheus
  check_log_output
  check_container_stats
  print_summary
}

main "$@"
