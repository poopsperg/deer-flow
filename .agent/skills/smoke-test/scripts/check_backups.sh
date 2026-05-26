#!/bin/bash
# check_backups.sh - Verify backup systems and recent backup integrity

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/deer-flow}"
MAX_BACKUP_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-24}"
MIN_BACKUP_SIZE_BYTES="${MIN_BACKUP_SIZE_BYTES:-1024}"
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
S3_PREFIX="${BACKUP_S3_PREFIX:-deer-flow/backups}"

echo "======================================"
echo "  Backup System Check"
echo "======================================"
echo ""

# Check if backup directory exists
check_backup_directory() {
    log_info "Checking backup directory: ${BACKUP_DIR}"

    if [ -d "${BACKUP_DIR}" ]; then
        log_pass "Backup directory exists: ${BACKUP_DIR}"
    else
        log_warn "Backup directory not found: ${BACKUP_DIR} (may not be configured)"
        return 0
    fi

    # Check directory is readable
    if [ -r "${BACKUP_DIR}" ]; then
        log_pass "Backup directory is readable"
    else
        log_fail "Backup directory is not readable"
    fi
}

# Check for recent backups
check_recent_backups() {
    log_info "Checking for recent backups (within ${MAX_BACKUP_AGE_HOURS}h)"

    if [ ! -d "${BACKUP_DIR}" ]; then
        log_warn "Skipping recent backup check — directory not found"
        return 0
    fi

    # Find backups newer than threshold
    recent_count=$(find "${BACKUP_DIR}" -name "*.tar.gz" -o -name "*.sql.gz" -o -name "*.dump" \
        2>/dev/null | xargs -I{} find {} -mmin "-$((MAX_BACKUP_AGE_HOURS * 60))" 2>/dev/null | wc -l)

    # Simpler approach
    recent_count=$(find "${BACKUP_DIR}" \( -name "*.tar.gz" -o -name "*.sql.gz" -o -name "*.dump" \) \
        -mmin "-$((MAX_BACKUP_AGE_HOURS * 60))" 2>/dev/null | wc -l)

    if [ "${recent_count}" -gt 0 ]; then
        log_pass "Found ${recent_count} recent backup(s) within ${MAX_BACKUP_AGE_HOURS} hours"
    else
        log_warn "No recent backups found within ${MAX_BACKUP_AGE_HOURS} hours"
    fi
}

# Check backup file sizes are reasonable
check_backup_sizes() {
    log_info "Checking backup file sizes"

    if [ ! -d "${BACKUP_DIR}" ]; then
        log_warn "Skipping backup size check — directory not found"
        return 0
    fi

    local suspicious=0
    while IFS= read -r -d '' backup_file; do
        size=$(stat -c%s "${backup_file}" 2>/dev/null || stat -f%z "${backup_file}" 2>/dev/null || echo 0)
        if [ "${size}" -lt "${MIN_BACKUP_SIZE_BYTES}" ]; then
            log_warn "Suspiciously small backup: ${backup_file} (${size} bytes)"
            ((suspicious++))
        fi
    done < <(find "${BACKUP_DIR}" \( -name "*.tar.gz" -o -name "*.sql.gz" -o -name "*.dump" \) \
        -print0 2>/dev/null)

    if [ "${suspicious}" -eq 0 ]; then
        log_pass "All backup files meet minimum size requirement (${MIN_BACKUP_SIZE_BYTES} bytes)"
    fi
}

# Check S3 backup availability (if configured)
check_s3_backups() {
    if [ -z "${S3_BUCKET}" ]; then
        log_info "S3 backup bucket not configured — skipping"
        return 0
    fi

    log_info "Checking S3 backups: s3://${S3_BUCKET}/${S3_PREFIX}"

    if ! command -v aws &>/dev/null; then
        log_warn "AWS CLI not found — cannot verify S3 backups"
        return 0
    fi

    if aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" &>/dev/null; then
        recent_s3=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" \
            --recursive 2>/dev/null | sort | tail -1)
        if [ -n "${recent_s3}" ]; then
            log_pass "S3 backups accessible, latest: ${recent_s3}"
        else
            log_warn "S3 bucket accessible but no backups found at prefix"
        fi
    else
        log_fail "Cannot access S3 backup bucket: s3://${S3_BUCKET}/${S3_PREFIX}"
    fi
}

# Check backup cron job or scheduler
check_backup_schedule() {
    log_info "Checking backup schedule configuration"

    # Check for cron job
    if crontab -l 2>/dev/null | grep -qi "backup"; then
        log_pass "Backup cron job found in user crontab"
    elif [ -f "/etc/cron.d/deer-flow-backup" ]; then
        log_pass "Backup cron config found: /etc/cron.d/deer-flow-backup"
    else
        log_warn "No backup schedule detected (cron or /etc/cron.d)"
    fi
}

# Run all checks
check_backup_directory
check_recent_backups
check_backup_sizes
check_s3_backups
check_backup_schedule

echo ""
echo "======================================"
echo "  Backup Check Summary"
echo "  PASS: ${PASS} | FAIL: ${FAIL} | WARN: ${WARN}"
echo "======================================"

# Exit with failure if any hard failures
if [ "${FAIL}" -gt 0 ]; then
    exit 1i

exit 0
