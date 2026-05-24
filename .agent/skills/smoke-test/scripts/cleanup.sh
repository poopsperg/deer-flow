#!/bin/bash
# cleanup.sh - Clean up resources after smoke tests
# Removes temporary files, stops test containers, and resets environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/.agent/logs"
TMP_DIR="${PROJECT_ROOT}/.agent/tmp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[CLEANUP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[CLEANUP]${NC} $1"
}

log_error() {
    echo -e "${RED}[CLEANUP]${NC} $1" >&2
}

# Parse flags
FORCE=false
KEEP_LOGS=false
DOCKER_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --docker)
            DOCKER_MODE=true
            shift
            ;;
        *)
            log_warn "Unknown argument: $1"
            shift
            ;;
    esac
done

cleanup_tmp_files() {
    log_info "Removing temporary files..."
    if [[ -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
        log_info "Removed ${TMP_DIR}"
    else
        log_warn "No tmp directory found at ${TMP_DIR}"
    fi
}

cleanup_logs() {
    if [[ "${KEEP_LOGS}" == "true" ]]; then
        log_info "Skipping log cleanup (--keep-logs flag set)"
        return
    fi

    log_info "Cleaning up old log files..."
    if [[ -d "${LOG_DIR}" ]]; then
        # Keep the most recent 5 log files, remove the rest
        find "${LOG_DIR}" -name "smoke-test-*.log" -type f | sort -r | tail -n +6 | xargs -r rm -f
        log_info "Old logs pruned (kept latest 5)"
    fi
}

cleanup_docker() {
    if [[ "${DOCKER_MODE}" != "true" ]]; then
        return
    fi

    log_info "Stopping and removing smoke-test Docker containers..."

    if ! command -v docker &>/dev/null; then
        log_warn "Docker not found, skipping Docker cleanup"
        return
    fi

    # Stop containers started by deploy_docker.sh (labeled for smoke-test)
    local containers
    containers=$(docker ps -a --filter "label=deer-flow.smoke-test=true" -q 2>/dev/null || true)

    if [[ -n "${containers}" ]]; then
        echo "${containers}" | xargs docker rm -f
        log_info "Removed smoke-test containers"
    else
        log_warn "No smoke-test containers found"
    fi

    # Remove dangling images created during tests if force flag is set
    if [[ "${FORCE}" == "true" ]]; then
        log_info "Force mode: removing dangling Docker images..."
        docker image prune -f --filter "label=deer-flow.smoke-test=true" 2>/dev/null || true
    fi
}

cleanup_env_overrides() {
    local env_override="${PROJECT_ROOT}/.env.smoke-test"
    if [[ -f "${env_override}" ]]; then
        log_info "Removing smoke-test env override: ${env_override}"
        rm -f "${env_override}"
    fi
}

main() {
    log_info "Starting cleanup for smoke-test environment..."
    log_info "Project root: ${PROJECT_ROOT}"

    cleanup_tmp_files
    cleanup_logs
    cleanup_docker
    cleanup_env_overrides

    log_info "Cleanup complete."
}

main
