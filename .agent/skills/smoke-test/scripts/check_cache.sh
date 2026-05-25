#!/bin/bash
# check_cache.sh - Verify cache layer health and connectivity
# Part of the deer-flow smoke test suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# ── defaults ────────────────────────────────────────────────────────────────
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_DB="${REDIS_DB:-0}"
CONNECT_TIMEOUT="${CACHE_CONNECT_TIMEOUT:-3}"
MIN_FREE_MEMORY_MB="${CACHE_MIN_FREE_MEMORY_MB:-50}"
MAX_USED_MEMORY_PERCENT="${CACHE_MAX_USED_MEMORY_PERCENT:-85}"

PASS=0
FAIL=0
WARN=0

# ── helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
pass() { log "  ✅  PASS  $*"; ((PASS++)); }
fail() { log "  ❌  FAIL  $*"; ((FAIL++)); }
warn() { log "  ⚠️   WARN  $*"; ((WARN++)); }

# Build redis-cli auth args once
redis_args() {
  local args=("-h" "${REDIS_HOST}" "-p" "${REDIS_PORT}" "-n" "${REDIS_DB}")
  [[ -n "${REDIS_PASSWORD}" ]] && args+=("-a" "${REDIS_PASSWORD}" "--no-auth-warning")
  echo "${args[@]}"
}

run_redis() {
  # shellcheck disable=SC2046
  redis-cli $(redis_args) --connect-timeout "${CONNECT_TIMEOUT}" "$@" 2>/dev/null
}

# ── checks ───────────────────────────────────────────────────────────────────
check_redis_available() {
  log "Checking redis-cli availability…"
  if ! command -v redis-cli &>/dev/null; then
    warn "redis-cli not found — skipping cache checks"
    return 1
  fi
  pass "redis-cli found: $(redis-cli --version)"
  return 0
}

check_connectivity() {
  log "Checking Redis connectivity (${REDIS_HOST}:${REDIS_PORT})…"
  local pong
  pong=$(run_redis PING 2>&1) || true
  if [[ "${pong}" == "PONG" ]]; then
    pass "Redis PING → PONG"
  else
    fail "Redis unreachable or auth failed (got: '${pong}')"
    return 1
  fi
}

check_memory_usage() {
  log "Checking Redis memory usage…"
  local info used_bytes max_bytes used_mb max_mb percent

  info=$(run_redis INFO memory) || { warn "Could not retrieve memory info"; return; }

  used_bytes=$(echo "${info}" | grep '^used_memory:' | tr -d '\r' | cut -d: -f2)
  max_bytes=$(echo "${info}"  | grep '^maxmemory:'   | tr -d '\r' | cut -d: -f2)

  used_mb=$(( ${used_bytes:-0} / 1024 / 1024 ))

  if [[ "${max_bytes:-0}" -eq 0 ]]; then
    warn "maxmemory not configured — used ${used_mb} MB (no hard limit)"
    return
  fi

  max_mb=$(( max_bytes / 1024 / 1024 ))
  percent=$(( used_bytes * 100 / max_bytes ))

  if [[ ${percent} -ge ${MAX_USED_MEMORY_PERCENT} ]]; then
    fail "Memory usage ${percent}% (${used_mb}/${max_mb} MB) exceeds threshold ${MAX_USED_MEMORY_PERCENT}%"
  else
    pass "Memory usage ${percent}% (${used_mb}/${max_mb} MB) within threshold"
  fi
}

check_read_write() {
  log "Checking Redis read/write round-trip…"
  local key="deerflow:smoketest:$(date +%s)"
  local value="smoke_ok"

  run_redis SET "${key}" "${value}" EX 30 &>/dev/null || { fail "SET failed"; return; }
  local got
  got=$(run_redis GET "${key}") || { fail "GET failed"; return; }

  if [[ "${got}" == "${value}" ]]; then
    pass "Read/write round-trip OK"
    run_redis DEL "${key}" &>/dev/null || true
  else
    fail "Round-trip mismatch: expected '${value}', got '${got}'"
  fi
}

check_keyspace() {
  log "Checking keyspace stats…"
  local dbinfo
  dbinfo=$(run_redis INFO keyspace) || { warn "Could not retrieve keyspace info"; return; }
  local db_line
  db_line=$(echo "${dbinfo}" | grep "^db${REDIS_DB}:") || true
  if [[ -z "${db_line}" ]]; then
    warn "DB ${REDIS_DB} has no keys yet"
  else
    local keys
    keys=$(echo "${db_line}" | grep -oP 'keys=\K[0-9]+')
    pass "DB ${REDIS_DB} contains ${keys} key(s)"
  fi
}

check_replication() {
  log "Checking Redis replication role…"
  local role
  role=$(run_redis INFO replication | grep '^role:' | tr -d '\r' | cut -d: -f2) || { warn "Could not retrieve replication info"; return; }
  if [[ "${role}" == "master" ]]; then
    pass "Redis role: master"
  elif [[ "${role}" == "slave" || "${role}" == "replica" ]]; then
    local lag
    lag=$(run_redis INFO replication | grep 'master_last_io_seconds_ago:' | tr -d '\r' | cut -d: -f2) || lag="?"
    pass "Redis role: replica (lag ${lag}s)"
  else
    warn "Unknown replication role: '${role}'"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
  log "═══════════════════════════════════════"
  log " Cache Health Check"
  log "═══════════════════════════════════════"

  if ! check_redis_available; then
    log "Skipped all Redis checks (redis-cli unavailable)"
    exit 0
  fi

  check_connectivity || { log "Aborting further checks — Redis unreachable"; exit 1; }
  check_memory_usage
  check_read_write
  check_keyspace
  check_replication

  log "───────────────────────────────────────"
  log " Results: PASS=${PASS}  WARN=${WARN}  FAIL=${FAIL}"
  log "───────────────────────────────────────"

  [[ ${FAIL} -eq 0 ]]
}

main "$@"
