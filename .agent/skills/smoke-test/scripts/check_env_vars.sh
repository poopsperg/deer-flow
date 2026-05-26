#!/bin/bash
# check_env_vars.sh - Validate required environment variables for deer-flow
# Checks that all necessary env vars are set and have valid formats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

# Load .env file if present
load_env_file() {
    local env_file="${ROOT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment from ${env_file}"
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    else
        log_warn ".env file not found at ${env_file} — relying on shell environment"
    fi
}

# Check a required variable is set and non-empty
check_required() {
    local var_name="$1"
    local value="${!var_name:-}"
    if [[ -z "$value" ]]; then
        log_fail "Required variable ${var_name} is not set"
    else
        log_pass "${var_name} is set"
    fi
}

# Check an optional variable and warn if missing
check_optional() {
    local var_name="$1"
    local default_hint="${2:-}"
    local value="${!var_name:-}"
    if [[ -z "$value" ]]; then
        local msg="Optional variable ${var_name} is not set"
        [[ -n "$default_hint" ]] && msg+="  (default: ${default_hint})"
        log_warn "$msg"
    else
        log_pass "${var_name} is set"
    fi
}

# Check that a variable matches a regex pattern
check_format() {
    local var_name="$1"
    local pattern="$2"
    local description="$3"
    local value="${!var_name:-}"
    if [[ -z "$value" ]]; then
        log_fail "${var_name} is not set (expected format: ${description})"
        return
    fi
    if [[ "$value" =~ $pattern ]]; then
        log_pass "${var_name} has valid format (${description})"
    else
        log_fail "${var_name} has invalid format — expected ${description}, got: ${value}"
    fi
}

# Check a URL variable is reachable (basic connectivity)
check_url_reachable() {
    local var_name="$1"
    local value="${!var_name:-}"
    if [[ -z "$value" ]]; then
        log_fail "${var_name} is not set — cannot check reachability"
        return
    fi
    if curl -sf --max-time 5 "$value" > /dev/null 2>&1; then
        log_pass "${var_name} URL is reachable (${value})"
    else
        log_warn "${var_name} URL may not be reachable (${value}) — check network or service status"
    fi
}

main() {
    echo "======================================"
    echo "  deer-flow Environment Variable Check"
    echo "======================================"
    echo ""

    load_env_file

    log_info "--- LLM / AI Provider ---"
    check_required "OPENAI_API_KEY"
    check_optional "OPENAI_BASE_URL" "https://api.openai.com/v1"
    check_optional "OPENAI_MODEL" "gpt-4o"
    check_optional "ANTHROPIC_API_KEY"
    check_optional "AZURE_OPENAI_API_KEY"
    check_optional "AZURE_OPENAI_ENDPOINT"

    log_info ""
    log_info "--- Search / Tools ---"
    check_optional "TAVILY_API_KEY"
    check_optional "BRAVE_SEARCH_API_KEY"
    check_optional "SERPAPI_API_KEY"

    log_info ""
    log_info "--- Application Config ---"
    check_optional "APP_ENV" "development"
    check_optional "LOG_LEVEL" "INFO"
    check_format  "APP_PORT" '^[0-9]{4,5}$' "numeric port (e.g. 8000)"

    log_info ""
    log_info "--- Database / Cache (if applicable) ---"
    check_optional "DATABASE_URL"
    check_optional "REDIS_URL"

    log_info ""
    log_info "--- Frontend ---"
    check_optional "NEXT_PUBLIC_API_URL" "http://localhost:8000"

    echo ""
    echo "======================================"
    echo "  Results: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
    echo "======================================"

    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}Environment check FAILED — fix the above errors before proceeding.${NC}"
        exit 1
    elif [[ $WARN -gt 0 ]]; then
        echo -e "${YELLOW}Environment check passed with warnings.${NC}"
        exit 0
    else
        echo -e "${GREEN}Environment check PASSED.${NC}"
        exit 0
    fi
}

main "$@"
