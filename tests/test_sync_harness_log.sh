#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/../scripts/sync_harness_log.sh"

TMP_DIR="$(mktemp -d /tmp/test-sync-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="$TMP_DIR"

# Mock Obsidian AI_Config
mkdir -p "$TMP_DIR/vault/AI_Config"

# Mock Harness Logs
MOCK_LOG_DIR="$TMP_DIR/mock_logs"
mkdir -p "$MOCK_LOG_DIR"
echo '{"ts":"2026-09-11T00:00:00Z","repo":"test","hook":"pre-commit","check":"harness_engineering","result":"PASS","agent":"test","detail":"","host":"MBA 2026"}' > "$MOCK_LOG_DIR/2026-09.jsonl"

# Run sync script
export HARNESS_HOST="MBA 2026"
export OBSIDIAN_VAULT="$TMP_DIR/vault"
export HARNESS_LOG_DIR="$MOCK_LOG_DIR"

OUTPUT=$(bash "$SYNC_SCRIPT")
echo "$OUTPUT"

# Verify destination file
OUT_FILE="$TMP_DIR/vault/AI_Config/harness-logs/MBA_2026.jsonl"
if [ ! -f "$OUT_FILE" ]; then
  echo "FAIL: $OUT_FILE not found" >&2
  exit 1
fi

diff -u "$MOCK_LOG_DIR/2026-09.jsonl" "$OUT_FILE"
jq . "$OUT_FILE" >/dev/null

echo "test_sync_harness_log: PASSED"
