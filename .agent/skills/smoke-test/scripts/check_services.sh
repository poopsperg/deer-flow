#!/bin/bash
# check_services.sh - Verify all required services are running and healthy
# Part of the deer-flow smoke test suite

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNED=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARNED++)); }
log_info() { echo -e "[INFO] $1"; }

# Default service endpoints (can be overridden via env vars)
BACKEND_HOST="${BACKEND_HOST:-localhost}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_HOST="${FRONTEND_HOST:-localhost}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-10}"

BACKEND_URL="http://${BACKEND_HOST}:${BACKEND_PORT}"
FRONTEND_URL="http://${FRONTEND_HOST}:${FRONTEND_PORT}"

echo "================================================"
echo "  deer-flow Service Health Check"
echo "================================================"
echo ""

# --- Backend checks ---
log_info "Checking backend service at ${BACKEND_URL}..."

# Basic connectivity
if curl -sf --max-time "${HEALTH_TIMEOUT}" "${BACKEND_URL}/health" > /dev/null 2>&1; then
    log_pass "Backend /health endpoint is reachable"
else
    log_fail "Backend /health endpoint is not responding at ${BACKEND_URL}/health"
fi

# Check API docs are available
if curl -sf --max-time "${HEALTH_TIMEOUT}" "${BACKEND_URL}/docs" > /dev/null 2>&1; then
    log_pass "Backend /docs (Swagger UI) is accessible"
else
    log_warn "Backend /docs not accessible — may be disabled in production"
fi

# Check OpenAPI schema
if curl -sf --max-time "${HEALTH_TIMEOUT}" "${BACKEND_URL}/openapi.json" > /dev/null 2>&1; then
    log_pass "Backend OpenAPI schema is accessible"
else
    log_warn "Backend /openapi.json not accessible"
fi

# Validate health response body if jq is available
if command -v jq &> /dev/null; then
    HEALTH_RESPONSE=$(curl -sf --max-time "${HEALTH_TIMEOUT}" "${BACKEND_URL}/health" 2>/dev/null || echo "{}")
    STATUS=$(echo "${HEALTH_RESPONSE}" | jq -r '.status // empty' 2>/dev/null)
    if [[ "${STATUS}" == "ok" || "${STATUS}" == "healthy" ]]; then
        log_pass "Backend health status reports: ${STATUS}"
    elif [[ -n "${STATUS}" ]]; then
        log_warn "Backend health status is: ${STATUS}"
    fi
fi

echo ""

# --- Frontend checks ---
log_info "Checking frontend service at ${FRONTEND_URL}..."

if curl -sf --max-time "${HEALTH_TIMEOUT}" "${FRONTEND_URL}" > /dev/null 2>&1; then
    log_pass "Frontend is reachable at ${FRONTEND_URL}"
else
    log_fail "Frontend is not responding at ${FRONTEND_URL}"
fi

# Check that frontend returns HTML
FRONTEND_CONTENT_TYPE=$(curl -sI --max-time "${HEALTH_TIMEOUT}" "${FRONTEND_URL}" 2>/dev/null \
    | grep -i 'content-type' | head -1 || echo "")
if echo "${FRONTEND_CONTENT_TYPE}" | grep -qi 'text/html'; then
    log_pass "Frontend returns text/html content"
else
    log_warn "Frontend content-type is unexpected: ${FRONTEND_CONTENT_TYPE:-unknown}"
fi

echo ""

# --- Summary ---
echo "================================================"
echo "  Results: ${PASSED} passed | ${FAILED} failed | ${WARNED} warnings"
echo "================================================"

if [[ ${FAILED} -gt 0 ]]; then
    echo -e "${RED}Service check FAILED. See above for details.${NC}"
    exit 1
else
    echo -e "${GREEN}All critical service checks passed.${NC}"
    exit 0
fi
