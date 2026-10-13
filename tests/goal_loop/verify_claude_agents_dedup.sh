#!/usr/bin/env bash
# goal_loop 試験用計画（plans/PLAN_goal_loop_trial.md）項目2「CLAUDE.md / AGENTS.md の重複解消」の受け入れ検証。
# 失敗した確認をすべて列挙し、1件でもあれば終了コード 1。
#   1. repo_checkup.sh --dup-files 2 で、CLAUDE.md と AGENTS.md の組の重複ブロックが 0 件
#   2. AGENTS.md「必要時に参照」の各箇条書き行が CLAUDE.md に逐語で残っていない（5行未満の重複も見る）
#   3. repo_checkup.sh の既定閾値での検知が 0 件（--no-remote）
#   4. AGENTS.md は HEAD から変更なし、CLAUDE.md の @import 行は HEAD と同じ
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKUP="$ROOT/scripts/repo_checkup.sh"

TMP="$(mktemp -d /tmp/verify-dedup-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ng() { FAILS=$((FAILS + 1)); echo "NG: $*"; }
ok() { echo "OK: $*"; }

echo "=== 1. repo_checkup.sh --dup-files 2（CLAUDE.md × AGENTS.md） ==="
"$CHECKUP" --repo "$ROOT" --no-remote --dup-files 2 --output "$TMP/dup2.md"
# 「### 2-n.」節ごとに列挙されたファイルを見て、ルートの CLAUDE.md と AGENTS.md を両方含む節を数える
pair="$(awk '
  /^### 2-[0-9]+\./ { if (c && a) n++; c = 0; a = 0; next }
  /^## 3\./ { exit }
  /^- `CLAUDE\.md` / { c = 1 }
  /^- `AGENTS\.md` / { a = 1 }
  END { if (c && a) n++; print n + 0 }
' "$TMP/dup2.md")"
if [ "$pair" -eq 0 ]; then
  ok "CLAUDE.md と AGENTS.md の重複ブロックは 0 件"
else
  ng "CLAUDE.md と AGENTS.md の重複ブロックが ${pair} 件"
  sed -n '/^## 2\./,/^## 3\./p' "$TMP/dup2.md"
fi

echo "=== 2. 「必要時に参照」の箇条書き行の残存 ==="
lines="$(awk '/^## 必要時に参照/ { on = 1; next } on && /^## / { exit } on && /^- / { print }' "$ROOT/AGENTS.md")"
if [ -z "$lines" ]; then
  ng "AGENTS.md に「## 必要時に参照」節の箇条書きが無い"
fi
left=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  if grep -qxF -- "$l" "$ROOT/CLAUDE.md"; then
    left=$((left + 1)); echo "  CLAUDE.md に残存: $l"
  fi
done <<EOF
$lines
EOF
if [ "$left" -eq 0 ]; then ok "CLAUDE.md に逐語で残る行なし"; else ng "CLAUDE.md に逐語で残る行が ${left} 行"; fi

echo "=== 3. repo_checkup.sh 既定閾値 ==="
if "$CHECKUP" --repo "$ROOT" --no-remote --fail-on-findings --output "$TMP/default.md"; then
  ok "既定閾値での検知 0 件"
else
  ng "既定閾値で検知あり"; sed -n '/^## サマリ/,/^## 1\./p' "$TMP/default.md"
fi

echo "=== 4. AGENTS.md と CLAUDE.md の @import ==="
if git -C "$ROOT" diff --quiet HEAD -- AGENTS.md; then ok "AGENTS.md は HEAD から変更なし"; else ng "AGENTS.md が変更されている"; fi
if diff <(git -C "$ROOT" show HEAD:CLAUDE.md | grep '^@') <(grep '^@' "$ROOT/CLAUDE.md"); then
  ok "CLAUDE.md の @import 行は HEAD と同じ"
else
  ng "CLAUDE.md の @import 行が HEAD と異なる"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "verify_claude_agents_dedup: PASSED"
else
  echo "verify_claude_agents_dedup: FAILED（NG ${FAILS} 件）"
  exit 1
fi
