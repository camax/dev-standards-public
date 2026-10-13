#!/usr/bin/env bash
# PostToolUse(Edit|Write) フック: 編集直後のファイルを静的検証し、問題を Claude に返す。
#
# stdin で受け取る JSON の tool_input.file_path を拡張子（拡張子が無い場合は shebang）で
# 判別し、次の検証を行う:
#   - .sh / .bash / sh・bash の shebang: bash -n（構文）。shellcheck があれば -S warning で実行
#   - .json: jq empty（構文）。空ファイルも不正として扱う
#   - .md: 1 行目の frontmatter（---）が閉じているか、コードフェンス（``` / ~~~）が閉じているか
#   - .py: python3 があれば compile() で構文確認（.pyc は書き出さない）
#
# 問題を検知した場合のみ hookSpecificOutput.additionalContext で内容を返す。
# フィードバック専用であり、permissionDecision や decision: "block" は決して出力しない。
# 検証できない状況（jq 不在・入力 JSON 不正・ファイル不在・未対応の種別）は何も出力せず exit 0。
# 常に exit 0 で終了する（Claude の作業を止めない）。

set -u

PREFIX="[post-edit-lint]"
MAX_LINES=30
PROBLEMS=""

# 検証ツールの出力を MAX_LINES 行までに切り詰めて PROBLEMS に追記する
add_problem() {
  local label="$1" body="$2" total
  total="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  if [ "$total" -gt "$MAX_LINES" ]; then
    body="$(printf '%s\n' "$body" | head -n "$MAX_LINES")
…（以下 $((total - MAX_LINES)) 行省略）"
  fi
  PROBLEMS="${PROBLEMS}
--- ${label} ---
${body}"
}

check_sh() {
  local out
  out="$(bash -n "$FILE" 2>&1)" || add_problem "bash -n（構文エラー）" "$out"
  if command -v shellcheck >/dev/null 2>&1; then
    out="$(shellcheck -f gcc -S warning "$FILE" 2>&1)" || add_problem "shellcheck" "$out"
  fi
}

check_json() {
  local out
  if [ ! -s "$FILE" ]; then
    add_problem "jq empty（構文エラー）" "ファイルが空（JSON として不正）"
    return
  fi
  out="$(jq empty "$FILE" 2>&1)" || add_problem "jq empty（構文エラー）" "$out"
}

check_md() {
  local out
  out="$(awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 { if ($0 == "---" || $0 == "...") fm = 2; next }
    {
      # 行頭 0〜3 個の空白に続く 3 文字以上の ` / ~ の連続をフェンスとみなす
      line = $0; ind = 0
      while (ind < 3 && substr(line, 1, 1) == " ") { line = substr(line, 2); ind++ }
      c = substr(line, 1, 1)
      if (c != "`" && c != "~") next
      n = 0
      while (substr(line, n + 1, 1) == c) n++
      if (n < 3) next
      rest = substr(line, n + 1)
      if (!open) {
        if (c == "`" && index(rest, "`") > 0) next
        open = 1; och = c; olen = n; oline = NR
      } else if (c == och && n >= olen && rest ~ /^[ \t]*$/) {
        open = 0
      }
    }
    END {
      if (fm == 1) print "frontmatter: 1 行目の --- に対応する閉じの --- がない（ファイル末尾まで frontmatter 扱いになる）"
      if (open) printf "コードフェンス: %d 行目で開いたフェンス（%s が %d 個）が閉じられていない\n", oline, och, olen
    }
  ' "$FILE" 2>&1)"
  [ -z "$out" ] || add_problem "Markdown 構造" "$out"
}

check_py() {
  local out
  command -v python3 >/dev/null 2>&1 || return 0
  out="$(python3 - "$FILE" 2>&1 <<'PY'
import sys
path = sys.argv[1]
try:
    with open(path, "rb") as f:
        compile(f.read(), path, "exec")
except SyntaxError as e:
    print(f"{path}:{e.lineno}:{e.offset}: {e.msg}")
    sys.exit(1)
PY
)" || add_problem "python3 compile（構文エラー）" "$out"
}

is_sh_shebang() {
  local first
  IFS= read -r first < "$FILE" || [ -n "$first" ] || return 1
  case "$first" in
    '#!'*bash*|'#!'*/sh|'#!'*/sh' '*|'#!'*' sh'|'#!'*' sh '*) return 0 ;;
  esac
  return 1
}

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // "" | if type == "string" then . else "" end' 2>/dev/null)" || exit 0
[ -n "$FILE" ] || exit 0

case "$FILE" in
  /*) ;;
  *)
    CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // "" | if type == "string" then . else "" end' 2>/dev/null)" || CWD=""
    [ -n "$CWD" ] && FILE="$CWD/$FILE"
    ;;
esac
[ -f "$FILE" ] || exit 0

BASE="${FILE##*/}"
case "$BASE" in
  *.sh|*.bash) check_sh ;;
  *.json) check_json ;;
  *.md|*.markdown) check_md ;;
  *.py) check_py ;;
  *.*) ;;
  *) is_sh_shebang && check_sh ;;
esac

[ -n "$PROBLEMS" ] || exit 0

jq -n --arg c "$PREFIX $FILE の静的検証で問題を検知した（編集はブロックしていない。内容を確認し、意図しない崩れなら修正すること）:$PROBLEMS" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
