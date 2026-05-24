#!/bin/bash
# health_check.sh - Performs health checks on all running services
# Verifies endpoints are responding and returning expected status codes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Default configuration
BACKEND_HOST="${BACKEND_HOST:-localhost}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_HOST="${FRONTEND_HOST:-localhost}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY="${RETRY_DELAY:-3}"
TIMEOUT="${TIMEOUT:-10}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check a single HTTP endpoint with retries
check_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time "$TIMEOUT" \
            --connect-timeout 5 \
            "$url" 2>/dev/null || echo "000")

        if [ "$status" = "$expected_status" ]; then
            log_info "[$name] OK (HTTP $status) — $url"
            PASS=$((PASS + 1))
            return 0
        fi

        if [ $attempt -lt $MAX_RETRIES ]; then
            log_warn "[$name] Attempt $attempt/$MAX_RETRIES failed (HTTP $status), retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
        attempt=$((attempt + 1))
    done

    log_error "[$name] FAILED after $MAX_RETRIES attempts (last HTTP $status) — $url"
    FAIL=$((FAIL + 1))
    return 1
}

# Check if a port is open
check_port() {
    local name="$1"
    local host="$2"
    local port="$3"

    if nc -z -w5 "$host" "$port" 2>/dev/null; then
        log_info "[$name] Port $port is open on $host"
        PASS=$((PASS + 1))
        return 0
    else
        log_error "[$name] Port $port is NOT reachable on $host"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

# Run all health checks
run_health_checks() {
    echo "====================================="
    echo " DeerFlow Health Check"
    echo " $(date '+%Y-%m-%d %H:%M:%S')"
    echo "====================================="
    echo ""

    log_info "Checking backend service..."
    check_port  "Backend TCP"    "$BACKEND_HOST"  "$BACKEND_PORT"
    check_endpoint "Backend /health" \
        "http://${BACKEND_HOST}:${BACKEND_PORT}/health" "200"
    check_endpoint "Backend /api/v1/status" \
        "http://${BACKEND_HOST}:${BACKEND_PORT}/api/v1/status" "200"

    echo ""
    log_info "Checking frontend service..."
    check_port  "Frontend TCP"   "$FRONTEND_HOST" "$FRONTEND_PORT"
    check_endpoint "Frontend root" \
        "http://${FRONTEND_HOST}:${FRONTEND_PORT}/" "200"

    echo ""
    echo "====================================="
    echo " Results: PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
    echo "====================================="

    if [ $FAIL -gt 0 ]; then
        log_error "Health check FAILED ($FAIL checks did not pass)"
        return 1
    fi

    log_info "All health checks passed!"
    return 0
}

run_health_checks
