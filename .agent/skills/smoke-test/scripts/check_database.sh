#!/bin/bash
# check_database.sh - Verify database connectivity and basic operations
# Part of the deer-flow smoke test suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# Source common utilities if available
if [[ -f "${SCRIPT_DIR}/utils.sh" ]]; then
    source "${SCRIPT_DIR}/utils.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-deerflow}"
DB_USER="${DB_USER:-postgres}"
DB_TIMEOUT="${DB_TIMEOUT:-10}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS_COUNT++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL_COUNT++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN_COUNT++)); }
log_info() { echo -e "[INFO] $1"; }

check_postgres_connection() {
    log_info "Checking PostgreSQL connectivity at ${DB_HOST}:${DB_PORT}..."

    if ! command -v pg_isready &>/dev/null; then
        log_warn "pg_isready not found, skipping PostgreSQL check"
        return 0
    fi

    if pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -t "${DB_TIMEOUT}" &>/dev/null; then
        log_pass "PostgreSQL is accepting connections at ${DB_HOST}:${DB_PORT}"
    else
        log_fail "PostgreSQL not reachable at ${DB_HOST}:${DB_PORT}"
        return 1
    fi
}

check_postgres_database() {
    log_info "Checking PostgreSQL database '${DB_NAME}' exists..."

    if ! command -v psql &>/dev/null; then
        log_warn "psql not found, skipping database existence check"
        return 0
    fi

    if PGPASSWORD="${DB_PASSWORD:-}" psql -h "${DB_HOST}" -p "${DB_PORT}" \
        -U "${DB_USER}" -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw "${DB_NAME}"; then
        log_pass "Database '${DB_NAME}' exists"
    else
        log_fail "Database '${DB_NAME}' not found"
        return 1
    fi
}

check_redis_connection() {
    log_info "Checking Redis connectivity at ${REDIS_HOST}:${REDIS_PORT}..."

    if ! command -v redis-cli &>/dev/null; then
        log_warn "redis-cli not found, skipping Redis check"
        return 0
    fi

    local response
    response=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
        --no-auth-warning ping 2>/dev/null || echo "")

    if [[ "${response}" == "PONG" ]]; then
        log_pass "Redis is responding at ${REDIS_HOST}:${REDIS_PORT}"
    else
        log_fail "Redis not reachable at ${REDIS_HOST}:${REDIS_PORT} (got: '${response}')"
        return 1
    fi
}

check_redis_write_read() {
    log_info "Checking Redis read/write operations..."

    if ! command -v redis-cli &>/dev/null; then
        log_warn "redis-cli not found, skipping Redis read/write check"
        return 0
    fi

    local test_key="deerflow:smoke_test:$(date +%s)"
    local test_value="smoke_test_ok"

    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
        --no-auth-warning SET "${test_key}" "${test_value}" EX 60 &>/dev/null

    local read_value
    read_value=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
        --no-auth-warning GET "${test_key}" 2>/dev/null || echo "")

    if [[ "${read_value}" == "${test_value}" ]]; then
        log_pass "Redis read/write operations working correctly"
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" \
            --no-auth-warning DEL "${test_key}" &>/dev/null
    else
        log_fail "Redis read/write check failed (expected '${test_value}', got '${read_value}')"
        return 1
    fi
}

check_tcp_port() {
    local host="$1"
    local port="$2"
    local service="$3"

    if timeout 5 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
        log_pass "${service} port ${port} is open on ${host}"
    else
        log_fail "${service} port ${port} is not reachable on ${host}"
        return 1
    fi
}

main() {
    echo "======================================"
    echo "  Database Connectivity Checks"
    echo "======================================"
    echo ""

    # TCP-level checks first (no client tools required)
    check_tcp_port "${DB_HOST}" "${DB_PORT}" "PostgreSQL" || true
    check_tcp_port "${REDIS_HOST}" "${REDIS_PORT}" "Redis" || true

    echo ""

    # Higher-level checks
    check_postgres_connection || true
    check_postgres_database || true
    check_redis_connection || true
    check_redis_write_read || true

    echo ""
    echo "======================================"
    echo "  Database Check Summary"
    echo "======================================"
    echo -e "  ${GREEN}Passed:${NC}   ${PASS_COUNT}"
    echo -e "  ${YELLOW}Warnings:${NC} ${WARN_COUNT}"
    echo -e "  ${RED}Failed:${NC}   ${FAIL_COUNT}"
    echo ""

    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        echo -e "${RED}Database checks FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}Database checks PASSED${NC}"
        exit 0
    fi
}

main "$@"
