#!/usr/bin/env bash
# goal_loop 試験用計画（plans/PLAN_goal_loop_trial.md）項目1「update.sh の stack 対応」の受け入れ検証。
# 失敗した確認をすべて列挙し、1件でもあれば終了コード 1。
#   1. init.sh --print-rules の4パターン（type × stack）が HEAD の init.sh と同一（init.sh の配布結果を変えていない）
#   2. update.sh 後の .agent/rules/git_safety.md / coding_standards.md が、同じ stack の
#      init.sh --print-rules --type=client-delivery の出力と一致し、マーカーが残らない
#   3. 2回目の update.sh は「差分なし」（同期 diff も加工後の内容と比較している）
#   4. project_type.conf が無ければ WARNING を出し、従来どおり加工せずに同期する
#   5. STACK が不正値なら ERROR で中断する
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INIT="$ROOT/project_template/init.sh"
UPDATE="$ROOT/project_template/update.sh"

TMP="$(mktemp -d /tmp/verify-update-stack-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ng() { FAILS=$((FAILS + 1)); echo "NG: $*"; }
ok() { echo "OK: $*"; }

# --print-rules の出力から1ファイル分を取り出す（次の ===== 見出しの手前の空行は区切りなので落とす）
section() { # $1: 出力ファイル, $2: .agent/rules/ 配下のファイル名
  awk -v h="===== .agent/rules/$2 =====" '
    $0 == h { on = 1; next }
    on && /^===== / { exit }
    on { buf[++n] = $0 }
    END { if (n && buf[n] == "") n--; for (i = 1; i <= n; i++) print buf[i] }
  ' "$1"
}

echo "=== 1. init.sh --print-rules 4パターンを HEAD と比較 ==="
mkdir -p "$TMP/base"
git -C "$ROOT" archive HEAD | tar -x -C "$TMP/base"
for type in client-delivery internal-only; do
  for stack in kintone-gas other; do
    (cd "$TMP" && bash "$TMP/base/project_template/init.sh" --print-rules --type="$type" --stack="$stack") > "$TMP/base_${type}_${stack}.txt"
    (cd "$TMP" && bash "$INIT" --print-rules --type="$type" --stack="$stack") > "$TMP/cur_${type}_${stack}.txt"
    if diff -u "$TMP/base_${type}_${stack}.txt" "$TMP/cur_${type}_${stack}.txt"; then
      ok "print-rules $type/$stack は HEAD と同一"
    else
      ng "print-rules $type/$stack が HEAD と異なる"
    fi
  done
done

for stack in kintone-gas other; do
  echo "=== 2-3. update.sh（stack=${stack}） ==="
  D="$TMP/proj_$stack"
  mkdir -p "$D"
  (cd "$D" && bash "$INIT" --type=client-delivery --stack="$stack") > /dev/null 2>&1 || { ng "init.sh が失敗（${stack}）"; continue; }
  # 旧 update.sh で同期された状態（マーカー入りの原本）を再現してから update.sh をかける
  cp "$ROOT/rules/git_safety.md" "$ROOT/rules/coding_standards.md" "$D/.agent/rules/"
  if (cd "$D" && bash "$UPDATE" --yes) > "$TMP/upd1_$stack.log" 2>&1; then
    ok "update.sh が成功（${stack}）"
  else
    ng "update.sh が失敗（${stack}）"; cat "$TMP/upd1_$stack.log"; continue
  fi
  for f in git_safety.md coding_standards.md; do
    section "$TMP/cur_client-delivery_${stack}.txt" "$f" > "$TMP/expected_${stack}_$f"
    if diff -u "$TMP/expected_${stack}_$f" "$D/.agent/rules/$f" > "$TMP/diff_${stack}_$f"; then
      ok "$f が print-rules client-delivery/$stack と一致"
    else
      ng "$f が print-rules client-delivery/$stack と一致しない（差分先頭20行）"; head -n 20 "$TMP/diff_${stack}_$f"
    fi
    if grep -q 'stack:kintone-gas' "$D/.agent/rules/$f"; then
      ng "$f に stack マーカーが残っている（${stack}）"
    else
      ok "$f に stack マーカーなし（${stack}）"
    fi
  done
  if cmp -s "$ROOT/rules/language.md" "$D/.agent/rules/language.md"; then
    ok "加工対象外の rules/language.md は原本どおり（${stack}）"
  else
    ng "加工対象外の rules/language.md が原本と異なる（${stack}）"
  fi
  if (cd "$D" && bash "$UPDATE" --yes) > "$TMP/upd2_$stack.log" 2>&1 && grep -q '差分なし' "$TMP/upd2_$stack.log"; then
    ok "2回目の update.sh は差分なし（${stack}）"
  else
    ng "2回目の update.sh が差分なしにならない（${stack}。出力先頭20行）"; head -n 20 "$TMP/upd2_$stack.log"
  fi
done

echo "=== 4. project_type.conf なし ==="
D="$TMP/proj_noconf"
mkdir -p "$D"
(cd "$D" && bash "$INIT" --type=client-delivery --stack=other) > /dev/null 2>&1
rm -f "$D/.agent/project_type.conf"
if (cd "$D" && bash "$UPDATE" --yes) > "$TMP/upd_noconf.log" 2>&1; then
  ok "update.sh が成功（conf なし）"
  grep -q 'WARNING.*project_type.conf' "$TMP/upd_noconf.log" && ok "project_type.conf についての WARNING を出す" || ng "conf なしで project_type.conf についての WARNING が出ない"
  if cmp -s "$ROOT/rules/git_safety.md" "$D/.agent/rules/git_safety.md" && cmp -s "$ROOT/rules/coding_standards.md" "$D/.agent/rules/coding_standards.md"; then
    ok "conf なしは加工せず原本どおり同期"
  else
    ng "conf なしで原本どおりに同期されていない"
  fi
else
  ng "update.sh が失敗（conf なし）"; cat "$TMP/upd_noconf.log"
fi

echo "=== 5. STACK 不正値 ==="
D="$TMP/proj_bad"
mkdir -p "$D"
(cd "$D" && bash "$INIT" --type=client-delivery --stack=other) > /dev/null 2>&1
printf 'TYPE=client-delivery\nSTACK=bogus\n' > "$D/.agent/project_type.conf"
if (cd "$D" && bash "$UPDATE" --yes) > "$TMP/upd_bad.log" 2>&1; then
  ng "STACK=bogus でも update.sh が成功した"
else
  grep -q 'ERROR' "$TMP/upd_bad.log" && ok "STACK 不正値は ERROR で中断" || ng "STACK 不正値で ERROR が出ない"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "verify_update_stack: PASSED"
else
  echo "verify_update_stack: FAILED（NG ${FAILS} 件）"
  exit 1
fi
