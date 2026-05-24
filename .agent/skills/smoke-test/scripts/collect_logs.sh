#!/bin/bash
# collect_logs.sh - Collect logs from all services for debugging and reporting
# Part of the deer-flow smoke test skill

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="${LOGS_DIR:-/tmp/deer-flow-smoke-test/logs}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="deer-flow-logs-${TIMESTAMP}.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Ensure logs directory exists
mkdir -p "${LOGS_DIR}"

collect_docker_logs() {
    log_info "Collecting Docker container logs..."
    local docker_log_dir="${LOGS_DIR}/docker"
    mkdir -p "${docker_log_dir}"

    if ! command -v docker &>/dev/null; then
        log_warn "Docker not found, skipping container log collection"
        return 0
    fi

    # Collect logs from deer-flow related containers
    local containers
    containers=$(docker ps -a --filter "name=deer-flow" --format "{{.Names}}" 2>/dev/null || true)

    if [[ -z "${containers}" ]]; then
        log_warn "No deer-flow containers found"
        return 0
    fi

    while IFS= read -r container; do
        [[ -z "${container}" ]] && continue
        local log_file="${docker_log_dir}/${container}.log"
        log_info "  Collecting logs from container: ${container}"
        docker logs "${container}" > "${log_file}" 2>&1 || log_warn "Failed to collect logs from ${container}"
    done <<< "${containers}"

    # Collect docker-compose logs if available
    if command -v docker-compose &>/dev/null && [[ -f "docker-compose.yml" ]]; then
        log_info "  Collecting docker-compose logs..."
        docker-compose logs --no-color > "${docker_log_dir}/docker-compose.log" 2>&1 || true
    fi
}

collect_local_process_logs() {
    log_info "Collecting local process logs..."
    local proc_log_dir="${LOGS_DIR}/processes"
    mkdir -p "${proc_log_dir}"

    # Common log locations for deer-flow services
    local log_paths=(
        "/tmp/deer-flow*.log"
        "/tmp/deerflow*.log"
        "./logs/*.log"
        "./backend/logs/*.log"
        "./frontend/.next/server/*.log"
    )

    for pattern in "${log_paths[@]}"; do
        # Use glob expansion safely
        for f in $pattern; do
            [[ -f "${f}" ]] || continue
            local dest="${proc_log_dir}/$(basename "${f}")"
            log_info "  Copying: ${f}"
            cp "${f}" "${dest}" 2>/dev/null || log_warn "Failed to copy ${f}"
        done
    done
}

collect_system_info() {
    log_info "Collecting system information..."
    local sys_log="${LOGS_DIR}/system_info.txt"

    {
        echo "=== System Info ==="
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "OS: $(uname -a)"
        echo ""
        echo "=== Python ==="
        python3 --version 2>&1 || echo "Python3 not found"
        echo ""
        echo "=== Node ==="
        node --version 2>&1 || echo "Node not found"
        npm --version 2>&1 || echo "npm not found"
        echo ""
        echo "=== Docker ==="
        docker --version 2>&1 || echo "Docker not found"
        docker-compose --version 2>&1 || echo "docker-compose not found"
        echo ""
        echo "=== Disk Usage ==="
        df -h 2>/dev/null || true
        echo ""
        echo "=== Memory ==="
        free -h 2>/dev/null || vm_stat 2>/dev/null || true
    } > "${sys_log}" 2>&1
}

create_archive() {
    log_info "Creating log archive: ${ARCHIVE_NAME}"
    local archive_path="/tmp/${ARCHIVE_NAME}"
    tar -czf "${archive_path}" -C "$(dirname "${LOGS_DIR}")" "$(basename "${LOGS_DIR}")" 2>/dev/null
    log_info "Log archive created: ${archive_path}"
    echo "${archive_path}"
}

main() {
    log_info "Starting log collection for deer-flow smoke test..."
    log_info "Output directory: ${LOGS_DIR}"

    collect_system_info
    collect_docker_logs
    collect_local_process_logs

    local archive
    archive=$(create_archive)

    log_info "Log collection complete."
    log_info "Archive: ${archive}"
    log_info "Raw logs: ${LOGS_DIR}"
}

main "$@"
