#!/bin/bash
# check_integrations.sh - Verify third-party integrations and external service connectivity
# Part of the deer-flow smoke test suite

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
  source "${SCRIPT_DIR}/common.sh"
fi

# Configuration
TIMEOUT=${INTEGRATION_CHECK_TIMEOUT:-10}
BASE_URL=${BASE_URL:-"http://localhost:8000"}
FRONTEND_URL=${FRONTEND_URL:-"http://localhost:3000"}
PASS=0
FAIL=0
WARN=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

echo "================================================"
echo " Integration Checks"
echo "================================================"
echo ""

# Check LLM API connectivity (OpenAI-compatible endpoint)
check_llm_integration() {
  log_info "Checking LLM API integration..."

  local llm_api_key="${OPENAI_API_KEY:-${LLM_API_KEY:-}}"
  local llm_base_url="${OPENAI_BASE_URL:-https://api.openai.com}"

  if [[ -z "$llm_api_key" ]]; then
    log_warn "LLM API key not set — skipping live LLM connectivity check"
    return
  fi

  if curl -sf --max-time "$TIMEOUT" \
       -H "Authorization: Bearer ${llm_api_key}" \
       "${llm_base_url}/v1/models" > /dev/null 2>&1; then
    log_pass "LLM API endpoint reachable (${llm_base_url})"
  else
    log_warn "LLM API endpoint unreachable or returned error (${llm_base_url})"
  fi
}

# Check search tool integration (Tavily / SearXNG)
check_search_integration() {
  log_info "Checking search tool integration..."

  local tavily_key="${TAVILY_API_KEY:-}"
  local searxng_url="${SEARXNG_BASE_URL:-}"

  if [[ -n "$tavily_key" ]]; then
    if curl -sf --max-time "$TIMEOUT" \
         -X POST "https://api.tavily.com/search" \
         -H "Content-Type: application/json" \
         -d "{\"api_key\":\"${tavily_key}\",\"query\":\"test\",\"max_results\":1}" > /dev/null 2>&1; then
      log_pass "Tavily search API reachable"
    else
      log_warn "Tavily search API unreachable or key invalid"
    fi
  else
    log_warn "TAVILY_API_KEY not set — skipping Tavily check"
  fi

  if [[ -n "$searxng_url" ]]; then
    if curl -sf --max-time "$TIMEOUT" "${searxng_url}/healthz" > /dev/null 2>&1 || \
       curl -sf --max-time "$TIMEOUT" "${searxng_url}" > /dev/null 2>&1; then
      log_pass "SearXNG instance reachable (${searxng_url})"
    else
      log_warn "SearXNG instance unreachable (${searxng_url})"
    fi
  fi
}

# Check backend <-> frontend integration via API health
check_backend_frontend_integration() {
  log_info "Checking backend/frontend integration..."

  local api_health
  api_health=$(curl -sf --max-time "$TIMEOUT" "${BASE_URL}/api/health" 2>/dev/null || echo "")

  if [[ -n "$api_health" ]]; then
    log_pass "Backend API health endpoint responding"
  else
    log_fail "Backend API health endpoint not responding at ${BASE_URL}/api/health"
  fi

  # Verify frontend can reach backend (CORS / proxy config)
  local frontend_status
  frontend_status=$(curl -sf -o /dev/null -w "%{http_code}" \
    --max-time "$TIMEOUT" \
    -H "Origin: ${FRONTEND_URL}" \
    "${BASE_URL}/api/health" 2>/dev/null || echo "000")

  if [[ "$frontend_status" =~ ^2 ]]; then
    log_pass "CORS/proxy allows frontend origin (HTTP ${frontend_status})"
  else
    log_warn "Frontend origin may be blocked or backend unreachable (HTTP ${frontend_status})"
  fi
}

# Check WebSocket / streaming endpoint availability
check_streaming_integration() {
  log_info "Checking streaming endpoint availability..."

  local stream_status
  stream_status=$(curl -sf -o /dev/null -w "%{http_code}" \
    --max-time "$TIMEOUT" \
    -H "Accept: text/event-stream" \
    "${BASE_URL}/api/chat/stream" 2>/dev/null || echo "000")

  # 200 or 405 both indicate the route exists
  if [[ "$stream_status" == "200" || "$stream_status" == "405" || "$stream_status" == "422" ]]; then
    log_pass "Streaming endpoint exists (HTTP ${stream_status})"
  elif [[ "$stream_status" == "404" ]]; then
    log_fail "Streaming endpoint not found at ${BASE_URL}/api/chat/stream"
  else
    log_warn "Streaming endpoint returned unexpected status (HTTP ${stream_status})"
  fi
}

# Run all integration checks
check_llm_integration
check_search_integration
check_backend_frontend_integration
check_streaming_integration

echo ""
echo "------------------------------------------------"
echo " Integration Check Summary"
echo "  Passed : ${PASS}"
echo "  Failed : ${FAIL}"
echo "  Warned : ${WARN}"
echo "------------------------------------------------"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
