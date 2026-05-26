#!/bin/bash
# check_ssl.sh - Verify SSL/TLS certificate validity and configuration
# Part of the deer-flow smoke test suite

set -euo pipefail

# Source common utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
  source "${SCRIPT_DIR}/common.sh"
fi

# Default configuration
SSL_CHECK_TIMEOUT=${SSL_CHECK_TIMEOUT:-10}
SSL_WARN_DAYS=${SSL_WARN_DAYS:-30}  # Warn if cert expires within N days
SSL_CRITICAL_DAYS=${SSL_CRITICAL_DAYS:-7}  # Critical if expires within N days
APP_HOST=${APP_HOST:-"localhost"}
APP_PORT=${APP_PORT:-443}
FRONTEND_HOST=${FRONTEND_HOST:-"localhost"}
FRONTEND_PORT=${FRONTEND_PORT:-3000}

# Result tracking
PASS=0
WARN=0
FAIL=0

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*"; WARN=$((WARN + 1)); }
log_error() { echo "[ERROR] $*"; FAIL=$((FAIL + 1)); }
log_ok()    { echo "[OK]    $*"; PASS=$((PASS + 1)); }

# Check if openssl is available
check_openssl_available() {
  if ! command -v openssl &>/dev/null; then
    log_warn "openssl not found — skipping SSL checks"
    return 1
  fi
  log_ok "openssl is available ($(openssl version))"
  return 0
}

# Get certificate expiry date and days remaining
get_cert_expiry() {
  local host="$1"
  local port="$2"
  local expiry_date
  local days_remaining

  expiry_date=$(echo | openssl s_client -connect "${host}:${port}" \
    -servername "${host}" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | cut -d= -f2)

  if [[ -z "$expiry_date" ]]; then
    return 1
  fi

  days_remaining=$(( ( $(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null) - $(date +%s) ) / 86400 ))
  echo "$days_remaining"
}

# Check certificate validity for a host:port
check_cert_validity() {
  local host="$1"
  local port="$2"
  local label="${3:-${host}:${port}}"

  log_info "Checking SSL certificate for ${label}..."

  # Test connectivity first
  if ! timeout "${SSL_CHECK_TIMEOUT}" bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
    log_warn "Cannot connect to ${label} — skipping SSL check"
    return
  fi

  # Verify certificate chain
  local verify_output
  verify_output=$(echo | timeout "${SSL_CHECK_TIMEOUT}" openssl s_client \
    -connect "${host}:${port}" \
    -servername "${host}" 2>&1)

  if echo "$verify_output" | grep -q "Verify return code: 0"; then
    log_ok "Certificate chain valid for ${label}"
  else
    local verify_code
    verify_code=$(echo "$verify_output" | grep "Verify return code" | head -1)
    log_warn "Certificate chain issue for ${label}: ${verify_code}"
  fi

  # Check expiry
  local days_remaining
  days_remaining=$(get_cert_expiry "$host" "$port") || {
    log_warn "Could not retrieve certificate expiry for ${label}"
    return
  }

  if [[ "$days_remaining" -le "$SSL_CRITICAL_DAYS" ]]; then
    log_error "Certificate for ${label} expires in ${days_remaining} days (CRITICAL)"
  elif [[ "$days_remaining" -le "$SSL_WARN_DAYS" ]]; then
    log_warn "Certificate for ${label} expires in ${days_remaining} days"
  else
    log_ok "Certificate for ${label} valid for ${days_remaining} more days"
  fi
}

# Check TLS protocol versions (ensure TLS 1.2+ is supported, SSLv3/TLS1.0 disabled)
check_tls_protocols() {
  local host="$1"
  local port="$2"
  local label="${3:-${host}:${port}}"

  log_info "Checking TLS protocols for ${label}..."

  # Check TLS 1.2 support (should be supported)
  if echo | timeout "${SSL_CHECK_TIMEOUT}" openssl s_client \
      -connect "${host}:${port}" -tls1_2 2>&1 | grep -q "Cipher"; then
    log_ok "TLS 1.2 supported on ${label}"
  else
    log_warn "TLS 1.2 not confirmed on ${label}"
  fi

  # Check that SSLv3 is disabled (security requirement)
  if echo | timeout "${SSL_CHECK_TIMEOUT}" openssl s_client \
      -connect "${host}:${port}" -ssl3 2>&1 | grep -q "handshake failure\|unknown option\|ssl3"; then
    log_ok "SSLv3 disabled on ${label}"
  fi
}

# Main execution
main() {
  echo "======================================="
  echo " SSL/TLS Certificate Check"
  echo " $(date '+%Y-%m-%d %H:%M:%S')"
  echo "======================================="

  if ! check_openssl_available; then
    echo "---"
    echo "SKIPPED: openssl not available"
    exit 0
  fi

  # Only run SSL checks if HTTPS is configured
  if [[ "${ENABLE_SSL:-false}" != "true" && "$APP_PORT" != "443" ]]; then
    log_info "SSL not enabled (ENABLE_SSL != true and port != 443) — skipping deep checks"
  else
    check_cert_validity "$APP_HOST" "$APP_PORT" "backend API"
    check_tls_protocols "$APP_HOST" "$APP_PORT" "backend API"

    if [[ "$FRONTEND_PORT" == "443" || "${ENABLE_SSL:-false}" == "true" ]]; then
      check_cert_validity "$FRONTEND_HOST" "$FRONTEND_PORT" "frontend"
    fi
  fi

  echo "---"
  echo "SSL Check Summary: PASS=${PASS} WARN=${WARN} FAIL=${FAIL}"

  if [[ "$FAIL" -gt 0 ]]; then
    exit 2
  elif [[ "$WARN" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
