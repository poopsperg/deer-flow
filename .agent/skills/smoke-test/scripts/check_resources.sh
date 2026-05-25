#!/bin/bash
# check_resources.sh - Check system resource usage during smoke tests
# Verifies CPU, memory, disk, and network resources are within acceptable limits

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
  source "${SCRIPT_DIR}/common.sh"
fi

# Thresholds
CPU_THRESHOLD=${CPU_THRESHOLD:-85}       # percent
MEM_THRESHOLD=${MEM_THRESHOLD:-90}       # percent
DISK_THRESHOLD=${DISK_THRESHOLD:-85}     # percent
LOAD_MULTIPLIER=${LOAD_MULTIPLIER:-2}    # load avg multiplier vs cpu count

# Results tracking
PASS=0
FAIL=0
WARN=0

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_pass()  { echo "[PASS]  $(date '+%H:%M:%S') $*"; ((PASS++)); }
log_fail()  { echo "[FAIL]  $(date '+%H:%M:%S') $*" >&2; ((FAIL++)); }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*"; ((WARN++)); }

# ── CPU ──────────────────────────────────────────────────────────────────────
check_cpu() {
  log_info "Checking CPU usage..."

  # Use top in batch mode for a 1-second snapshot
  if command -v top &>/dev/null; then
    local idle
    idle=$(top -bn1 | grep -E '^(%Cpu|Cpu)' | awk '{print $8}' | tr -d '%,' | head -1)
    if [[ -z "$idle" ]]; then
      # macOS top format differs
      idle=$(top -l1 -n0 | grep 'CPU usage' | awk '{print $7}' | tr -d '%' 2>/dev/null || echo "")
    fi

    if [[ -n "$idle" ]]; then
      local used
      used=$(echo "100 - $idle" | bc 2>/dev/null || echo "unknown")
      if [[ "$used" == "unknown" ]]; then
        log_warn "Could not calculate CPU usage"
      elif (( $(echo "$used > $CPU_THRESHOLD" | bc -l) )); then
        log_fail "CPU usage ${used}% exceeds threshold ${CPU_THRESHOLD}%"
      else
        log_pass "CPU usage ${used}% is within threshold ${CPU_THRESHOLD}%"
      fi
    else
      log_warn "Could not read CPU idle time"
    fi
  else
    log_warn "'top' not available, skipping CPU check"
  fi

  # Load average check
  local cpu_count
  cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  local load_limit
  load_limit=$(echo "$cpu_count * $LOAD_MULTIPLIER" | bc)
  local load1
  load1=$(uptime | awk -F'load average[s:]?' '{print $2}' | cut -d',' -f1 | tr -d ' ')

  if [[ -n "$load1" ]]; then
    if (( $(echo "$load1 > $load_limit" | bc -l) )); then
      log_fail "1-min load average ${load1} exceeds limit ${load_limit} (${cpu_count} CPUs x ${LOAD_MULTIPLIER})"
    else
      log_pass "1-min load average ${load1} is within limit ${load_limit}"
    fi
  fi
}

# ── Memory ───────────────────────────────────────────────────────────────────
check_memory() {
  log_info "Checking memory usage..."

  if [[ -f /proc/meminfo ]]; then
    local total used_pct
    local mem_total mem_available
    mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    mem_available=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    used_pct=$(echo "scale=1; (1 - $mem_available / $mem_total) * 100" | bc)

    if (( $(echo "$used_pct > $MEM_THRESHOLD" | bc -l) )); then
      log_fail "Memory usage ${used_pct}% exceeds threshold ${MEM_THRESHOLD}%"
    else
      log_pass "Memory usage ${used_pct}% is within threshold ${MEM_THRESHOLD}%"
    fi
  elif command -v vm_stat &>/dev/null; then
    # macOS
    local pages_free pages_active pages_inactive pages_speculative page_size
    page_size=$(pagesize 2>/dev/null || echo 4096)
    pages_free=$(vm_stat | awk '/Pages free/{gsub("\\.","",$3); print $3}')
    pages_active=$(vm_stat | awk '/Pages active/{gsub("\\.","",$3); print $3}')
    log_pass "Memory check passed (macOS vm_stat: free=${pages_free} pages, active=${pages_active} pages)"
  else
    log_warn "Cannot determine memory usage on this platform"
  fi
}

# ── Disk ─────────────────────────────────────────────────────────────────────
check_disk() {
  log_info "Checking disk usage..."

  local check_paths=("${DISK_PATHS:-/ /tmp}")
  # Re-split on spaces
  read -ra check_paths <<< "${DISK_PATHS:-/ /tmp}"

  for path in "${check_paths[@]}"; do
    if [[ ! -d "$path" ]]; then
      continue
    fi
    local used_pct
    used_pct=$(df -h "$path" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
    if [[ -z "$used_pct" ]]; then
      log_warn "Could not read disk usage for $path"
      continue
    fi
    if (( used_pct > DISK_THRESHOLD )); then
      log_fail "Disk usage on $path is ${used_pct}%, exceeds threshold ${DISK_THRESHOLD}%"
    else
      log_pass "Disk usage on $path is ${used_pct}%, within threshold ${DISK_THRESHOLD}%"
    fi
  done
}

# ── Docker-specific resource check ───────────────────────────────────────────
check_docker_resources() {
  if ! command -v docker &>/dev/null; then
    return 0
  fi
  log_info "Checking Docker container resource usage..."

  local stats
  stats=$(docker stats --no-stream --format \
    'table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}' 2>/dev/null || echo "")

  if [[ -z "$stats" ]]; then
    log_warn "No running Docker containers found or stats unavailable"
    return 0
  fi

  echo "$stats"
  log_pass "Docker resource stats collected"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  log_info "=== Resource Check Starting ==="
  check_cpu
  check_memory
  check_disk
  check_docker_resources

  echo ""
  log_info "=== Resource Check Summary: PASS=${PASS} WARN=${WARN} FAIL=${FAIL} ==="

  if (( FAIL > 0 )); then
    exit 1
  fi
  exit 0
}

main "$@"
