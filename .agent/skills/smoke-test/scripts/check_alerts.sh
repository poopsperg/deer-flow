#!/bin/bash
# check_alerts.sh - Verify alerting rules and notification channels are properly configured
# Part of the deer-flow smoke test suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load common utilities if available
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
  source "${SCRIPT_DIR}/common.sh"
fi

# Configuration
ALERT_MANAGER_URL="${ALERT_MANAGER_URL:-http://localhost:9093}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3001}"
TIMEOUT="${CHECK_TIMEOUT:-10}"
PASS=0
FAIL=0
WARN=0

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_pass()  { echo "[PASS]  $(date '+%H:%M:%S') $*"; ((PASS++)); }
log_fail()  { echo "[FAIL]  $(date '+%H:%M:%S') $*"; ((FAIL++)); }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*"; ((WARN++)); }

# Check if AlertManager is reachable
check_alertmanager_health() {
  log_info "Checking AlertManager health..."
  if curl -sf --max-time "${TIMEOUT}" "${ALERT_MANAGER_URL}/-/healthy" &>/dev/null; then
    log_pass "AlertManager is healthy at ${ALERT_MANAGER_URL}"
  else
    log_warn "AlertManager not reachable at ${ALERT_MANAGER_URL} (may not be configured)"
  fi
}

# Check Prometheus alerting rules are loaded
check_prometheus_rules() {
  log_info "Checking Prometheus alerting rules..."
  local response
  response=$(curl -sf --max-time "${TIMEOUT}" "${PROMETHEUS_URL}/api/v1/rules" 2>/dev/null || echo "")

  if [[ -z "${response}" ]]; then
    log_warn "Could not reach Prometheus at ${PROMETHEUS_URL}"
    return
  fi

  local rule_count
  rule_count=$(echo "${response}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data.get('data', {}).get('groups', [])
total = sum(len(g.get('rules', [])) for g in groups)
print(total)
" 2>/dev/null || echo "0")

  if [[ "${rule_count}" -gt 0 ]]; then
    log_pass "Prometheus has ${rule_count} alerting rule(s) loaded"
  else
    log_warn "No alerting rules found in Prometheus"
  fi
}

# Check for any currently firing alerts
check_firing_alerts() {
  log_info "Checking for firing alerts..."
  local response
  response=$(curl -sf --max-time "${TIMEOUT}" "${PROMETHEUS_URL}/api/v1/alerts" 2>/dev/null || echo "")

  if [[ -z "${response}" ]]; then
    log_warn "Could not query alerts from Prometheus"
    return
  fi

  local firing_count
  firing_count=$(echo "${response}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
alerts = data.get('data', {}).get('alerts', [])
firing = [a for a in alerts if a.get('state') == 'firing']
print(len(firing))
" 2>/dev/null || echo "0")

  if [[ "${firing_count}" -eq 0 ]]; then
    log_pass "No firing alerts detected"
  else
    log_fail "${firing_count} alert(s) currently firing — investigate before proceeding"
  fi
}

# Check Grafana alert notification channels
check_grafana_alerts() {
  log_info "Checking Grafana alert configuration..."
  local GRAFANA_USER="${GRAFANA_USER:-admin}"
  local GRAFANA_PASS="${GRAFANA_PASS:-admin}"

  local response
  response=$(curl -sf --max-time "${TIMEOUT}" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    "${GRAFANA_URL}/api/alert-notifications" 2>/dev/null || echo "")

  if [[ -z "${response}" ]]; then
    log_warn "Could not reach Grafana at ${GRAFANA_URL}"
    return
  fi

  local channel_count
  channel_count=$(echo "${response}" | python3 -c "
import sys, json
channels = json.load(sys.stdin)
print(len(channels) if isinstance(channels, list) else 0)
" 2>/dev/null || echo "0")

  if [[ "${channel_count}" -gt 0 ]]; then
    log_pass "Grafana has ${channel_count} notification channel(s) configured"
  else
    log_warn "No Grafana notification channels configured"
  fi
}

# Summary
print_summary() {
  echo ""
  echo "======================================="
  echo " Alert Check Summary"
  echo "======================================="
  echo " PASSED : ${PASS}"
  echo " FAILED : ${FAIL}"
  echo " WARNINGS: ${WARN}"
  echo "======================================="

  if [[ "${FAIL}" -gt 0 ]]; then
    echo " Result: FAILED"
    exit 1
  elif [[ "${WARN}" -gt 0 ]]; then
    echo " Result: PASSED WITH WARNINGS"
    exit 0
  else
    echo " Result: PASSED"
    exit 0
  fi
}

main() {
  log_info "Starting alert checks..."
  check_alertmanager_health
  check_prometheus_rules
  check_firing_alerts
  check_grafana_alerts
  print_summary
}

main "$@"
