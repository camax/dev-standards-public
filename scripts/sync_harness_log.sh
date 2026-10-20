#!/usr/bin/env bash
# Gitフック・ハーネスのログをObsidianへ集約する同期スクリプト
# 各端末の ~/.harness-log/*.jsonl の全内容を、対応する集約先ファイルへ上書きコピーします。
set -euo pipefail

# 1. ホスト名の決定（HARNESS_HOST 未設定時は hostname -s）とサニタイズ（スペースをアンダースコアに置換）
HOST="${HARNESS_HOST:-$(hostname -s)}"
SAFE_HOST="${HOST// /_}"

# 2. 出力先ディレクトリの決定
DEST_DIR=""
if [ -n "${OBSIDIAN_VAULT:-}" ] && [ -d "$OBSIDIAN_VAULT/AI_Config" ]; then
  DEST_DIR="$OBSIDIAN_VAULT/AI_Config/harness-logs"
elif [ -d "$HOME/Desktop/work/Obsidian/AI_Config" ]; then
  DEST_DIR="$HOME/Desktop/work/Obsidian/AI_Config/harness-logs"
elif [ -d "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/ObsidianVault/AI_Config" ]; then
  DEST_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/ObsidianVault/AI_Config/harness-logs"
else
  echo "エラー: Obsidian の AI_Config ディレクトリが見つかりません。" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
DEST_FILE="$DEST_DIR/${SAFE_HOST}.jsonl"

# 3. ログ元ディレクトリ
SRC_DIR="${HARNESS_LOG_DIR:-$HOME/.harness-log}"

echo "ホスト名: $HOST"
echo "出力先: $DEST_FILE"

# 4. ~/.harness-log/*.jsonl の全内容を上書きコピー
shopt -s nullglob
LOG_FILES=("$SRC_DIR"/*.jsonl)
shopt -u nullglob

if [ ${#LOG_FILES[@]} -eq 0 ]; then
  : > "$DEST_FILE"
  echo "情報: ログファイルが見つかりません ($SRC_DIR)。空ファイルを生成しました: $DEST_FILE"
else
  cat "${LOG_FILES[@]}" > "$DEST_FILE"
  LINE_COUNT=$(wc -l < "$DEST_FILE" | tr -d ' ')
  echo "同期完了: ${#LOG_FILES[@]} 個のログファイル ($LINE_COUNT 行) を $DEST_FILE へ反映しました。"
fi
