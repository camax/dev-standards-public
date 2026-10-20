#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_LOG="$SCRIPT_DIR/../hooks/lib/log.sh"

if [ ! -f "$LIB_LOG" ]; then
  echo "Error: $LIB_LOG not found" >&2
  exit 1
fi

# 本番ログへの汚染を防ぐため、テスト専用の一時ディレクトリを HOME に設定
TMP_DIR="$(mktemp -d /tmp/test-log-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="$TMP_DIR"

. "$LIB_LOG"

export HARNESS_HOST="TestHost-Unit"
export HARNESS_AGENT="UnitTestAgent"

log_record "test-hook" "unit_test" "PASS" "Testing host field logging"

LOG_FILE="$HOME/.harness-log/$(date +'%Y-%m').jsonl"
LAST_LINE=$(tail -n 1 "$LOG_FILE")

echo "Last log line: $LAST_LINE"

# Verify JSON parsing and host field
echo "$LAST_LINE" | jq -e '.host == "TestHost-Unit"' >/dev/null
echo "$LAST_LINE" | jq -e '.agent == "UnitTestAgent"' >/dev/null
echo "$LAST_LINE" | jq -e '.check == "unit_test"' >/dev/null

echo "All tests passed!"
