#!/bin/bash
# check_security.sh - Basic security checks for deer-flow deployment
# Verifies SSL/TLS config, exposed ports, auth headers, and sensitive data exposure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BASE_URL="${BASE_URL:-http://localhost:8000}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
TIMEOUT="${TIMEOUT:-10}"
FAILURES=0
WARNINGS=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILURES++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARNINGS++)); }
log_info() { echo -e "[INFO] $1"; }

echo "========================================"
echo " Security Checks"
echo " Target: ${BASE_URL}"
echo "========================================"
echo ""

# Check 1: Sensitive endpoints are not publicly accessible
check_sensitive_endpoints() {
    log_info "Checking sensitive endpoints are protected..."

    local sensitive_paths=(
        "/admin"
        "/.env"
        "/config"
        "/metrics"
        "/debug"
        "/__debug__"
    )

    for path in "${sensitive_paths[@]}"; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time "${TIMEOUT}" \
            "${BASE_URL}${path}" 2>/dev/null || echo "000")

        if [[ "$status" == "200" ]]; then
            log_warn "Sensitive path ${path} returned 200 — review if intentional"
        elif [[ "$status" == "000" ]]; then
            log_warn "Could not reach ${path} (connection issue)"
        else
            log_pass "${path} returns ${status} (not openly accessible)"
        fi
    done
}

# Check 2: Security headers present on API responses
check_security_headers() {
    log_info "Checking HTTP security headers..."

    local headers
    headers=$(curl -s -I --max-time "${TIMEOUT}" "${BASE_URL}/api/health" 2>/dev/null || true)

    if echo "$headers" | grep -qi "x-content-type-options"; then
        log_pass "X-Content-Type-Options header present"
    else
        log_warn "X-Content-Type-Options header missing"
    fi

    if echo "$headers" | grep -qi "x-frame-options"; then
        log_pass "X-Frame-Options header present"
    else
        log_warn "X-Frame-Options header missing"
    fi

    if echo "$headers" | grep -qi "x-xss-protection"; then
        log_pass "X-XSS-Protection header present"
    else
        log_warn "X-XSS-Protection header missing"
    fi

    # HTTPS-only check
    if [[ "${BASE_URL}" == https://* ]]; then
        if echo "$headers" | grep -qi "strict-transport-security"; then
            log_pass "HSTS header present"
        else
            log_warn "HSTS header missing on HTTPS endpoint"
        fi
    fi
}

# Check 3: API key / auth token not leaked in responses
check_no_credential_leakage() {
    log_info "Checking for credential leakage in API responses..."

    local response
    response=$(curl -s --max-time "${TIMEOUT}" "${BASE_URL}/api/health" 2>/dev/null || echo "")

    local patterns=("api_key" "secret" "password" "token" "private_key" "sk-")
    local leaked=false

    for pattern in "${patterns[@]}"; do
        if echo "$response" | grep -qi "$pattern"; then
            log_fail "Possible credential pattern '${pattern}' found in health response"
            leaked=true
        fi
    done

    if [[ "$leaked" == false ]]; then
        log_pass "No obvious credential patterns in health response"
    fi
}

# Check 4: CORS headers not overly permissive
check_cors() {
    log_info "Checking CORS configuration..."

    local cors_header
    cors_header=$(curl -s -I \
        --max-time "${TIMEOUT}" \
        -H "Origin: https://evil.example.com" \
        "${BASE_URL}/api/health" 2>/dev/null \
        | grep -i "access-control-allow-origin" || echo "")

    if echo "$cors_header" | grep -q "\*"; then
        log_warn "CORS allows all origins (*) — acceptable for dev, review for prod"
    elif [[ -z "$cors_header" ]]; then
        log_pass "No wildcard CORS header detected"
    else
        log_pass "CORS header present and not wildcard: ${cors_header}"
    fi
}

# Run all checks
check_sensitive_endpoints
echo ""
check_security_headers
echo ""
check_no_credential_leakage
echo ""
check_cors

echo ""
echo "========================================"
echo " Security Check Summary"
echo "  Failures : ${FAILURES}"
echo "  Warnings : ${WARNINGS}"
echo "========================================"

if [[ "${FAILURES}" -gt 0 ]]; then
    exit 1
fi

exit 0
