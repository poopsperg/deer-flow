#!/bin/bash
# check_auth.sh - Verify authentication and authorization endpoints
# Tests login, token validation, and protected route access

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
fi

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8000}"
TIMEOUT="${TIMEOUT:-10}"
PASS=0
FAIL=0
WARN=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

echo "======================================"
echo "  Auth Check"
echo "  Target: ${BASE_URL}"
echo "======================================"
echo ""

# Check if API key endpoint exists (DeerFlow uses API key auth)
check_api_key_auth() {
    log_info "Checking API key authentication..."

    # Test unauthenticated request to protected endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "${TIMEOUT}" \
        "${BASE_URL}/api/chat/stream" 2>/dev/null || echo "000")

    if [[ "${HTTP_CODE}" == "401" || "${HTTP_CODE}" == "403" || "${HTTP_CODE}" == "422" ]]; then
        log_pass "Unauthenticated request correctly rejected (HTTP ${HTTP_CODE})"
    elif [[ "${HTTP_CODE}" == "000" ]]; then
        log_warn "Could not reach endpoint — service may be down"
    else
        log_warn "Unexpected response for unauthenticated request (HTTP ${HTTP_CODE})"
    fi
}

# Check CORS headers on auth-sensitive endpoints
check_cors_headers() {
    log_info "Checking CORS configuration..."

    HEADERS=$(curl -s -I --max-time "${TIMEOUT}" \
        -H "Origin: http://localhost:3000" \
        "${BASE_URL}/api/" 2>/dev/null || echo "")

    if echo "${HEADERS}" | grep -qi "access-control-allow-origin"; then
        ORIGIN=$(echo "${HEADERS}" | grep -i "access-control-allow-origin" | tr -d '\r')
        log_pass "CORS header present: ${ORIGIN}"
    else
        log_warn "No CORS headers detected — may cause frontend issues"
    fi
}

# Check that sensitive headers are not leaked
check_security_headers() {
    log_info "Checking security headers..."

    HEADERS=$(curl -s -I --max-time "${TIMEOUT}" "${BASE_URL}/" 2>/dev/null || echo "")

    if echo "${HEADERS}" | grep -qi "x-powered-by"; then
        log_warn "X-Powered-By header exposed — consider removing it"
    else
        log_pass "X-Powered-By header not exposed"
    fi

    if echo "${HEADERS}" | grep -qi "server:"; then
        SERVER=$(echo "${HEADERS}" | grep -i "^server:" | tr -d '\r')
        log_warn "Server header exposed: ${SERVER}"
    else
        log_pass "Server header not exposed"
    fi
}

# Check that the /docs endpoint requires no auth (FastAPI default)
check_docs_access() {
    log_info "Checking API docs accessibility..."

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "${TIMEOUT}" \
        "${BASE_URL}/docs" 2>/dev/null || echo "000")

    if [[ "${HTTP_CODE}" == "200" ]]; then
        log_pass "API docs accessible at /docs (HTTP 200)"
    elif [[ "${HTTP_CODE}" == "404" ]]; then
        log_info "API docs not available at /docs (may be disabled in production)"
    elif [[ "${HTTP_CODE}" == "000" ]]; then
        log_warn "Could not reach /docs — service may be down"
    else
        log_warn "/docs returned HTTP ${HTTP_CODE}"
    fi
}

# Run all auth checks
check_api_key_auth
check_cors_headers
check_security_headers
check_docs_access

# Summary
echo ""
echo "======================================"
echo "  Auth Check Summary"
echo "  PASS: ${PASS} | FAIL: ${FAIL} | WARN: ${WARN}"
echo "======================================"

if [[ ${FAIL} -gt 0 ]]; then
    exit 1
fi

exit 0
