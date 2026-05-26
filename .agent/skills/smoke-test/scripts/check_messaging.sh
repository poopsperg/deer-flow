#!/bin/bash
# check_messaging.sh - Verify messaging/queue services are operational
# Part of the deer-flow smoke test suite

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/common.sh"
fi

# Configuration
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-10}"
LOG_FILE="${LOG_FILE:-/tmp/smoke-test-messaging.log}"

# Tracking
PASSED=0
FAILED=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  log "PASS: $*"
  ((PASSED++)) || true
}

fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  log "FAIL: $*"
  ((FAILED++)) || true
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
  log "WARN: $*"
  ((WARNINGS++)) || true
}

# Check if redis-cli is available
check_redis_cli() {
  if command -v redis-cli &>/dev/null; then
    pass "redis-cli is available"
    return 0
  else
    warn "redis-cli not found — skipping Redis checks"
    return 1
  fi
}

# Test Redis connectivity
check_redis_connection() {
  local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
  if [[ -n "${REDIS_PASSWORD}" ]]; then
    redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"
  fi

  local response
  if response=$(timeout "${CHECK_TIMEOUT}" ${redis_cmd} PING 2>/dev/null); then
    if [[ "${response}" == "PONG" ]]; then
      pass "Redis connection OK (${REDIS_HOST}:${REDIS_PORT})"
      return 0
    else
      fail "Redis responded unexpectedly: ${response}"
      return 1
    fi
  else
    fail "Cannot connect to Redis at ${REDIS_HOST}:${REDIS_PORT}"
    return 1
  fi
}

# Verify Redis can read/write
check_redis_readwrite() {
  local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
  if [[ -n "${REDIS_PASSWORD}" ]]; then
    redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"
  fi

  local test_key="smoke_test_$(date +%s)"
  local test_val="deer-flow-ok"

  # Write
  if ! timeout "${CHECK_TIMEOUT}" ${redis_cmd} SET "${test_key}" "${test_val}" EX 30 &>/dev/null; then
    fail "Redis SET failed"
    return 1
  fi

  # Read back
  local result
  result=$(timeout "${CHECK_TIMEOUT}" ${redis_cmd} GET "${test_key}" 2>/dev/null)
  if [[ "${result}" == "${test_val}" ]]; then
    pass "Redis read/write OK"
    # Cleanup
    timeout "${CHECK_TIMEOUT}" ${redis_cmd} DEL "${test_key}" &>/dev/null || true
    return 0
  else
    fail "Redis GET returned unexpected value: '${result}'"
    return 1
  fi
}

# Check Redis memory usage
check_redis_memory() {
  local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
  if [[ -n "${REDIS_PASSWORD}" ]]; then
    redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"
  fi

  local used_memory
  used_memory=$(timeout "${CHECK_TIMEOUT}" ${redis_cmd} INFO memory 2>/dev/null \
    | grep 'used_memory_human' | head -1 | cut -d: -f2 | tr -d '[:space:]')

  if [[ -n "${used_memory}" ]]; then
    pass "Redis memory usage: ${used_memory}"
  else
    warn "Could not retrieve Redis memory stats"
  fi
}

# Main
main() {
  log "=== Messaging/Queue Service Checks ==="
  echo "Checking messaging services..."

  if check_redis_cli; then
    check_redis_connection && {
      check_redis_readwrite
      check_redis_memory
    }
  fi

  echo ""
  echo "Messaging check summary: ${PASSED} passed, ${FAILED} failed, ${WARNINGS} warnings"
  log "Summary: PASSED=${PASSED} FAILED=${FAILED} WARNINGS=${WARNINGS}"

  if [[ ${FAILED} -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
