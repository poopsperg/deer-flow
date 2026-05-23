#!/bin/bash
# run_all_checks.sh - Master smoke test runner for deer-flow
# Runs all environment and deployment checks in sequence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/smoke_test_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track results
PASSED=0
FAILED=0
SKIPPED=0

mkdir -p "${LOG_DIR}"

log() {
    echo -e "$1" | tee -a "${LOG_FILE}"
}

print_header() {
    log ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}  deer-flow Smoke Test Suite${NC}"
    log "${BLUE}  Started: $(date)${NC}"
    log "${BLUE}========================================${NC}"
    log ""
}

print_summary() {
    log ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}  Smoke Test Summary${NC}"
    log "${BLUE}========================================${NC}"
    log "  ${GREEN}Passed:  ${PASSED}${NC}"
    log "  ${RED}Failed:  ${FAILED}${NC}"
    log "  ${YELLOW}Skipped: ${SKIPPED}${NC}"
    log "  Log file: ${LOG_FILE}"
    log "${BLUE}========================================${NC}"
    log ""
}

run_check() {
    local name="$1"
    local script="$2"
    local required="${3:-true}"

    log "${YELLOW}[CHECK]${NC} Running: ${name}"

    if [ ! -f "${script}" ]; then
        log "${YELLOW}[SKIP]${NC}  Script not found: ${script}"
        ((SKIPPED++)) || true
        return 0
    fi

    if bash "${script}" >> "${LOG_FILE}" 2>&1; then
        log "${GREEN}[PASS]${NC}  ${name}"
        ((PASSED++)) || true
    else
        local exit_code=$?
        if [ "${required}" = "true" ]; then
            log "${RED}[FAIL]${NC}  ${name} (exit code: ${exit_code})"
            ((FAILED++)) || true
        else
            log "${YELLOW}[WARN]${NC}  ${name} failed but is optional (exit code: ${exit_code})"
            ((SKIPPED++)) || true
        fi
    fi
}

# Parse CLI args
DEPLOY_MODE="local"  # local | docker | all
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            DEPLOY_MODE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--mode local|docker|all]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header
log "Deploy mode: ${DEPLOY_MODE}"

# Always run environment checks
run_check "Local Environment" "${SCRIPT_DIR}/check_local_env.sh" "true"
run_check "Frontend Dependencies" "${SCRIPT_DIR}/frontend_check.sh" "true"

# Conditionally run Docker checks
if [[ "${DEPLOY_MODE}" == "docker" || "${DEPLOY_MODE}" == "all" ]]; then
    run_check "Docker Environment" "${SCRIPT_DIR}/check_docker.sh" "true"
    run_check "Docker Deployment" "${SCRIPT_DIR}/deploy_docker.sh" "false"
fi

# Run local deployment check
if [[ "${DEPLOY_MODE}" == "local" || "${DEPLOY_MODE}" == "all" ]]; then
    run_check "Local Deployment" "${SCRIPT_DIR}/deploy_local.sh" "false"
fi

print_summary

# Exit with failure if any required checks failed
if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi

exit 0
