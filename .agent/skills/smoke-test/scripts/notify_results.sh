#!/bin/bash
# notify_results.sh - Send smoke test results to configured notification channels
# Supports Slack webhooks, email (via sendmail), and file-based notifications

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${REPORT_DIR:-/tmp/smoke-test-reports}"
NOTIFY_SLACK="${NOTIFY_SLACK:-false}"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-false}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-}"
TEST_ENV="${TEST_ENV:-local}"
CI_BUILD_URL="${CI_BUILD_URL:-}"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "[$(date '+%H:%M:%S')] $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err() { echo -e "${RED}[ERR]${NC} $*" >&2; }

# Load the latest report summary if available
load_report_summary() {
  local summary_file="${REPORT_DIR}/summary.txt"
  if [[ -f "$summary_file" ]]; then
    cat "$summary_file"
  else
    echo "No summary report found at ${summary_file}"
  fi
}

# Determine overall status from exit code or summary file
get_overall_status() {
  local status_file="${REPORT_DIR}/status.txt"
  if [[ -f "$status_file" ]]; then
    cat "$status_file"
  else
    echo "UNKNOWN"
  fi
}

# Build Slack message payload
build_slack_payload() {
  local status="$1"
  local summary="$2"
  local color
  local icon

  case "$status" in
    PASS|pass|0) color="good"; icon=":white_check_mark:"; status="PASSED" ;;
    FAIL|fail|1) color="danger"; icon=":x:"; status="FAILED" ;;
    *)           color="warning"; icon=":warning:"; status="UNKNOWN" ;;
  esac

  local build_link=""
  if [[ -n "$CI_BUILD_URL" ]]; then
    build_link="\n<${CI_BUILD_URL}|View Build>"
  fi

  cat <<EOF
{
  "attachments": [
    {
      "color": "${color}",
      "title": "${icon} DeerFlow Smoke Test — ${status}",
      "text": "*Environment:* ${TEST_ENV}\n*Time:* $(date '+%Y-%m-%d %H:%M:%S %Z')${build_link}",
      "fields": [
        {
          "title": "Summary",
          "value": "\`\`\`${summary}\`\`\`",
          "short": false
        }
      ],
      "footer": "deer-flow smoke-test",
      "ts": $(date +%s)
    }
  ]
}
EOF
}

# Send notification to Slack
notify_slack() {
  local status="$1"
  local summary="$2"

  if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
    log_warn "SLACK_WEBHOOK_URL not set, skipping Slack notification"
    return 0
  fi

  log "Sending Slack notification..."
  local payload
  payload="$(build_slack_payload "$status" "$summary")"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H 'Content-type: application/json' \
    --data "$payload" \
    "$SLACK_WEBHOOK_URL")

  if [[ "$http_code" == "200" ]]; then
    log_ok "Slack notification sent (HTTP ${http_code})"
  else
    log_err "Slack notification failed (HTTP ${http_code})"
    return 1
  fi
}

# Send notification via email
notify_email() {
  local status="$1"
  local summary="$2"

  if [[ -z "$EMAIL_RECIPIENTS" ]]; then
    log_warn "EMAIL_RECIPIENTS not set, skipping email notification"
    return 0
  fi

  if ! command -v sendmail &>/dev/null; then
    log_warn "sendmail not available, skipping email notification"
    return 0
  fi

  log "Sending email notification to: ${EMAIL_RECIPIENTS}"
  local subject="[DeerFlow] Smoke Test ${status} — ${TEST_ENV} — $(date '+%Y-%m-%d')"

  {
    echo "To: ${EMAIL_RECIPIENTS}"
    echo "Subject: ${subject}"
    echo "Content-Type: text/plain"
    echo ""
    echo "DeerFlow Smoke Test Result: ${status}"
    echo "Environment: ${TEST_ENV}"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    [[ -n "$CI_BUILD_URL" ]] && echo "Build: ${CI_BUILD_URL}"
    echo ""
    echo "--- Summary ---"
    echo "$summary"
  } | sendmail -t

  log_ok "Email notification sent"
}

# Write result to a file for CI artifact pickup
notify_file() {
  local status="$1"
  local output_file="${REPORT_DIR}/notification_sent.txt"
  mkdir -p "$REPORT_DIR"
  echo "status=${status}" > "$output_file"
  echo "env=${TEST_ENV}" >> "$output_file"
  echo "timestamp=$(date '+%Y-%m-%dT%H:%M:%SZ')" >> "$output_file"
  log_ok "Notification record written to ${output_file}"
}

main() {
  log "=== DeerFlow Smoke Test Notifier ==="

  local status
  status="$(get_overall_status)"
  local summary
  summary="$(load_report_summary)"

  log "Overall status: ${status}"

  local errors=0

  if [[ "$NOTIFY_SLACK" == "true" ]]; then
    notify_slack "$status" "$summary" || ((errors++))
  fi

  if [[ "$NOTIFY_EMAIL" == "true" ]]; then
    notify_email "$status" "$summary" || ((errors++))
  fi

  notify_file "$status"

  if [[ $errors -gt 0 ]]; then
    log_err "${errors} notification channel(s) failed"
    exit 1
  fi

  log_ok "All notifications dispatched successfully"
}

main "$@"
