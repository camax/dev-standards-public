#!/usr/bin/env bash
set -euo pipefail

HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/hooks/pre-commit}"
CASE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-pre-commit.XXXXXX")
trap 'rm -r -- "$CASE_ROOT"' EXIT
mkdir -p "$CASE_ROOT/home"

check_case() {
  local label="$1" path="$2" expected="$3" repo="$CASE_ROOT/$1" output status
  git init -q "$repo"
  mkdir -p "$(dirname "$repo/$path")"
  printf '/* generated fixture */\n' > "$repo/$path"
  git -C "$repo" add -- "$path"

  status=0
  output=$(cd "$repo" && HOME="$CASE_ROOT/home" bash "$HOOK" 2>&1) || status=$?
  printf '%s\n' "[$label]" "$output" "exit=$status"
  [ "$status" -eq "$expected" ] || exit 1
}

check_case local_rest_api .obsidian/plugins/obsidian-local-rest-api/main.js 0
check_case vendor_dir vendor/library/main.js 0
check_case normal_source src/main.js 1
check_case other_plugin .obsidian/plugins/my-plugin/main.js 1
