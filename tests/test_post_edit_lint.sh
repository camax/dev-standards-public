#!/usr/bin/env bash
# .claude/hooks/post-edit-lint.sh のテスト。
# 一時ディレクトリに検証対象ファイルを作り、PostToolUse の JSON をフックに渡して
# 出力（additionalContext の有無と内容）と終了コードを確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/post-edit-lint.sh"
SETTINGS="$SCRIPT_DIR/../.claude/settings.json"

[ -x "$HOOK" ] || { echo "Error: $HOOK が無いか実行権限がない" >&2; exit 1; }

TMP_DIR="$(mktemp -d /tmp/test-post-edit-lint-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
ng() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }

# フックに生の stdin を渡し、OUT と RC を設定する。HOOK_PATH が空でなければ PATH を差し替える
HOOK_PATH=""
run_raw() {
  RC=0
  if [ -n "$HOOK_PATH" ]; then
    OUT="$(printf '%s' "$1" | PATH="$HOOK_PATH" "$HOOK")" || RC=$?
  else
    OUT="$(printf '%s' "$1" | "$HOOK")" || RC=$?
  fi
}

run_file() {
  run_raw "$(jq -n --arg p "$1" --arg t "${2:-Write}" --arg cwd "$TMP_DIR" \
    '{hook_event_name: "PostToolUse", tool_name: $t, cwd: $cwd, tool_input: {file_path: $p}}')"
}

# 出力が PostToolUse の additionalContext のみで、ブロック系のキーを含まないこと
is_feedback_output() {
  printf '%s' "$OUT" | jq -e '
    .hookSpecificOutput.hookEventName == "PostToolUse"
    and (.hookSpecificOutput.additionalContext | type == "string" and startswith("[post-edit-lint]"))
    and (.hookSpecificOutput | has("permissionDecision") | not)
    and (has("decision") | not)
  ' >/dev/null 2>&1
}

# $1: ファイル, $2: additionalContext に含まれるべき文字列, $3: 説明
expect_feedback() {
  run_file "$1"
  if [ "$RC" -eq 0 ] && is_feedback_output \
     && printf '%s' "$OUT" | jq -e --arg s "$2" '.hookSpecificOutput.additionalContext | contains($s)' >/dev/null; then
    ok "FEEDBACK | $3"
    printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | sed 's/^/          /'
  else
    ng "FEEDBACK 期待（'$2' を含む）だが不一致 | $3 | rc=$RC out=$OUT"
  fi
}

expect_silent() {
  run_file "$1"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    ok "SILENT   | $2 | (出力なし, exit 0)"
  else
    ng "SILENT 期待だが出力あり | $2 | rc=$RC out=$OUT"
  fi
}

T="$TMP_DIR"

echo "=== .sh ==="
printf '#!/usr/bin/env bash\nif true; then\n  echo ok\n' > "$T/broken.sh"
printf '#!/usr/bin/env bash\nset -eu\necho "ok"\n' > "$T/good.sh"
printf '#!/bin/bash\nfor x in; do\n' > "$T/no-ext-bash"
printf '#!/usr/bin/env python3\nprint(1\n' > "$T/no-ext-python"
mkdir -p "$T/dir with space"
printf 'echo "unterminated\n' > "$T/dir with space/broken.sh"
expect_feedback "$T/broken.sh" "bash -n" "if の閉じ忘れ（fi なし）"
expect_silent "$T/good.sh" "正しいスクリプト"
expect_feedback "$T/no-ext-bash" "bash -n" "拡張子なし + bash の shebang"
expect_silent "$T/no-ext-python" "拡張子なし + bash 以外の shebang は対象外"
expect_feedback "$T/dir with space/broken.sh" "bash -n" "パスに空白を含む"

echo "=== shellcheck（存在すれば実行 / 無くても落ちない） ==="
# 偽の shellcheck を置いた PATH: 呼ばれれば出力がフィードバックに含まれる
STUB_DIR="$T/stub-bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "STUB-SHELLCHECK $*"
exit 1
EOF
chmod +x "$STUB_DIR/shellcheck"
HOOK_PATH="$STUB_DIR:$PATH"
expect_feedback "$T/good.sh" "STUB-SHELLCHECK -f gcc -S warning" "shellcheck があれば実行し、指摘を返す"
HOOK_PATH=""

# shellcheck を含まない PATH: フックが使うコマンドだけを symlink したディレクトリ
NOSC_DIR="$T/no-shellcheck-bin"
mkdir -p "$NOSC_DIR"
for c in bash env jq awk head wc tr cat python3; do
  p="$(command -v "$c" || true)"
  [ -n "$p" ] && ln -s "$p" "$NOSC_DIR/$c"
done
HOOK_PATH="$NOSC_DIR"
if PATH="$HOOK_PATH" command -v shellcheck >/dev/null 2>&1; then
  ng "テスト用 PATH に shellcheck が残っている"
fi
expect_silent "$T/good.sh" "shellcheck 不在 + 正しいスクリプト"
expect_feedback "$T/broken.sh" "bash -n" "shellcheck 不在でも bash -n は実行される"
HOOK_PATH=""

echo "=== .json ==="
printf '{"a": 1,}\n' > "$T/broken.json"
printf '{"a": [1, 2], "b": {"c": null}}\n' > "$T/good.json"
: > "$T/empty.json"
expect_feedback "$T/broken.json" "jq empty" "末尾カンマ"
expect_silent "$T/good.json" "正しい JSON"
expect_feedback "$T/empty.json" "ファイルが空" "空ファイル"
expect_silent "$SETTINGS" "リポジトリの .claude/settings.json"

echo "=== .md ==="
printf -- '---\nname: x\ndescription: y\n\n# 本文\n' > "$T/fm-unclosed.md"
printf -- '# 見出し\n\n```bash\necho 1\n\n本文\n' > "$T/fence-unclosed.md"
printf -- '# 見出し\n\n~~~\ncode\n```\n' > "$T/fence-mismatch.md"
cat > "$T/good.md" <<'EOF'
---
name: x
description: y
---

# 見出し

本文

---

````markdown
```bash
echo nested
```
````

~~~
code
~~~

インラインの ```code``` は行頭でなければフェンスではない。
EOF
printf -- '# 見出し\n\n---\n\n本文\n' > "$T/hr-only.md"
expect_feedback "$T/fm-unclosed.md" "frontmatter" "frontmatter の閉じ --- なし"
expect_feedback "$T/fence-unclosed.md" "3 行目で開いたフェンス" "コードフェンスの閉じ忘れ"
expect_feedback "$T/fence-mismatch.md" "コードフェンス" "~~~ を \`\`\` で閉じようとしている"
expect_silent "$T/good.md" "frontmatter + 入れ子フェンス + 区切り線"
expect_silent "$T/hr-only.md" "1 行目以外の --- は区切り線"

echo "=== .py ==="
if command -v python3 >/dev/null 2>&1; then
  printf 'def f(:\n    pass\n' > "$T/broken.py"
  printf 'def f():\n    return 1\n' > "$T/good.py"
  expect_feedback "$T/broken.py" "python3 compile" "def の構文エラー"
  expect_silent "$T/good.py" "正しい Python"
  if [ -e "$T/__pycache__" ]; then ng ".pyc を書き出している"; else ok "__pycache__ を作らない"; fi
else
  echo "[SKIP] python3 が無い"
fi

echo "=== 対象外・異常入力（何も出力せず exit 0） ==="
printf 'anything {{{\n' > "$T/note.txt"
expect_silent "$T/note.txt" "未対応の拡張子"
expect_silent "$T/does-not-exist.sh" "存在しないファイル"
expect_feedback "broken.sh" "$T/broken.sh" "相対パスは cwd 基準で解決する"
run_raw 'not json'
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "SILENT   | 不正な JSON 入力"; else ng "不正な JSON 入力 | rc=$RC out=$OUT"; fi
run_raw ''
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "SILENT   | 空の入力"; else ng "空の入力 | rc=$RC out=$OUT"; fi
run_raw '{"tool_name":"Edit","tool_input":{}}'
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "SILENT   | file_path 無し"; else ng "file_path 無し | rc=$RC out=$OUT"; fi
run_file "$T/broken.sh" "Edit"
if [ "$RC" -eq 0 ] && is_feedback_output; then ok "FEEDBACK | tool_name=Edit でも同じく動作"; else ng "tool_name=Edit | rc=$RC out=$OUT"; fi

echo "=== 長い出力の切り詰め ==="
cat > "$STUB_DIR/shellcheck" <<'EOF'
#!/usr/bin/env bash
for i in $(seq 1 100); do echo "STUB line $i"; done
exit 1
EOF
HOOK_PATH="$STUB_DIR:$PATH"
run_file "$T/good.sh"
HOOK_PATH=""
CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || true)"
if printf '%s' "$CTX" | grep -q 'STUB line 30$' && ! printf '%s' "$CTX" | grep -q 'STUB line 31$' \
   && printf '%s' "$CTX" | grep -q '以下 70 行省略'; then
  ok "検証ツールの出力は 30 行で切り詰める"
else
  ng "切り詰めが期待どおりでない | $CTX"
fi

echo "=== 静的チェック ==="
if grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE 'permissionDecision|"block"|decision:'; then
  ng "フックがブロック系の出力（permissionDecision / decision: block）を含む"
else
  ok "フックにブロック系の出力が無い（フィードバックのみ）"
fi
if grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE 'exit [1-9]'; then
  ng "フックが 0 以外で exit しうる"
else
  ok "フックは exit 0 のみ"
fi
if jq -e '.hooks.PostToolUse[] | select(.matcher == "Edit|Write") | .hooks[] | select(.command | test("post-edit-lint\\.sh"))' "$SETTINGS" >/dev/null; then
  ok "settings.json に PostToolUse(matcher: Edit|Write) で登録済み"
else
  ng "settings.json に PostToolUse が登録されていない"
fi
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | test("block-destructive\\.sh"))' "$SETTINGS" >/dev/null; then
  ok "既存の PreToolUse(Bash) 登録が残っている"
else
  ng "既存の PreToolUse(Bash) 登録が消えた"
fi

echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
