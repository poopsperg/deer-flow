#!/bin/bash
# check_storage.sh - Verify storage/filesystem health and disk space for deer-flow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# Thresholds
DISK_WARN_PERCENT=80
DISK_CRIT_PERCENT=90
INODE_WARN_PERCENT=80
INODE_CRIT_PERCENT=90

# Results tracking
PASS=0
FAIL=0
WARN=0

log_pass() { echo "  [PASS] $1"; ((PASS++)); }
log_fail() { echo "  [FAIL] $1"; ((FAIL++)); }
log_warn() { echo "  [WARN] $1"; ((WARN++)); }
log_info() { echo "  [INFO] $1"; }

echo "========================================"
echo "Storage & Filesystem Checks"
echo "========================================"

# --- Disk Space ---
echo ""
echo "[Disk Space]"

check_disk_usage() {
  local mount="$1"
  if ! df -h "$mount" &>/dev/null; then
    log_warn "Mount point not accessible: $mount"
    return
  fi

  local usage_pct
  usage_pct=$(df "$mount" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  local avail
  avail=$(df -h "$mount" | awk 'NR==2 {print $4}')

  if [[ "$usage_pct" -ge "$DISK_CRIT_PERCENT" ]]; then
    log_fail "Disk usage on $mount: ${usage_pct}% used (${avail} free) — CRITICAL"
  elif [[ "$usage_pct" -ge "$DISK_WARN_PERCENT" ]]; then
    log_warn "Disk usage on $mount: ${usage_pct}% used (${avail} free) — WARNING"
  else
    log_pass "Disk usage on $mount: ${usage_pct}% used (${avail} free)"
  fi
}

check_disk_usage "/"
[[ -d "$PROJECT_ROOT" ]] && check_disk_usage "$PROJECT_ROOT"

# --- Inode Usage ---
echo ""
echo "[Inode Usage]"

check_inode_usage() {
  local mount="$1"
  if ! df -i "$mount" &>/dev/null; then
    log_warn "Cannot check inodes for: $mount"
    return
  fi

  local inode_pct
  inode_pct=$(df -i "$mount" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

  # Some filesystems (e.g. tmpfs) report 0% or -
  if [[ -z "$inode_pct" || "$inode_pct" == "-" ]]; then
    log_info "Inode usage not applicable for $mount"
    return
  fi

  if [[ "$inode_pct" -ge "$INODE_CRIT_PERCENT" ]]; then
    log_fail "Inode usage on $mount: ${inode_pct}% — CRITICAL"
  elif [[ "$inode_pct" -ge "$INODE_WARN_PERCENT" ]]; then
    log_warn "Inode usage on $mount: ${inode_pct}% — WARNING"
  else
    log_pass "Inode usage on $mount: ${inode_pct}%"
  fi
}

check_inode_usage "/"

# --- Key Project Directories ---
echo ""
echo "[Project Directories]"

check_dir() {
  local dir="$1"
  local label="$2"
  if [[ -d "$dir" ]]; then
    local size
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    log_pass "$label exists (${size}): $dir"
  else
    log_warn "$label not found: $dir"
  fi
}

check_dir "${PROJECT_ROOT}" "Project root"
check_dir "${PROJECT_ROOT}/src" "Source directory"
check_dir "${PROJECT_ROOT}/logs" "Logs directory"
check_dir "${PROJECT_ROOT}/.agent" "Agent directory"

# Check writable
for dir in "${PROJECT_ROOT}" "/tmp"; do
  if [[ -w "$dir" ]]; then
    log_pass "Directory is writable: $dir"
  else
    log_fail "Directory is NOT writable: $dir"
  fi
done

# --- Temp Space ---
echo ""
echo "[Temp Space]"
check_disk_usage "/tmp"

# --- Summary ---
echo ""
echo "========================================"
echo "Storage Check Summary"
echo "  Passed : $PASS"
echo "  Warned : $WARN"
echo "  Failed : $FAIL"
echo "========================================"

if [[ "$FAIL" -gt 0 ]]; then
  exit 2
elif [[ "$WARN" -gt 0 ]]; then
  exit 1
fi

exit 0
