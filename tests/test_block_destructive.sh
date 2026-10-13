#!/usr/bin/env bash
# .claude/hooks/block-destructive.sh のテスト。
# フックには PreToolUse の JSON（文字列）を渡すだけで、検査対象のコマンドは
# 一切実行しない（rm 等を実際に走らせて検証することはしない）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/block-destructive.sh"
SETTINGS="$SCRIPT_DIR/../.claude/settings.json"

[ -x "$HOOK" ] || { echo "Error: $HOOK が無いか実行権限がない" >&2; exit 1; }

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
ng() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }

# フックに生の stdin を渡し、OUT と RC を設定する
run_raw() {
  RC=0
  OUT="$(printf '%s' "$1" | "$HOOK")" || RC=$?
}

run_cmd() {
  run_raw "$(jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}')"
}

is_deny_output() {
  printf '%s' "$OUT" | jq -e '
    .hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == "deny"
    and (.hookSpecificOutput.permissionDecisionReason | type == "string" and length > 0)
  ' >/dev/null 2>&1
}

expect_deny() {
  run_cmd "$1"
  if [ "$RC" -eq 0 ] && is_deny_output; then
    ok "DENY  | $1"
    echo "        $(printf '%s' "$OUT" | jq -c .)"
  else
    ng "DENY 期待だが拒否されなかった | $1 | rc=$RC out=$OUT"
  fi
}

expect_allow() {
  run_cmd "$1"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    ok "ALLOW | $1 | (出力なし, exit 0)"
  else
    ng "ALLOW 期待だが出力あり | $1 | rc=$RC out=$OUT"
  fi
}

echo "=== rm -rf / 広範な rm -r ==="
expect_deny 'rm -rf /'
expect_deny 'rm -rf ./build'
expect_deny 'rm -fr ~/Desktop'
expect_deny 'rm -r -f ../other'
expect_deny 'rm -Rf node_modules'
expect_deny 'rm --recursive --force dist'
expect_deny 'sudo rm -rf /var/tmp/x'
expect_deny '/bin/rm -rf build'
expect_deny '\rm -rf build'
expect_deny 'ls && rm -rf build'
expect_deny 'find . -name "*.tmp" | xargs rm -rf'
expect_deny "bash -c 'rm -rf build'"
expect_deny 'rm -r /tmp/foo'
expect_deny 'rm -r ../sibling'
expect_deny 'rm -r ~'
expect_deny 'rm -r "$HOME/x"'
expect_deny 'rm -r *'

echo "=== git push --force / -f ==="
expect_deny 'git push --force'
expect_deny 'git push -f origin main'
expect_deny 'git push origin main --force'
expect_deny 'git push -uf origin main'
expect_deny 'git push --force-with-lease origin main'
expect_deny 'git push origin +main'
expect_deny 'git -C ../repo push -f'

echo "=== git reset --hard ==="
expect_deny 'git reset --hard'
expect_deny 'git reset --hard HEAD~1'
expect_deny 'git status; git reset --hard origin/main'

echo "=== git add . / git commit -am ==="
expect_deny 'git add .'
expect_deny 'git add ./'
expect_deny 'git add -A'
expect_deny 'git add --all'
expect_deny 'git add -u'
expect_deny 'git add *.md'
expect_deny 'git commit -am "fix: x"'
expect_deny 'git commit -a -m "fix: x"'
expect_deny 'git commit --all -m "fix: x"'
expect_deny "git commit -a -F - <<'EOF'
fix: x
EOF"
expect_deny 'cd /tmp/repo && git add . && git commit -m "x"'

echo "=== 安全なコマンド（何も出力せず exit 0） ==="
expect_allow 'git add rules/foo.md'
expect_allow 'git add rules/foo.md tests/test_foo.sh'
expect_allow 'git commit -m "feat: add hook"'
expect_allow "git commit -F - <<'EOF'
docs: update readme

Co-Authored-By: someone
EOF"
expect_allow 'git diff --cached --stat'
expect_allow 'git log --oneline -1'
expect_allow 'git push origin main'
expect_allow 'git push -u origin feature/x'
expect_allow 'git reset --soft HEAD~1'
expect_allow 'git reset HEAD rules/foo.md'
expect_allow 'rm build.log'
expect_allow 'rm -f build.log'
expect_allow 'rm -r ./build'
expect_allow 'ls -la'
expect_allow 'bash tests/test_init_sh.sh'

echo "=== 異常入力（判定不能は拒否） ==="
run_raw 'not json'
if [ "$RC" -eq 0 ] && is_deny_output; then
  ok "DENY  | 不正な JSON 入力"
  echo "        $(printf '%s' "$OUT" | jq -c .)"
else
  ng "不正な JSON 入力が拒否されなかった | rc=$RC out=$OUT"
fi
run_raw ''
if [ "$RC" -eq 0 ] && is_deny_output; then
  ok "DENY  | 空の入力"
else
  ng "空の入力が拒否されなかった | rc=$RC out=$OUT"
fi
run_raw '{"tool_name":"Bash","tool_input":{}}'
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "ALLOW | command 無し（検査対象なし, 出力なし, exit 0）"
else
  ng "command 無しの入力 | rc=$RC out=$OUT"
fi

echo "=== 静的チェック ==="
# 権限フローを迂回する allow を出力しないこと
if grep -qE 'permissionDecision"?: *"allow"' "$HOOK"; then
  ng "フックが allow を出力しうる"
else
  ok "フックに allow を出力するコードが無い"
fi
# 検査対象のコマンドを評価・実行しないこと
if grep -qw 'eval' "$HOOK"; then
  ng "フックに eval が含まれる"
else
  ok "フックに eval が無い（コマンドを実行しない）"
fi
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | test("block-destructive\\.sh"))' "$SETTINGS" >/dev/null; then
  ok "settings.json に PreToolUse(matcher: Bash) で登録済み"
else
  ng "settings.json に登録されていない"
fi

echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
