#!/bin/bash
# check_performance.sh - Basic performance checks for deer-flow services
# Measures response times and checks against acceptable thresholds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Default thresholds (milliseconds)
API_RESPONSE_THRESHOLD=${API_RESPONSE_THRESHOLD:-2000}
FRONTEND_RESPONSE_THRESHOLD=${FRONTEND_RESPONSE_THRESHOLD:-3000}
HEALTH_RESPONSE_THRESHOLD=${HEALTH_RESPONSE_THRESHOLD:-500}

# Service URLs
BACKEND_URL=${BACKEND_URL:-"http://localhost:8000"}
FRONTEND_URL=${FRONTEND_URL:-"http://localhost:3000"}

PASS=0
FAIL=0
WARN=0

log_info() { echo "[INFO]  $*"; }
log_pass() { echo "[PASS]  $*"; ((PASS++)) || true; }
log_fail() { echo "[FAIL]  $*"; ((FAIL++)) || true; }
log_warn() { echo "[WARN]  $*"; ((WARN++)) || true; }

# Measure response time in milliseconds for a given URL
measure_response_time() {
    local url="$1"
    local label="$2"
    local threshold="$3"

    local result
    result=$(curl -o /dev/null -s -w "%{http_code} %{time_total}" \
        --connect-timeout 5 \
        --max-time 10 \
        "$url" 2>/dev/null) || {
        log_fail "${label}: could not connect to ${url}"
        return 1
    }

    local http_code time_total
    http_code=$(echo "$result" | awk '{print $1}')
    time_total=$(echo "$result" | awk '{print $2}')

    # Convert seconds to milliseconds
    local time_ms
    time_ms=$(echo "$time_total * 1000" | bc 2>/dev/null | cut -d'.' -f1)
    time_ms=${time_ms:-9999}

    if [[ "$http_code" -lt 200 || "$http_code" -ge 500 ]]; then
        log_fail "${label}: HTTP ${http_code} (${time_ms}ms)"
        return 1
    fi

    if [[ "$time_ms" -le "$threshold" ]]; then
        log_pass "${label}: ${time_ms}ms (threshold: ${threshold}ms, HTTP ${http_code})"
    elif [[ "$time_ms" -le $((threshold * 2)) ]]; then
        log_warn "${label}: ${time_ms}ms exceeds threshold of ${threshold}ms (HTTP ${http_code})"
    else
        log_fail "${label}: ${time_ms}ms far exceeds threshold of ${threshold}ms (HTTP ${http_code})"
        return 1
    fi
}

# Run multiple samples and report average
measure_avg_response_time() {
    local url="$1"
    local label="$2"
    local threshold="$3"
    local samples=${4:-3}

    local total=0
    local count=0

    for ((i=1; i<=samples; i++)); do
        local result
        result=$(curl -o /dev/null -s -w "%{time_total}" \
            --connect-timeout 5 --max-time 10 "$url" 2>/dev/null) || continue
        local ms
        ms=$(echo "$result * 1000" | bc 2>/dev/null | cut -d'.' -f1)
        total=$((total + ms))
        ((count++)) || true
    done

    if [[ "$count" -eq 0 ]]; then
        log_fail "${label} avg (${samples} samples): no successful requests"
        return 1
    fi

    local avg=$((total / count))
    if [[ "$avg" -le "$threshold" ]]; then
        log_pass "${label} avg (${count}/${samples} samples): ${avg}ms"
    else
        log_warn "${label} avg (${count}/${samples} samples): ${avg}ms exceeds ${threshold}ms"
    fi
}

echo "======================================"
echo " deer-flow Performance Checks"
echo "======================================"
echo "Backend:  ${BACKEND_URL}"
echo "Frontend: ${FRONTEND_URL}"
echo "--------------------------------------"

# Health endpoint — should be very fast
measure_response_time "${BACKEND_URL}/health" \
    "Backend /health" "${HEALTH_RESPONSE_THRESHOLD}"

# API root
measure_response_time "${BACKEND_URL}/api/v1" \
    "Backend /api/v1" "${API_RESPONSE_THRESHOLD}"

# Frontend
measure_response_time "${FRONTEND_URL}" \
    "Frontend /" "${FRONTEND_RESPONSE_THRESHOLD}"

# Average response time over multiple samples for health
measure_avg_response_time "${BACKEND_URL}/health" \
    "Backend /health" "${HEALTH_RESPONSE_THRESHOLD}" 5

echo "--------------------------------------"
echo "Results: PASS=${PASS}  WARN=${WARN}  FAIL=${FAIL}"
echo "======================================"

[[ "$FAIL" -eq 0 ]]
