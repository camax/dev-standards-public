#!/bin/bash
# 内部リポジトリ → 納品ディレクトリ 許可リスト同期（git_safety.md 4.1）
# 使い方: .agent/scripts/sync_to_delivery.sh <納品ディレクトリ>
# 許可リストは .agent/delivery_allowlist.txt（記法は同ファイル冒頭のコメント参照）。
# 対象は git 管理下のファイルのみ。コピーした相対パス一覧を標準出力に出す（2.5の証拠用）。
set -euo pipefail

SRC="$(git rev-parse --show-toplevel)"
DEST="${1:?納品ディレクトリのパスを指定してください}"
LIST="$SRC/.agent/delivery_allowlist.txt"
[ -f "$LIST" ] || { echo "ERROR: $LIST がありません。" >&2; exit 1; }

includes=()
excludes=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -z "$line" ] && continue
  case "$line" in
    '!'*) excludes+=("${line#!}") ;;
    *)    includes+=("$line") ;;
  esac
done < "$LIST"

[ "${#includes[@]}" -gt 0 ] || { echo "ERROR: 許可リストに有効なパターンがありません。" >&2; exit 1; }

cd "$SRC"
git -c core.quotepath=false ls-files | while IFS= read -r f; do
  hit=0
  for pat in "${includes[@]}"; do
    [[ "$f" == $pat ]] && { hit=1; break; }
  done
  [ "$hit" = "1" ] || continue
  if [ "${#excludes[@]}" -gt 0 ]; then
    for pat in "${excludes[@]}"; do
      [[ "$f" == $pat ]] && { hit=0; break; }
    done
  fi
  [ "$hit" = "1" ] || continue
  mkdir -p "$DEST/$(dirname "$f")"
  cp "$f" "$DEST/$f"
  printf '%s\n' "$f"
done
