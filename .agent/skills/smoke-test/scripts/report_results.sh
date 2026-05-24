#!/bin/bash
# report_results.sh - Aggregate and format smoke test results into a summary report
# Usage: ./report_results.sh [--output <file>] [--format <text|json|markdown>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTPUT_FORMAT="text"
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --format)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Ensure reports directory exists
mkdir -p "$REPORT_DIR"

# Collect result files written by individual check scripts
RESULT_FILES=("$REPORT_DIR"/*.result 2>/dev/null || true)

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -a RESULTS=()

for result_file in "${RESULT_FILES[@]}"; do
  [[ -f "$result_file" ]] || continue
  while IFS='|' read -r check_name status message; do
    RESULTS+=("${check_name}|${status}|${message}")
    case "$status" in
      PASS) ((PASS_COUNT++)) ;;
      FAIL) ((FAIL_COUNT++)) ;;
      SKIP) ((SKIP_COUNT++)) ;;
    esac
  done < "$result_file"
done

TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
OVERALL="PASS"
[[ $FAIL_COUNT -gt 0 ]] && OVERALL="FAIL"

generate_text_report() {
  echo "========================================"
  echo "  DeerFlow Smoke Test Report"
  echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "========================================"
  echo ""
  printf "%-40s %-8s %s\n" "Check" "Status" "Message"
  printf "%-40s %-8s %s\n" "-----" "------" "-------"
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r name status msg <<< "$entry"
    printf "%-40s %-8s %s\n" "$name" "$status" "$msg"
  done
  echo ""
  echo "----------------------------------------"
  echo "  Total:  $TOTAL"
  echo "  Passed: $PASS_COUNT"
  echo "  Failed: $FAIL_COUNT"
  echo "  Skipped: $SKIP_COUNT"
  echo "  Overall: $OVERALL"
  echo "========================================"
}

generate_json_report() {
  echo "{"
  echo "  \"generated_at\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
  echo "  \"overall\": \"$OVERALL\","
  echo "  \"summary\": { \"total\": $TOTAL, \"passed\": $PASS_COUNT, \"failed\": $FAIL_COUNT, \"skipped\": $SKIP_COUNT },"
  echo "  \"checks\": ["
  local first=true
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r name status msg <<< "$entry"
    [[ "$first" == true ]] && first=false || echo ","
    printf '    { "name": "%s", "status": "%s", "message": "%s" }' "$name" "$status" "$msg"
  done
  echo ""
  echo "  ]"
  echo "}"
}

generate_markdown_report() {
  echo "# DeerFlow Smoke Test Report"
  echo ""
  echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  "
  echo "**Overall:** $OVERALL"
  echo ""
  echo "## Summary"
  echo "| Metric | Count |"
  echo "|--------|-------|"
  echo "| Total  | $TOTAL |"
  echo "| Passed | $PASS_COUNT |"
  echo "| Failed | $FAIL_COUNT |"
  echo "| Skipped | $SKIP_COUNT |"
  echo ""
  echo "## Results"
  echo "| Check | Status | Message |"
  echo "|-------|--------|---------|"
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r name status msg <<< "$entry"
    echo "| $name | $status | $msg |"
  done
}

# Generate the report
case "$OUTPUT_FORMAT" in
  json)     REPORT=$(generate_json_report) ;;
  markdown) REPORT=$(generate_markdown_report) ;;
  *)        REPORT=$(generate_text_report) ;;
esac

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$REPORT" > "$OUTPUT_FILE"
  echo "Report written to: $OUTPUT_FILE"
else
  DEFAULT_FILE="$REPORT_DIR/smoke_test_${TIMESTAMP}.${OUTPUT_FORMAT}"
  echo "$REPORT" > "$DEFAULT_FILE"
  echo "$REPORT"
  echo ""
  echo "Report saved to: $DEFAULT_FILE"
fi

# Exit with non-zero if any checks failed
[[ $FAIL_COUNT -eq 0 ]]
