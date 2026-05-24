#!/bin/bash
# run_smoke_test.sh - Main entry point for the smoke test suite
# Orchestrates the full smoke test workflow from config validation to reporting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Default values
DEPLOY_MODE="local"   # local | docker
SKIP_DEPLOY=false
SKIP_CLEANUP=false
VERBOSE=false
REPORT_FORMAT="text"  # text | json | markdown
EXIT_CODE=0

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run the full deer-flow smoke test suite.

Options:
  -m, --mode MODE        Deployment mode: local or docker (default: local)
  -s, --skip-deploy      Skip deployment step (assume services are already running)
  -k, --skip-cleanup     Skip cleanup after tests
  -r, --report FORMAT    Report format: text, json, or markdown (default: text)
  -v, --verbose          Enable verbose output
  -h, --help             Show this help message

Examples:
  $(basename "$0") --mode docker
  $(basename "$0") --mode local --skip-deploy --report markdown
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mode)        DEPLOY_MODE="$2"; shift 2 ;;
      -s|--skip-deploy) SKIP_DEPLOY=true; shift ;;
      -k|--skip-cleanup) SKIP_CLEANUP=true; shift ;;
      -r|--report)      REPORT_FORMAT="$2"; shift 2 ;;
      -v|--verbose)     VERBOSE=true; shift ;;
      -h|--help)        usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  if [[ "$DEPLOY_MODE" != "local" && "$DEPLOY_MODE" != "docker" ]]; then
    log_error "Invalid mode '$DEPLOY_MODE'. Must be 'local' or 'docker'."
    exit 1
  fi
}

run_step() {
  local label="$1"
  local script="$2"
  shift 2

  log_info "Step: $label"
  if [[ "$VERBOSE" == true ]]; then
    bash "$SCRIPT_DIR/$script" "$@"
  else
    bash "$SCRIPT_DIR/$script" "$@" 2>&1 | grep -E '^(\[|ERROR|WARN|OK)' || true
  fi
}

main() {
  parse_args "$@"

  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}  deer-flow Smoke Test Suite${NC}"
  echo -e "${BLUE}========================================${NC}"
  log_info "Mode: $DEPLOY_MODE | Skip deploy: $SKIP_DEPLOY | Report: $REPORT_FORMAT"
  echo ""

  # 1. Validate configuration
  run_step "Validate config" validate_config.sh || { log_error "Config validation failed."; exit 1; }

  # 2. Check environment prerequisites
  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    run_step "Check Docker env" check_docker.sh || { log_error "Docker environment check failed."; exit 1; }
  else
    run_step "Check local env" check_local_env.sh || { log_error "Local environment check failed."; exit 1; }
  fi

  # 3. Deploy (unless skipped)
  if [[ "$SKIP_DEPLOY" == false ]]; then
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
      run_step "Deploy (Docker)" deploy_docker.sh
    else
      run_step "Deploy (local)" deploy_local.sh
    fi
  else
    log_warn "Skipping deployment step."
  fi

  # 4. Health check
  run_step "Health check" health_check.sh || EXIT_CODE=1

  # 5. Service checks
  run_step "Service checks" check_services.sh || EXIT_CODE=1

  # 6. Frontend checks
  run_step "Frontend checks" frontend_check.sh || EXIT_CODE=1

  # 7. Run all functional checks
  run_step "Functional checks" run_all_checks.sh || EXIT_CODE=1

  # 8. Report results
  run_step "Report results" report_results.sh --format "$REPORT_FORMAT"

  # 9. Cleanup
  if [[ "$SKIP_CLEANUP" == false ]]; then
    run_step "Cleanup" cleanup.sh
  else
    log_warn "Skipping cleanup step."
  fi

  echo ""
  if [[ $EXIT_CODE -eq 0 ]]; then
    log_ok "Smoke test suite PASSED."
  else
    log_error "Smoke test suite FAILED. Check the report for details."
  fi

  exit $EXIT_CODE
}

main "$@"
