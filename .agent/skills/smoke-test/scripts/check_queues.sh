#!/bin/bash
# check_queues.sh - Verify message queue health and connectivity
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
RABBITMQ_HOST="${RABBITMQ_HOST:-localhost}"
RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"
RABBITMQ_MGMT_PORT="${RABBITMQ_MGMT_PORT:-15672}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASS="${RABBITMQ_PASS:-guest}"
CELERY_QUEUE="${CELERY_QUEUE:-celery}"
TIMEOUT="${QUEUE_CHECK_TIMEOUT:-10}"

PASSED=0
FAILED=0
WARNINGS=0

log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_ok()    { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; PASSED=$((PASSED + 1)); }
log_warn()  { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*"; WARNINGS=$((WARNINGS + 1)); }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*"; FAILED=$((FAILED + 1)); }

# Check if a command exists
has_cmd() { command -v "$1" &>/dev/null; }

# -------------------------------------------------------------------
# Redis queue checks
# -------------------------------------------------------------------
check_redis_connectivity() {
  log_info "Checking Redis connectivity at ${REDIS_HOST}:${REDIS_PORT}..."

  if ! has_cmd redis-cli; then
    log_warn "redis-cli not found — skipping Redis queue checks"
    return
  fi

  if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --no-auth-warning \
       -a "${REDIS_PASSWORD:-}" PING 2>/dev/null | grep -q "PONG"; then
    log_ok "Redis is reachable and responding to PING"
  else
    log_error "Redis at ${REDIS_HOST}:${REDIS_PORT} did not respond to PING"
    return
  fi

  # Check Celery task queue length
  local queue_len
  queue_len=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --no-auth-warning \
    -a "${REDIS_PASSWORD:-}" LLEN "${CELERY_QUEUE}" 2>/dev/null || echo "N/A")

  if [[ "${queue_len}" == "N/A" ]]; then
    log_warn "Could not read Celery queue length from Redis"
  elif [[ "${queue_len}" -gt 1000 ]]; then
    log_warn "Celery queue '${CELERY_QUEUE}' has ${queue_len} pending tasks — possible backlog"
  else
    log_ok "Celery queue '${CELERY_QUEUE}' length: ${queue_len}"
  fi
}

# -------------------------------------------------------------------
# RabbitMQ checks (optional — only if RABBITMQ_ENABLED is set)
# -------------------------------------------------------------------
check_rabbitmq_connectivity() {
  if [[ "${RABBITMQ_ENABLED:-false}" != "true" ]]; then
    log_info "RabbitMQ checks skipped (RABBITMQ_ENABLED != true)"
    return
  fi

  log_info "Checking RabbitMQ management API at ${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}..."

  if ! has_cmd curl; then
    log_warn "curl not found — skipping RabbitMQ management API check"
    return
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "${TIMEOUT}" \
    -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
    "http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api/healthchecks/node" 2>/dev/null || echo "000")

  if [[ "${http_code}" == "200" ]]; then
    log_ok "RabbitMQ node health check passed (HTTP ${http_code})"
  elif [[ "${http_code}" == "000" ]]; then
    log_error "RabbitMQ management API unreachable at ${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}"
  else
    log_warn "RabbitMQ health check returned unexpected HTTP ${http_code}"
  fi

  # Check queue overview
  local overview
  overview=$(curl -s --max-time "${TIMEOUT}" \
    -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
    "http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api/overview" 2>/dev/null || echo "{}")

  local messages_ready
  messages_ready=$(echo "${overview}" | grep -o '"messages_ready":[0-9]*' | head -1 | cut -d: -f2 || echo "N/A")

  if [[ "${messages_ready}" != "N/A" && "${messages_ready}" -gt 5000 ]]; then
    log_warn "RabbitMQ has ${messages_ready} ready messages — possible consumer lag"
  elif [[ "${messages_ready}" != "N/A" ]]; then
    log_ok "RabbitMQ ready messages: ${messages_ready}"
  fi
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
main() {
  log_info "=== Queue Health Checks ==="
  check_redis_connectivity
  check_rabbitmq_connectivity

  echo ""
  log_info "Queue check summary — passed: ${PASSED}, warnings: ${WARNINGS}, failed: ${FAILED}"

  if [[ "${FAILED}" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
