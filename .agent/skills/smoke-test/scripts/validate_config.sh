#!/bin/bash
# validate_config.sh - Validates environment configuration before smoke tests
# Checks for required env vars, config files, and service dependencies

set -euo pipefail

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

echo "================================================"
echo " DeerFlow Config Validation"
echo "================================================"
echo ""

# --- Check for .env file ---
log_info "Checking for .env file..."
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    log_pass ".env file exists"
    # shellcheck disable=SC1090
    source "${PROJECT_ROOT}/.env" 2>/dev/null || log_warn "Could not source .env (non-fatal)"
elif [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
    log_warn ".env not found, but .env.example exists — consider copying it"
else
    log_fail ".env file missing and no .env.example found"
fi

# --- Required environment variables ---
log_info "Checking required environment variables..."

REQUIRED_VARS=(
    "OPENAI_API_KEY"
)

OPTIONAL_VARS=(
    "TAVILY_API_KEY"
    "OPENAI_BASE_URL"
    "NEXT_PUBLIC_API_URL"
    "DATABASE_URL"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        log_pass "${var} is set"
    else
        log_fail "${var} is NOT set (required)"
    fi
done

for var in "${OPTIONAL_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        log_pass "${var} is set"
    else
        log_warn "${var} is not set (optional)"
    fi
done

# --- Check key config files ---
log_info "Checking project config files..."

CONFIG_FILES=(
    "pyproject.toml"
    "package.json"
    "docker-compose.yml"
)

for cfg in "${CONFIG_FILES[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${cfg}" ]]; then
        log_pass "${cfg} found"
    else
        log_warn "${cfg} not found"
    fi
done

# --- Validate Python version ---
log_info "Checking Python version..."
if command -v python3 &>/dev/null; then
    PY_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    PY_MAJOR=$(echo "${PY_VERSION}" | cut -d. -f1)
    PY_MINOR=$(echo "${PY_VERSION}" | cut -d. -f2)
    if [[ "${PY_MAJOR}" -ge 3 && "${PY_MINOR}" -ge 10 ]]; then
        log_pass "Python ${PY_VERSION} meets minimum requirement (3.10+)"
    else
        log_fail "Python ${PY_VERSION} is below minimum requirement (3.10+)"
    fi
else
    log_fail "python3 not found in PATH"
fi

# --- Validate Node version ---
log_info "Checking Node.js version..."
if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version | tr -d 'v')
    NODE_MAJOR=$(echo "${NODE_VERSION}" | cut -d. -f1)
    if [[ "${NODE_MAJOR}" -ge 18 ]]; then
        log_pass "Node.js v${NODE_VERSION} meets minimum requirement (18+)"
    else
        log_fail "Node.js v${NODE_VERSION} is below minimum requirement (18+)"
    fi
else
    log_warn "node not found — frontend checks may be skipped"
fi

# --- Summary ---
echo ""
echo "================================================"
echo " Validation Summary"
echo "================================================"
echo -e "  ${GREEN}Passed:${NC}   ${PASS}"
echo -e "  ${YELLOW}Warnings:${NC} ${WARN}"
echo -e "  ${RED}Failed:${NC}   ${FAIL}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
    echo -e "${RED}Config validation FAILED. Fix the above issues before running smoke tests.${NC}"
    exit 1
else
    echo -e "${GREEN}Config validation PASSED.${NC}"
    exit 0
fi
