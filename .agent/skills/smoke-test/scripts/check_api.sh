#!/bin/bash
# check_api.sh - Validate core API endpoints are responding correctly
# Part of the deer-flow smoke test suite

set -euo pipefail

# Source shared utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/utils.sh" ]]; then
  source "${SCRIPT_DIR}/utils.sh"
fi

# Configuration
API_BASE_URL="${API_BASE_URL:-http://localhost:8000}"
API_TIMEOUT="${API_TIMEOUT:-10}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"

# Tracking
PASSED=0
FAILED=0
SKIPPED=0

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_ok()    { echo "[OK]    $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

# Perform an HTTP request with retry logic
# Usage: do_request <method> <path> [expected_status] [body]
do_request() {
  local method="$1"
  local path="$2"
  local expected_status="${3:-200}"
  local body="${4:-}"
  local url="${API_BASE_URL}${path}"
  local attempt=1

  while [[ $attempt -le $MAX_RETRIES ]]; do
    local curl_args=(
      --silent --show-error
      --max-time "$API_TIMEOUT"
      --write-out "\n%{http_code}"
      -X "$method"
      -H "Content-Type: application/json"
      -H "Accept: application/json"
    )

    if [[ -n "$body" ]]; then
      curl_args+=(--data "$body")
    fi

    local response
    response=$(curl "${curl_args[@]}" "$url" 2>&1) || true

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local resp_body
    resp_body=$(echo "$response" | head -n -1)

    if [[ "$http_code" == "$expected_status" ]]; then
      echo "$resp_body"
      return 0
    fi

    log_warn "Attempt $attempt/$MAX_RETRIES: $method $path returned $http_code (expected $expected_status)"
    attempt=$((attempt + 1))
    sleep "$RETRY_DELAY"
  done

  return 1
}

# Individual endpoint checks
check_health_endpoint() {
  log_info "Checking /health endpoint..."
  if do_request GET "/health" 200 > /dev/null; then
    log_ok "/health returned 200"
    PASSED=$((PASSED + 1))
  else
    log_error "/health check failed"
    FAILED=$((FAILED + 1))
  fi
}

check_api_root() {
  log_info "Checking API root /api/v1/..."
  if do_request GET "/api/v1/" 200 > /dev/null; then
    log_ok "/api/v1/ returned 200"
    PASSED=$((PASSED + 1))
  else
    log_warn "/api/v1/ not available — skipping"
    SKIPPED=$((SKIPPED + 1))
  fi
}

check_chat_endpoint() {
  log_info "Checking /api/v1/chat/completions (smoke payload)..."
  local payload='{"messages":[{"role":"user","content":"ping"}],"stream":false}'
  if do_request POST "/api/v1/chat/completions" 200 "$payload" > /dev/null; then
    log_ok "/api/v1/chat/completions accepted smoke payload"
    PASSED=$((PASSED + 1))
  else
    log_error "/api/v1/chat/completions smoke payload failed"
    FAILED=$((FAILED + 1))
  fi
}

check_models_endpoint() {
  log_info "Checking /api/v1/models..."
  local resp
  if resp=$(do_request GET "/api/v1/models" 200); then
    # Verify response contains at least one model entry
    if echo "$resp" | grep -q '"id"'; then
      log_ok "/api/v1/models returned valid model list"
      PASSED=$((PASSED + 1))
    else
      log_warn "/api/v1/models response missing expected fields"
      FAILED=$((FAILED + 1))
    fi
  else
    log_warn "/api/v1/models not available — skipping"
    SKIPPED=$((SKIPPED + 1))
  fi
}

print_summary() {
  echo ""
  echo "=============================="
  echo " API Check Summary"
  echo "=============================="
  echo "  Passed:  $PASSED"
  echo "  Failed:  $FAILED"
  echo "  Skipped: $SKIPPED"
  echo "=============================="
}

main() {
  log_info "Starting API checks against ${API_BASE_URL}"
  echo ""

  check_health_endpoint
  check_api_root
  check_chat_endpoint
  check_models_endpoint

  print_summary

  if [[ $FAILED -gt 0 ]]; then
    log_error "$FAILED API check(s) failed."
    exit 1
  fi

  log_ok "All critical API checks passed."
  exit 0
}

main "$@"
