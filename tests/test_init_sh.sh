#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SCRIPT="$SCRIPT_DIR/../project_template/init.sh"

TMP_DIR="$(mktemp -d /tmp/test-init-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="$TMP_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_init() {
  local type="$1" stack="$2" dest="$TMP_DIR/${1}_${2}"
  mkdir -p "$dest"
  (cd "$dest" && bash "$INIT_SCRIPT" --type="$type" --stack="$stack" >/dev/null 2>&1)
  echo "$dest"
}

# client-delivery: coding_standards.md の §1 は stack=other で除去、kintone-gas で残る
D=$(run_init client-delivery other)
CS="$D/.agent/rules/coding_standards.md"
grep -q '^## 1\. Kintone' "$CS" && fail "client-delivery/other: coding_standards.md に §1 が残っている"
grep -q '^## 2\. ' "$CS" || fail "client-delivery/other: coding_standards.md の §2 が欠落"
grep -q 'stack:kintone-gas' "$CS" && fail "client-delivery/other: coding_standards.md にマーカーが残っている"
grep -q 'GASの場合' "$D/.agent/rules/git_safety.md" && fail "client-delivery/other: git_safety.md 3.1 に GAS 行が残っている"

D=$(run_init client-delivery kintone-gas)
CS="$D/.agent/rules/coding_standards.md"
grep -q '^## 1\. Kintone' "$CS" || fail "client-delivery/kintone-gas: coding_standards.md の §1 が欠落"
grep -q 'stack:kintone-gas' "$CS" && fail "client-delivery/kintone-gas: coding_standards.md にマーカーが残っている"
grep -q 'GASの場合' "$D/.agent/rules/git_safety.md" || fail "client-delivery/kintone-gas: git_safety.md 3.1 の GAS 行が欠落"

# client-delivery: dev-standards 保守用の repo_checkup.sh / goal_loop.sh / local_delegate.py は配布しない（他の scripts/ は配布する）
for stack in other kintone-gas; do
  D="$TMP_DIR/client-delivery_$stack"
  [ -e "$D/.agent/scripts/repo_checkup.sh" ] && fail "client-delivery/$stack: repo_checkup.sh が配布されている"
  [ -e "$D/.agent/scripts/goal_loop.sh" ] && fail "client-delivery/$stack: goal_loop.sh が配布されている"
  [ -e "$D/.agent/scripts/local_delegate.py" ] && fail "client-delivery/$stack: local_delegate.py が配布されている"
  for f in deploy_skills.py sync_harness_log.sh sync_to_delivery.sh; do
    [ -f "$D/.agent/scripts/$f" ] || fail "client-delivery/$stack: scripts/$f が配布されていない"
  done
done
[ -f "$SCRIPT_DIR/../scripts/repo_checkup.sh" ] || fail "配布元の scripts/repo_checkup.sh が消えている"
[ -f "$SCRIPT_DIR/../scripts/goal_loop.sh" ] || fail "配布元の scripts/goal_loop.sh が消えている"
[ -f "$SCRIPT_DIR/../scripts/local_delegate.py" ] || fail "配布元の scripts/local_delegate.py が消えている"

# update.sh: repo_checkup.sh / goal_loop.sh / local_delegate.py を配布先に入れない（配布済みの古いコピーは除去）。他ファイルは通常どおり同期する
UPD="$TMP_DIR/update_target"   # update.sh で配置を書き換えるため、他テストと配置を共有しない
mkdir -p "$UPD"
(cd "$UPD" && bash "$INIT_SCRIPT" --type=client-delivery --stack=other >/dev/null 2>&1)
cp "$SCRIPT_DIR/../scripts/repo_checkup.sh" "$UPD/.agent/scripts/repo_checkup.sh"
cp "$SCRIPT_DIR/../scripts/goal_loop.sh" "$UPD/.agent/scripts/goal_loop.sh"
cp "$SCRIPT_DIR/../scripts/local_delegate.py" "$UPD/.agent/scripts/local_delegate.py"
echo "# stale" >> "$UPD/.agent/scripts/sync_to_delivery.sh"
UPD_OUT=$(cd "$UPD" && bash "$SCRIPT_DIR/../project_template/update.sh" --yes 2>&1) || fail "update.sh が失敗した: $UPD_OUT"
[ -e "$UPD/.agent/scripts/repo_checkup.sh" ] && fail "update.sh: repo_checkup.sh が配布先に残っている"
printf '%s\n' "$UPD_OUT" | grep -q 'Only in .*repo_checkup.sh' && fail "update.sh: 同期diffに repo_checkup.sh が出ている"
[ -e "$UPD/.agent/scripts/goal_loop.sh" ] && fail "update.sh: goal_loop.sh が配布先に残っている"
printf '%s\n' "$UPD_OUT" | grep -q 'Only in .*goal_loop.sh' && fail "update.sh: 同期diffに goal_loop.sh が出ている"
[ -e "$UPD/.agent/scripts/local_delegate.py" ] && fail "update.sh: local_delegate.py が配布先に残っている"
printf '%s\n' "$UPD_OUT" | grep -q 'Only in .*local_delegate.py' && fail "update.sh: 同期diffに local_delegate.py が出ている"
cmp -s "$SCRIPT_DIR/../scripts/sync_to_delivery.sh" "$UPD/.agent/scripts/sync_to_delivery.sh" || fail "update.sh: 他ファイルが同期されていない"

# update.sh: project_type.conf の STACK に従い、git_safety.md / coding_standards.md を init.sh と同じ内容に加工して同期する
for stack in other kintone-gas; do
  UPD="$TMP_DIR/update_stack_$stack"
  mkdir -p "$UPD"
  (cd "$UPD" && bash "$INIT_SCRIPT" --type=client-delivery --stack="$stack" >/dev/null 2>&1)
  mkdir -p "$TMP_DIR/expected_$stack"
  cp "$UPD/.agent/rules/git_safety.md" "$UPD/.agent/rules/coding_standards.md" "$TMP_DIR/expected_$stack/"
  # 旧 update.sh が原本（マーカー入り）を同期した状態を再現する
  cp "$SCRIPT_DIR/../rules/git_safety.md" "$SCRIPT_DIR/../rules/coding_standards.md" "$UPD/.agent/rules/"
  UPD_OUT=$(cd "$UPD" && bash "$SCRIPT_DIR/../project_template/update.sh" --yes 2>&1) || fail "update.sh/$stack が失敗した: $UPD_OUT"
  for f in git_safety.md coding_standards.md; do
    cmp -s "$TMP_DIR/expected_$stack/$f" "$UPD/.agent/rules/$f" || fail "update.sh/$stack: $f が init.sh の配布内容と一致しない"
    grep -q 'stack:kintone-gas' "$UPD/.agent/rules/$f" && fail "update.sh/$stack: $f にマーカーが残っている"
  done
  cmp -s "$SCRIPT_DIR/../rules/language.md" "$UPD/.agent/rules/language.md" || fail "update.sh/$stack: 加工対象外の language.md が原本と異なる"
  UPD_OUT=$(cd "$UPD" && bash "$SCRIPT_DIR/../project_template/update.sh" --yes 2>&1) || fail "update.sh/$stack の2回目が失敗した: $UPD_OUT"
  printf '%s\n' "$UPD_OUT" | grep -q '差分なし' || fail "update.sh/$stack: 2回目が差分なしにならない: $UPD_OUT"
done

# update.sh: project_type.conf が無ければ WARNING を出し、加工せず原本のまま同期する
UPD="$TMP_DIR/update_noconf"
mkdir -p "$UPD"
(cd "$UPD" && bash "$INIT_SCRIPT" --type=client-delivery --stack=other >/dev/null 2>&1)
rm -f "$UPD/.agent/project_type.conf"
UPD_OUT=$(cd "$UPD" && bash "$SCRIPT_DIR/../project_template/update.sh" --yes 2>&1) || fail "update.sh（conf なし）が失敗した: $UPD_OUT"
printf '%s\n' "$UPD_OUT" | grep -q 'WARNING.*project_type.conf' || fail "update.sh（conf なし）: WARNING が出ない"
for f in git_safety.md coding_standards.md; do
  cmp -s "$SCRIPT_DIR/../rules/$f" "$UPD/.agent/rules/$f" || fail "update.sh（conf なし）: $f が原本のまま同期されていない"
done

# update.sh: STACK が不正値なら ERROR で中断し、配置を書き換えない
UPD="$TMP_DIR/update_badstack"
mkdir -p "$UPD"
(cd "$UPD" && bash "$INIT_SCRIPT" --type=client-delivery --stack=other >/dev/null 2>&1)
printf 'TYPE=client-delivery\nSTACK=bogus\n' > "$UPD/.agent/project_type.conf"
cp "$UPD/.agent/rules/coding_standards.md" "$TMP_DIR/badstack_before.md"
UPD_OUT=$(cd "$UPD" && bash "$SCRIPT_DIR/../project_template/update.sh" --yes 2>&1) && fail "update.sh（STACK=bogus）が成功した"
printf '%s\n' "$UPD_OUT" | grep -q 'ERROR' || fail "update.sh（STACK=bogus）: ERROR が出ない"
cmp -s "$TMP_DIR/badstack_before.md" "$UPD/.agent/rules/coding_standards.md" || fail "update.sh（STACK=bogus）: 中断したのに配置が書き換わった"

# internal-only: coding_standards.md は配布しない
for stack in other kintone-gas; do
  D=$(run_init internal-only "$stack")
  [ -e "$D/.agent/rules/coding_standards.md" ] && fail "internal-only/$stack: coding_standards.md が配布されている"
done

# --print-rules: coding_standards.md は client-delivery のみ出力し、実配置と一致する
for stack in other kintone-gas; do
  OUT=$(cd "$TMP_DIR" && bash "$INIT_SCRIPT" --print-rules --type=client-delivery --stack="$stack")
  printf '%s\n' "$OUT" | sed -n '/^===== .agent\/rules\/coding_standards.md =====$/,$p' | tail -n +2 \
    | diff - "$TMP_DIR/client-delivery_${stack}/.agent/rules/coding_standards.md" >/dev/null \
    || fail "print-rules client-delivery/$stack: coding_standards.md の出力が実配置と一致しない"

  OUT=$(cd "$TMP_DIR" && bash "$INIT_SCRIPT" --print-rules --type=internal-only --stack="$stack")
  printf '%s\n' "$OUT" | grep -q 'coding_standards.md' && fail "print-rules internal-only/$stack: coding_standards.md が出力されている"
done

# 公開リポジトリ向け: init.sh に特定の案件名が残っていないこと
# 検知対象の名前自体をリポジトリに残さないため、文字列を分割して記述する
grep -q 'HC_''Project' "$INIT_SCRIPT" && fail "init.sh に特定の案件名が残っている"

# 対話プロンプトの 1 番は汎用スタック(other)であること
grep -q '1) STACK=other' "$INIT_SCRIPT" || fail "init.sh: 対話プロンプトの 1 番が other ではない"

echo "test_init_sh: PASSED"
