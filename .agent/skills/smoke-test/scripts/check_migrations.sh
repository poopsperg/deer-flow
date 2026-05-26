#!/bin/bash
# check_migrations.sh - Verify database migrations are up to date and healthy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Result tracking
PASSED=0
FAILED=0
WARNINGS=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARNINGS++)); }
log_info() { echo -e "[INFO] $1"; }

echo "========================================"
echo "  Database Migration Checks"
echo "========================================"
echo ""

# Load environment if available
if [ -f "${SOURCE_DIR}/.env" ]; then
    set -a
    source "${SOURCE_DIR}/.env"
    set +a
    log_info "Loaded environment from .env"
fi

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-deerflow}"
DB_USER="${DB_USER:-postgres}"

# Check if alembic is available (Python migrations)
check_alembic_available() {
    log_info "Checking Alembic availability..."
    if command -v alembic &>/dev/null; then
        local version
        version=$(alembic --version 2>&1 | head -1)
        log_pass "Alembic available: ${version}"
        return 0
    else
        log_warn "Alembic not found in PATH — skipping migration version checks"
        return 1
    fi
}

# Check migration files exist
check_migration_files() {
    log_info "Checking migration files..."
    local migrations_dir="${SOURCE_DIR}/alembic/versions"

    if [ -d "${migrations_dir}" ]; then
        local count
        count=$(find "${migrations_dir}" -name "*.py" | wc -l | tr -d ' ')
        if [ "${count}" -gt 0 ]; then
            log_pass "Found ${count} migration file(s) in ${migrations_dir}"
        else
            log_warn "Migration directory exists but contains no migration files"
        fi
    else
        log_warn "No alembic/versions directory found — project may not use Alembic"
    fi
}

# Check alembic.ini config
check_alembic_config() {
    log_info "Checking Alembic configuration..."
    local config_file="${SOURCE_DIR}/alembic.ini"

    if [ -f "${config_file}" ]; then
        log_pass "alembic.ini found"
        # Verify sqlalchemy.url is configured
        if grep -q "sqlalchemy.url" "${config_file}"; then
            log_pass "sqlalchemy.url configured in alembic.ini"
        else
            log_warn "sqlalchemy.url not found in alembic.ini"
        fi
    else
        log_warn "alembic.ini not found — skipping config checks"
    fi
}

# Check current migration head vs applied
check_migration_status() {
    log_info "Checking migration status (current vs head)..."

    if ! command -v alembic &>/dev/null; then
        log_warn "Alembic not available — skipping migration status check"
        return
    fi

    if ! pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null 2>&1; then
        log_warn "Database not reachable at ${DB_HOST}:${DB_PORT} — skipping live migration check"
        return
    fi

    pushd "${SOURCE_DIR}" > /dev/null
    local current
    current=$(alembic current 2>&1)
    local heads
    heads=$(alembic heads 2>&1)
    popd > /dev/null

    if echo "${current}" | grep -q "(head)"; then
        log_pass "Database is at migration head"
    else
        log_fail "Database is NOT at migration head. Current: ${current} | Head: ${heads}"
    fi
}

# Check for pending migrations
check_pending_migrations() {
    log_info "Checking for unapplied migrations..."

    if ! command -v alembic &>/dev/null; then
        log_warn "Alembic not available — skipping pending migration check"
        return
    fi

    if ! pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null 2>&1; then
        log_warn "Database not reachable — skipping pending migration check"
        return
    fi

    pushd "${SOURCE_DIR}" > /dev/null
    local pending
    pending=$(alembic history --indicate-current 2>&1 | grep -v "(current)" | grep -c "^" || true)
    popd > /dev/null

    if [ "${pending}" -eq 0 ]; then
        log_pass "No pending migrations"
    else
        log_warn "${pending} unapplied migration(s) detected"
    fi
}

# Run all checks
check_alembic_available
check_migration_files
check_alembic_config
check_migration_status
check_pending_migrations

echo ""
echo "========================================"
echo "  Migration Check Summary"
echo "  Passed:   ${PASSED}"
echo "  Failed:   ${FAILED}"
echo "  Warnings: ${WARNINGS}"
echo "========================================"

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi

exit 0
