#!/bin/bash
# check_network.sh - Verify network connectivity and DNS resolution for deer-flow services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/smoke-test/network_check.log}"
PASS=0
FAIL=0
WARN=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pass() { log "[PASS] $*"; ((PASS++)); }
fail() { log "[FAIL] $*"; ((FAIL++)); }
warn() { log "[WARN] $*"; ((WARN++)); }

# Default hosts/ports to check
BACKEND_HOST="${BACKEND_HOST:-localhost}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_HOST="${FRONTEND_HOST:-localhost}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
EXTERNAL_DNS_TARGET="${EXTERNAL_DNS_TARGET:-8.8.8.8}"

check_dns_resolution() {
    log "--- DNS Resolution Checks ---"

    if getent hosts "$BACKEND_HOST" &>/dev/null || [[ "$BACKEND_HOST" == "localhost" ]]; then
        pass "DNS resolution for backend host: $BACKEND_HOST"
    else
        fail "Cannot resolve backend host: $BACKEND_HOST"
    fi

    if getent hosts "$FRONTEND_HOST" &>/dev/null || [[ "$FRONTEND_HOST" == "localhost" ]]; then
        pass "DNS resolution for frontend host: $FRONTEND_HOST"
    else
        fail "Cannot resolve frontend host: $FRONTEND_HOST"
    fi
}

check_port_connectivity() {
    log "--- Port Connectivity Checks ---"

    if timeout 5 bash -c "</dev/tcp/$BACKEND_HOST/$BACKEND_PORT" 2>/dev/null; then
        pass "Backend port reachable: $BACKEND_HOST:$BACKEND_PORT"
    else
        fail "Backend port not reachable: $BACKEND_HOST:$BACKEND_PORT"
    fi

    if timeout 5 bash -c "</dev/tcp/$FRONTEND_HOST/$FRONTEND_PORT" 2>/dev/null; then
        pass "Frontend port reachable: $FRONTEND_HOST:$FRONTEND_PORT"
    else
        warn "Frontend port not reachable: $FRONTEND_HOST:$FRONTEND_PORT (may not be running)"
    fi
}

check_external_connectivity() {
    log "--- External Connectivity Checks ---"

    if ping -c 1 -W 3 "$EXTERNAL_DNS_TARGET" &>/dev/null; then
        pass "External network reachable (ping $EXTERNAL_DNS_TARGET)"
    else
        warn "External network unreachable — LLM API calls may fail"
    fi

    # Check HTTPS to common LLM endpoints if curl is available
    if command -v curl &>/dev/null; then
        local endpoints=("https://api.openai.com" "https://api.anthropic.com")
        for ep in "${endpoints[@]}"; do
            if curl --silent --max-time 5 --head "$ep" &>/dev/null; then
                pass "Reachable: $ep"
            else
                warn "Not reachable: $ep (check firewall/proxy if this LLM is required)"
            fi
        done
    else
        warn "curl not found — skipping HTTPS endpoint checks"
    fi
}

check_docker_network() {
    log "--- Docker Network Checks ---"

    if ! command -v docker &>/dev/null; then
        warn "Docker not installed — skipping Docker network checks"
        return
    fi

    local network_name="${DOCKER_NETWORK:-deer-flow_default}"
    if docker network inspect "$network_name" &>/dev/null; then
        pass "Docker network exists: $network_name"
    else
        warn "Docker network not found: $network_name (expected if using local dev mode)"
    fi
}

print_summary() {
    log ""
    log "============================="
    log " Network Check Summary"
    log "============================="
    log " PASS : $PASS"
    log " WARN : $WARN"
    log " FAIL : $FAIL"
    log "============================="

    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}Network checks completed with $FAIL failure(s).${NC}"
        exit 1
    elif [[ $WARN -gt 0 ]]; then
        echo -e "${YELLOW}Network checks completed with $WARN warning(s).${NC}"
        exit 0
    else
        echo -e "${GREEN}All network checks passed.${NC}"
        exit 0
    fi
}

main() {
    log "Starting network checks for deer-flow..."
    check_dns_resolution
    check_port_connectivity
    check_external_connectivity
    check_docker_network
    print_summary
}

main "$@"
