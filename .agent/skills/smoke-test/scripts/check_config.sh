#!/bin/bash
# check_config.sh - Verify application configuration files and environment variables
# Part of the deer-flow smoke test suite

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

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

echo "======================================"
echo "  Configuration Check"
echo "======================================"
echo ""

# Check for .env file existence
check_env_file() {
    log_info "Checking .env file..."

    if [ -f "${PROJECT_ROOT}/.env" ]; then
        log_pass ".env file exists"
    elif [ -f "${PROJECT_ROOT}/.env.example" ]; then
        log_warn ".env file missing but .env.example found — copy and configure it"
    else
        log_fail ".env file not found and no .env.example available"
    fi
}

# Check required environment variables
check_required_vars() {
    log_info "Checking required environment variables..."

    local env_file="${PROJECT_ROOT}/.env"
    local required_vars=(
        "TAVILY_API_KEY"
        "OPENAI_API_KEY"
    )

    # Load .env if it exists
    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file" 2>/dev/null || true
        set +a
    fi

    for var in "${required_vars[@]}"; do
        if [ -n "${!var:-}" ]; then
            # Mask the value for security
            local masked="${!var:0:4}****"
            log_pass "${var} is set (${masked})"
        else
            log_fail "${var} is not set or empty"
        fi
    done
}

# Check optional but recommended variables
check_optional_vars() {
    log_info "Checking optional environment variables..."

    local optional_vars=(
        "LANGCHAIN_API_KEY"
        "LANGCHAIN_TRACING_V2"
        "LANGCHAIN_PROJECT"
        "OPENAI_BASE_URL"
    )

    if [ -f "${PROJECT_ROOT}/.env" ]; then
        set -a
        # shellcheck disable=SC1090
        source "${PROJECT_ROOT}/.env" 2>/dev/null || true
        set +a
    fi

    for var in "${optional_vars[@]}"; do
        if [ -n "${!var:-}" ]; then
            log_pass "${var} is set (optional)"
        else
            log_warn "${var} not set (optional, may limit functionality)"
        fi
    done
}

# Validate conf.yaml if present
check_conf_yaml() {
    log_info "Checking conf.yaml..."

    local conf_file="${PROJECT_ROOT}/conf.yaml"

    if [ ! -f "$conf_file" ]; then
        log_fail "conf.yaml not found at project root"
        return
    fi

    log_pass "conf.yaml exists"

    # Check for required top-level keys
    local required_keys=("llm" "search")
    for key in "${required_keys[@]}"; do
        if grep -q "^${key}:" "$conf_file" 2>/dev/null; then
            log_pass "conf.yaml has '${key}' section"
        else
            log_warn "conf.yaml missing '${key}' section"
        fi
    done
}

# Check frontend config
check_frontend_config() {
    log_info "Checking frontend configuration..."

    local web_dir="${PROJECT_ROOT}/web"

    if [ ! -d "$web_dir" ]; then
        log_warn "web/ directory not found, skipping frontend config check"
        return
    fi

    if [ -f "${web_dir}/.env" ] || [ -f "${web_dir}/.env.local" ]; then
        log_pass "Frontend .env file found"
    else
        log_warn "No frontend .env/.env.local found (may use defaults)"
    fi
}

# Run all checks
check_env_file
check_required_vars
check_optional_vars
check_conf_yaml
check_frontend_config

echo ""
echo "======================================"
echo "  Config Check Summary"
echo "======================================"
echo -e "  ${GREEN}PASS${NC}: ${PASS}"
echo -e "  ${YELLOW}WARN${NC}: ${WARN}"
echo -e "  ${RED}FAIL${NC}: ${FAIL}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}Configuration check FAILED — fix the issues above before proceeding.${NC}"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}Configuration check passed with warnings.${NC}"
    exit 0
else
    echo -e "${GREEN}Configuration check PASSED.${NC}"
    exit 0
fi
