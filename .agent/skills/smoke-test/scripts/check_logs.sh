#!/bin/bash
# check_logs.sh - Analyze application logs for errors and warnings during smoke test
# Part of the deer-flow smoke test skill

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-/tmp/deer-flow-logs}"
ERROR_THRESHOLD="${ERROR_THRESHOLD:-10}"
WARN_THRESHOLD="${WARN_THRESHOLD:-50}"
DEPLOY_MODE="${DEPLOY_MODE:-local}"  # local | docker

# ANSI colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo -e "${CYAN}[check_logs]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }

check_result=0

record_fail() {
  fail "$*"
  check_result=1
}

# ─── Collect log sources ──────────────────────────────────────────────────────
collect_docker_logs() {
  log "Collecting Docker container logs..."
  mkdir -p "$LOG_DIR"

  local containers
  containers=$(docker ps --filter "name=deer-flow" --format '{{.Names}}' 2>/dev/null || true)

  if [[ -z "$containers" ]]; then
    warn "No deer-flow Docker containers found running"
    return 0
  fi

  for container in $containers; do
    local out="$LOG_DIR/${container}.log"
    docker logs "$container" > "$out" 2>&1 || true
    log "  Saved logs for $container → $out"
  done
}

collect_local_logs() {
  log "Collecting local process logs..."
  mkdir -p "$LOG_DIR"

  # Common log locations for deer-flow running locally
  local sources=(
    "./logs"
    "/tmp/deer-flow"
    "${HOME}/.deer-flow/logs"
  )

  for src in "${sources[@]}"; do
    if [[ -d "$src" ]]; then
      cp -r "$src"/*.log "$LOG_DIR/" 2>/dev/null || true
      log "  Copied logs from $src"
    fi
  done
}

# ─── Analyze a single log file ────────────────────────────────────────────────
analyze_log_file() {
  local file="$1"
  local label
  label=$(basename "$file")

  local error_count warn_count
  error_count=$(grep -ciE '(ERROR|CRITICAL|FATAL|Traceback|Exception)' "$file" 2>/dev/null || echo 0)
  warn_count=$(grep -ciE '(WARNING|WARN)' "$file" 2>/dev/null || echo 0)

  log "  $label → errors: $error_count, warnings: $warn_count"

  if (( error_count > ERROR_THRESHOLD )); then
    record_fail "$label has $error_count errors (threshold: $ERROR_THRESHOLD)"
    # Print last 5 error lines for context
    grep -iE '(ERROR|CRITICAL|FATAL)' "$file" | tail -5 | while read -r line; do
      fail "    $line"
    done
  fi

  if (( warn_count > WARN_THRESHOLD )); then
    warn "$label has $warn_count warnings (threshold: $WARN_THRESHOLD)"
  fi

  # Check for OOM / panic signals
  if grep -qiE '(out of memory|oom|killed|panic)' "$file" 2>/dev/null; then
    record_fail "$label contains OOM/panic indicators"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "Starting log analysis (mode: $DEPLOY_MODE)"
  log "Log directory: $LOG_DIR"
  echo

  # Collect logs based on deploy mode
  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    collect_docker_logs
  else
    collect_local_logs
  fi

  # Analyze all collected log files
  local log_files
  log_files=$(find "$LOG_DIR" -maxdepth 2 -name '*.log' 2>/dev/null || true)

  if [[ -z "$log_files" ]]; then
    warn "No log files found in $LOG_DIR — skipping analysis"
    exit 0
  fi

  log "Analyzing log files..."
  while IFS= read -r f; do
    analyze_log_file "$f"
  done <<< "$log_files"

  echo
  if (( check_result == 0 )); then
    pass "Log analysis passed — no critical issues detected"
  else
    fail "Log analysis found issues — review errors above"
  fi

  exit $check_result
}

main "$@"
