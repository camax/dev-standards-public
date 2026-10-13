#!/bin/bash
# update.sh — 既存プロジェクトの .agent/ を dev-standards の最新に同期する
#
# 使い方: 既存プロジェクトのルートディレクトリで実行する
#   <dev-standardsのパス>/project_template/update.sh [--yes]
#
# 動作:
#   - dev-standards の rules/ templates/ hooks/ scripts/ を .agent/ 配下に同名上書きで同期
#     （プロジェクト固有の追加ファイルは消さない。dev-standards側で削除された
#       ファイルも自動削除しない — diff の「Only in」表示を確認して手動対応）
#   - .agent/project_type.conf の STACK に応じて rules/git_safety.md と rules/coding_standards.md を
#     init.sh の strip_stack() と同じ規則で加工してから同期する
#     （other: stack マーカーで囲まれたブロックを削除、kintone-gas: マーカー行だけ削除）。
#     project_type.conf が無ければ WARNING を出して加工せずに同期する。TYPE は参照しない
#   - 同期前に diff（加工後の内容との比較）を表示し、確認プロンプトを挟む（--yes で省略可）
#   - git リポジトリなら pre-push フックを再設置
# 触らないもの（プロジェクト固有ファイルの自動書き換えは事故のもと）:
#   - CLAUDE.md / .agent/project.md / .agent/delivery.conf / .agent/delivery_allowlist.txt
#   - .agent/skills/（プロジェクト固有スキルが混在しうるため同期対象外）

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$(pwd)"
DIRS="rules templates hooks scripts"
# dev-standards 保守用で配布先に不要なファイル（SRC からの相対パス）。init.sh の DIST_EXCLUDE と同じ内容に保つ。
# 同期diffの表示対象から外し、同期後は配布先からも取り除く（配布済みの古いコピーがあれば消える。他ファイルは従来どおり削除しない）。
DIST_EXCLUDE="scripts/repo_checkup.sh scripts/goal_loop.sh scripts/local_delegate.py"

if [ ! -d "$DEST/.agent" ]; then
  echo "ERROR: $DEST/.agent がありません。新規導入は init.sh を使ってください。" >&2
  exit 1
fi

# init.sh が記録した STACK を読む（無ければ加工しない）
CONF="$DEST/.agent/project_type.conf"
STACK=""
if [ -f "$CONF" ]; then
  STACK="$(sed -n 's/^STACK=//p' "$CONF" | tail -n 1)"
  case "$STACK" in
    kintone-gas|other) ;;
    *) echo "ERROR: $CONF の STACK が不正です（'$STACK'）。kintone-gas か other を指定してください。" >&2; exit 1 ;;
  esac
else
  echo "WARNING: $CONF がありません。rules/ を stack に応じて加工せず、原本のまま同期します。" >&2
fi

# init.sh の strip_stack() と同じ規則。stack=other はブロックごと、kintone-gas はマーカー行だけ削除する。
strip_stack() {
  if [ "$STACK" = "other" ]; then
    sed '/<!-- stack:kintone-gas:start -->/,/<!-- stack:kintone-gas:end -->/d'
  else
    sed -e '/<!-- stack:kintone-gas:start -->/d' -e '/<!-- stack:kintone-gas:end -->/d'
  fi
}

# 同期元を一時ディレクトリに組み立て、diff と同期の両方をこの加工後の内容で行う
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/update-agent-XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
for d in $DIRS; do
  cp -R "$SRC/$d" "$STAGE/$d"
done
if [ -n "$STACK" ]; then
  for f in rules/git_safety.md rules/coding_standards.md; do
    strip_stack < "$SRC/$f" > "$STAGE/$f"
  done
fi

echo "=== 同期diff（現在の .agent/ → dev-standards${STACK:+（stack=$STACK で加工後）}） ==="
changed=0
for d in $DIRS; do
  if [ -d "$DEST/.agent/$d" ]; then
    diff_x=()
    for ex in $DIST_EXCLUDE; do
      case "$ex" in "$d"/*) diff_x+=(-x "${ex#"$d"/}") ;; esac
    done
    if ! diff -ru ${diff_x[@]+"${diff_x[@]}"} "$DEST/.agent/$d" "$STAGE/$d"; then
      changed=1
    fi
  else
    echo "（新規追加: .agent/${d} ← ${SRC}/${d}）"
    changed=1
  fi
done
if [ "$changed" = "0" ]; then
  echo "差分なし。フックの再設置のみ行います。"
fi

if [ "${1:-}" != "--yes" ]; then
  if [ ! -t 0 ]; then
    echo "ERROR: 非対話実行では --yes を付けてください。" >&2
    exit 1
  fi
  printf "上記の内容で .agent/ を上書き同期します。続行しますか? (yes/no): "
  read -r ans
  if [ "$ans" != "yes" ]; then
    echo "中断しました。"
    exit 1
  fi
fi

for d in $DIRS; do
  mkdir -p "$DEST/.agent/$d"
  cp -R "$STAGE/$d/." "$DEST/.agent/$d/"
done
for ex in $DIST_EXCLUDE; do
  rm -f "$DEST/.agent/$ex"
done
chmod +x "$DEST/.agent/hooks/pre-push" "$DEST/.agent/scripts/"*.sh

if [ -d "$DEST/.git" ]; then
  cp "$DEST/.agent/hooks/pre-push" "$DEST/.git/hooks/pre-push"
  chmod +x "$DEST/.git/hooks/pre-push"
  echo "OK: pre-push フックを再設置しました。"
else
  echo "WARNING: git リポジトリではないため pre-push フックを設置していません。" >&2
  echo "         git init / clone 後に以下を実行してください:" >&2
  echo "         cp .agent/hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push" >&2
fi

echo "OK: .agent/ の rules/ templates/ hooks/ scripts/ を同期しました。"
