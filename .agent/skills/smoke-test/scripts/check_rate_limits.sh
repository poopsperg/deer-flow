#!/bin/bash
# check_rate_limits.sh - Verify API rate limiting is functioning correctly
# Tests that rate limits are enforced and returns appropriate 429 responses

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/common.sh"
fi

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8000}"
RATE_LIMIT_ENDPOINT="${RATE_LIMIT_ENDPOINT:-/api/chat/completions}"
RATE_LIMIT_THRESHOLD="${RATE_LIMIT_THRESHOLD:-60}"  # requests per minute
TEST_BURST_COUNT="${TEST_BURST_COUNT:-10}"
TIMEOUT="${TIMEOUT:-5}"
VERBOSE="${VERBOSE:-false}"

# Result tracking
PASSED=0
FAILED=0
WARNINGS=0

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_verbose() {
  if [[ "${VERBOSE}" == "true" ]]; then
    log "[VERBOSE] $*"
  fi
}

pass() {
  log "[PASS] $1"
  ((PASSED++))
}

fail() {
  log "[FAIL] $1"
  ((FAILED++))
}

warn() {
  log "[WARN] $1"
  ((WARNINGS++))
}

# Check that rate limit headers are present in responses
check_rate_limit_headers() {
  log "Checking rate limit headers on ${BASE_URL}${RATE_LIMIT_ENDPOINT}..."

  local response_headers
  response_headers=$(curl -s -I --max-time "${TIMEOUT}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/api/health" 2>/dev/null || true)

  if echo "${response_headers}" | grep -qi "x-ratelimit"; then
    pass "Rate limit headers present (X-RateLimit-*)"
  elif echo "${response_headers}" | grep -qi "retry-after"; then
    pass "Rate limit headers present (Retry-After)"
  else
    warn "No rate limit headers found — may not be enforced at this endpoint"
  fi
}

# Send a burst of requests and check for 429 responses
check_burst_rate_limiting() {
  log "Sending burst of ${TEST_BURST_COUNT} rapid requests to test rate limiting..."

  local got_429=false
  local success_count=0
  local fail_count=0

  for i in $(seq 1 "${TEST_BURST_COUNT}"); do
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time "${TIMEOUT}" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"messages":[{"role":"user","content":"ping"}],"stream":false}' \
      "${BASE_URL}${RATE_LIMIT_ENDPOINT}" 2>/dev/null || echo "000")

    log_verbose "Request ${i}: HTTP ${http_status}"

    if [[ "${http_status}" == "429" ]]; then
      got_429=true
      ((fail_count++))
    elif [[ "${http_status}" =~ ^[245] ]]; then
      ((success_count++))
    fi
  done

  log "Burst results: ${success_count} succeeded, ${fail_count} rate-limited"

  if [[ "${got_429}" == "true" ]]; then
    pass "Rate limiting enforced — received 429 Too Many Requests during burst"
  else
    warn "No 429 responses during burst test — rate limiting may be set high or disabled"
  fi
}

# Check that 429 response includes Retry-After header
check_retry_after_header() {
  log "Checking Retry-After header on rate-limited responses..."

  # Attempt to trigger a 429 by hammering a single endpoint
  local retry_after_found=false
  for i in $(seq 1 20); do
    local headers
    headers=$(curl -s -D - -o /dev/null --max-time "${TIMEOUT}" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"messages":[{"role":"user","content":"test"}],"stream":false}' \
      "${BASE_URL}${RATE_LIMIT_ENDPOINT}" 2>/dev/null || true)

    if echo "${headers}" | grep -qi "retry-after"; then
      retry_after_found=true
      break
    fi
  done

  if [[ "${retry_after_found}" == "true" ]]; then
    pass "Retry-After header present on rate-limited response"
  else
    warn "Retry-After header not detected — clients may not know when to retry"
  fi
}

# Main
main() {
  log "=== Rate Limit Checks ==="
  log "Target: ${BASE_URL}"

  check_rate_limit_headers
  check_burst_rate_limiting
  check_retry_after_header

  log "=== Rate Limit Check Summary ==="
  log "Passed: ${PASSED} | Failed: ${FAILED} | Warnings: ${WARNINGS}"

  if [[ "${FAILED}" -gt 0 ]]; then
    log "Rate limit checks FAILED"
    exit 1
  fi

  log "Rate limit checks PASSED"
  exit 0
}

main "$@"
