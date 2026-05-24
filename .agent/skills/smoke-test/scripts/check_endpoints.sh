#!/bin/bash
# check_endpoints.sh - Validate all API endpoints respond correctly
# Part of the deer-flow smoke test suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8000}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
TIMEOUT="${ENDPOINT_TIMEOUT:-10}"
MAX_RETRIES="${MAX_RETRIES:-3}"
PASS=0
FAIL=0
SKIP=0

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check a single endpoint with retry logic
check_endpoint() {
    local name="$1"
    local method="$2"
    local url="$3"
    local expected_status="$4"
    local payload="${5:-}"

    local attempt=0
    local status_code

    while [ $attempt -lt $MAX_RETRIES ]; do
        attempt=$((attempt + 1))

        if [ -n "$payload" ]; then
            status_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time "$TIMEOUT" \
                -X "$method" \
                -H "Content-Type: application/json" \
                -d "$payload" \
                "$url" 2>/dev/null) || status_code="000"
        else
            status_code=$(curl -s -o /dev/null -w "%{http_code}" \
                --max-time "$TIMEOUT" \
                -X "$method" \
                "$url" 2>/dev/null) || status_code="000"
        fi

        if [ "$status_code" = "$expected_status" ]; then
            log_info "PASS [$name] $method $url -> $status_code"
            PASS=$((PASS + 1))
            return 0
        fi

        [ $attempt -lt $MAX_RETRIES ] && sleep 1
    done

    log_error "FAIL [$name] $method $url -> got $status_code, expected $expected_status"
    FAIL=$((FAIL + 1))
    return 1
}

# Check endpoint returns valid JSON
check_json_endpoint() {
    local name="$1"
    local url="$2"
    local response

    response=$(curl -s --max-time "$TIMEOUT" "$url" 2>/dev/null) || {
        log_error "FAIL [$name] could not reach $url"
        FAIL=$((FAIL + 1))
        return 1
    }

    if echo "$response" | python3 -m json.tool > /dev/null 2>&1; then
        log_info "PASS [$name] valid JSON from $url"
        PASS=$((PASS + 1))
    else
        log_error "FAIL [$name] invalid JSON from $url"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

log_info "Starting endpoint checks against $BASE_URL"
echo "-------------------------------------------"

# Backend health & core endpoints
check_endpoint "health"          GET  "${BASE_URL}/health"          200
check_endpoint "api-docs"        GET  "${BASE_URL}/docs"            200
check_endpoint "openapi-schema"  GET  "${BASE_URL}/openapi.json"    200

# Chat / research endpoints
check_endpoint "chat-list"       GET  "${BASE_URL}/api/chat"        200
check_endpoint "models-list"     GET  "${BASE_URL}/api/models"      200

# Expect 422 (validation error) on empty POST rather than 500
check_endpoint "chat-post-empty" POST "${BASE_URL}/api/chat"        422 "{}"

# Frontend availability (if running)
if curl -s --max-time 3 "${FRONTEND_URL}" > /dev/null 2>&1; then
    check_endpoint "frontend-root"  GET "${FRONTEND_URL}"           200
    check_endpoint "frontend-health" GET "${FRONTEND_URL}/api/health" 200
else
    log_warn "SKIP frontend checks — $FRONTEND_URL not reachable"
    SKIP=$((SKIP + 1))
fi

# Validate JSON responses for key endpoints
check_json_endpoint "health-json"   "${BASE_URL}/health"
check_json_endpoint "openapi-json"  "${BASE_URL}/openapi.json"

echo "-------------------------------------------"
log_info "Endpoint check summary: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"

# Export for aggregation by run_all_checks.sh
export ENDPOINT_PASS=$PASS
export ENDPOINT_FAIL=$FAIL
export ENDPOINT_SKIP=$SKIP

[ "$FAIL" -eq 0 ]
