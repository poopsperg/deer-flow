#!/bin/bash
# rollback.sh - Rollback to previous deployment state if smoke tests fail
# Part of the deer-flow smoke-test skill

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LOG_FILE="${PROJECT_ROOT}/.agent/logs/rollback.log"
BACKUP_DIR="${PROJECT_ROOT}/.agent/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info()    { log "INFO " "${BLUE}$*${NC}"; }
warn()    { log "WARN " "${YELLOW}$*${NC}"; }
error()   { log "ERROR" "${RED}$*${NC}"; }
success() { log "OK   " "${GREEN}$*${NC}"; }

mkdir -p "$(dirname "${LOG_FILE}")"

DEPLOY_MODE="${DEPLOY_MODE:-local}"  # local | docker
ROLLBACK_TARGET="${ROLLBACK_TARGET:-latest}"  # latest | <backup-id>

list_backups() {
    info "Available backups in ${BACKUP_DIR}:"
    if [[ ! -d "${BACKUP_DIR}" ]] || [[ -z "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]]; then
        warn "No backups found."
        return 1
    fi
    ls -lt "${BACKUP_DIR}" | grep '^d' | awk '{print $NF}'
}

resolve_backup_path() {
    if [[ "${ROLLBACK_TARGET}" == "latest" ]]; then
        local latest
        latest=$(ls -td "${BACKUP_DIR}"/*/  2>/dev/null | head -1)
        if [[ -z "${latest}" ]]; then
            error "No backup found to rollback to."
            return 1
        fi
        echo "${latest%/}"
    else
        local target_path="${BACKUP_DIR}/${ROLLBACK_TARGET}"
        if [[ ! -d "${target_path}" ]]; then
            error "Backup '${ROLLBACK_TARGET}' not found in ${BACKUP_DIR}."
            return 1
        fi
        echo "${target_path}"
    fi
}

rollback_local() {
    info "Starting local rollback..."

    local backup_path
    backup_path=$(resolve_backup_path) || return 1
    info "Rolling back from backup: ${backup_path}"

    # Stop running processes
    if pgrep -f "uvicorn" > /dev/null 2>&1; then
        warn "Stopping backend server..."
        pkill -f "uvicorn" || true
        sleep 2
    fi

    # Restore .env if backed up
    if [[ -f "${backup_path}/.env" ]]; then
        cp "${backup_path}/.env" "${PROJECT_ROOT}/.env"
        success "Restored .env from backup."
    else
        warn ".env not found in backup, skipping."
    fi

    # Restore conf.yaml if backed up
    if [[ -f "${backup_path}/conf.yaml" ]]; then
        cp "${backup_path}/conf.yaml" "${PROJECT_ROOT}/conf.yaml"
        success "Restored conf.yaml from backup."
    fi

    success "Local rollback complete."
}

rollback_docker() {
    info "Starting Docker rollback..."

    local backup_path
    backup_path=$(resolve_backup_path) || return 1
    info "Rolling back from backup: ${backup_path}"

    # Bring down current containers
    if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
        info "Stopping current Docker containers..."
        docker compose -f "${PROJECT_ROOT}/docker-compose.yml" down --remove-orphans || true
    fi

    # Restore docker-compose override if present
    if [[ -f "${backup_path}/docker-compose.override.yml" ]]; then
        cp "${backup_path}/docker-compose.override.yml" "${PROJECT_ROOT}/docker-compose.override.yml"
        success "Restored docker-compose.override.yml from backup."
    fi

    # Restore .env
    if [[ -f "${backup_path}/.env" ]]; then
        cp "${backup_path}/.env" "${PROJECT_ROOT}/.env"
        success "Restored .env from backup."
    fi

    # Restart containers with restored config
    info "Restarting Docker containers..."
    docker compose -f "${PROJECT_ROOT}/docker-compose.yml" up -d

    success "Docker rollback complete."
}

main() {
    info "=== Rollback Script Started ==="
    info "Deploy mode : ${DEPLOY_MODE}"
    info "Rollback target: ${ROLLBACK_TARGET}"

    case "${DEPLOY_MODE}" in
        local)
            rollback_local
            ;;
        docker)
            rollback_docker
            ;;
        *)
            error "Unknown DEPLOY_MODE '${DEPLOY_MODE}'. Use 'local' or 'docker'."
            exit 1
            ;;
    esac

    success "=== Rollback Completed Successfully ==="
}

main "$@"
