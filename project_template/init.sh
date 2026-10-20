#!/bin/bash
# init.sh — 新プロジェクトに dev-standards のルールセットを導入する
#
# 使い方: 新プロジェクトのルートディレクトリで実行する
#   <dev-standardsのパス>/project_template/init.sh [--type=client-delivery|internal-only] [--stack=kintone-gas|other]
#   引数を省略すると対話式で選択する（非対話実行では引数必須）。
#
# プロジェクトタイプ:
#   client-delivery … クライアント納品あり。ルール一式（rules/ skills/ templates/ hooks/ scripts/
#                      と project.md / delivery.conf / delivery_allowlist.txt を含む4章・delivery系）を配布する。
#   internal-only    … 内部利用のみ。git_safety.md の 2.5（エビデンス添付義務）・2.9（成功条件駆動）・
#                      3.1（検証手順ファースト）と、antigravity_qc_checklist.md の観点C（単純化QC）のみを
#                      抜粋して配布する。4章・delivery系・hooks/・scripts/・templates/・skills/ は配布しない。
#
# スタック:
#   kintone-gas … 3.1 に GAS / Kintone JS カスタマイズ向けの書き分けを含める。
#   other        … 3.1 から GAS / Kintone 固有の書き分けを取り除き、汎用的な検証手順ファーストの原則のみにする。
#                  client-delivery では coding_standards.md の §1（Kintone 固有）も取り除く。
#
# 稼働中プロジェクトへの後付け適用（.agent が既に存在するが dev-standards 由来ではない場合）:
#   init.sh は .agent が既に存在すると中断する。docs/APPLYING_TO_EXISTING_PROJECT.md の手順に従い、
#   下記 --print-rules で抜粋だけを生成し、配置は手動で行うこと。
#
#   <dev-standardsのパス>/project_template/init.sh --print-rules --type=... --stack=...
#     … ファイルを一切作成せず、配布されるはずの .agent/rules/*.md の内容を標準出力に印字するだけの
#       dry-run。DEST の .agent / CLAUDE.md の有無に関わらず実行できる。
#
# 安全ガード:
#   - 既存の .agent/ / CLAUDE.md があれば中断（既存プロジェクトの更新は update.sh を使う。
#     dev-standards 由来ではない .agent と共存させたい場合は --print-rules と手順書を使う）

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$(pwd)"

TYPE=""
STACK=""
PRINT_RULES=0
for arg in "$@"; do
  case "$arg" in
    --type=*) TYPE="${arg#--type=}" ;;
    --stack=*) STACK="${arg#--stack=}" ;;
    --print-rules) PRINT_RULES=1 ;;
    *) echo "ERROR: 不明な引数です: $arg" >&2; exit 1 ;;
  esac
done

if [ -z "$TYPE" ]; then
  if [ -t 0 ]; then
    echo "プロジェクトタイプを選んでください:"
    echo "  1) client-delivery  (クライアント納品あり案件)"
    echo "  2) internal-only    (内部利用のみ。例: パーフェクトライフログ)"
    printf "番号を入力 (1/2): "
    read -r ans
    case "$ans" in
      1) TYPE=client-delivery ;;
      2) TYPE=internal-only ;;
      *) echo "ERROR: 不正な選択です。" >&2; exit 1 ;;
    esac
  else
    echo "ERROR: 非対話実行では --type=client-delivery|internal-only を指定してください。" >&2
    exit 1
  fi
fi
case "$TYPE" in
  client-delivery|internal-only) ;;
  *) echo "ERROR: --type は client-delivery か internal-only のいずれかを指定してください。" >&2; exit 1 ;;
esac

if [ -z "$STACK" ]; then
  if [ -t 0 ]; then
    echo "技術スタックを選んでください:"
    echo "  1) kintone-gas  (Kintone + GAS)"
    echo "  2) other        (それ以外)"
    printf "番号を入力 (1/2): "
    read -r ans2
    case "$ans2" in
      1) STACK=kintone-gas ;;
      2) STACK=other ;;
      *) echo "ERROR: 不正な選択です。" >&2; exit 1 ;;
    esac
  else
    echo "ERROR: 非対話実行では --stack=kintone-gas|other を指定してください。" >&2
    exit 1
  fi
fi
case "$STACK" in
  kintone-gas|other) ;;
  *) echo "ERROR: --stack は kintone-gas か other のいずれかを指定してください。" >&2; exit 1 ;;
esac

# stack=other のとき、<!-- stack:kintone-gas:start/end --> で囲まれたブロックを削除する。
# stack=kintone-gas のときは、マーカー行だけを取り除いて中身を残す。
strip_stack() {
  if [ "$STACK" = "other" ]; then
    sed '/<!-- stack:kintone-gas:start -->/,/<!-- stack:kintone-gas:end -->/d'
  else
    sed -e '/<!-- stack:kintone-gas:start -->/d' -e '/<!-- stack:kintone-gas:end -->/d'
  fi
}

# 指定した見出し行（正規表現）から、次の "## " または "### " 見出し行の手前までを抜き出す。
extract_section() {
  local file="$1" pattern="$2"
  awk -v pat="$pattern" '
    $0 ~ pat { on=1 }
    on && ($0 ~ /^## /|| $0 ~ /^### /) && $0 !~ pat { exit }
    on { print }
  ' "$file"
}

build_git_safety() {
  if [ "$TYPE" = "client-delivery" ]; then
    strip_stack < "$SRC/rules/git_safety.md"
  else
    {
      echo "# 🛡️ Git Safety（internal-only プロファイル抜粋）"
      echo
      echo "このプロジェクトは internal-only プロファイルのため、dev-standards の"
      echo "rules/git_safety.md から一部の項目のみを抜粋しています。全文は"
      echo "dev-standards リポジトリの rules/git_safety.md を参照してください。"
      echo
      echo "---"
      echo
      extract_section "$SRC/rules/git_safety.md" '^### 2\.5 '
      echo
      echo "---"
      echo
      extract_section "$SRC/rules/git_safety.md" '^### 2\.9 '
      echo
      echo "---"
      echo
      extract_section "$SRC/rules/git_safety.md" '^### 3\.1 '
    } | strip_stack
  fi
}

build_qc_checklist() {
  if [ "$TYPE" = "client-delivery" ]; then
    cat "$SRC/rules/antigravity_qc_checklist.md"
  else
    echo "# 🔍 Antigravity QCチェックリスト（internal-only プロファイル抜粋）"
    echo
    echo "internal-only プロファイルのため、観点C（単純化QC）のみを抜粋しています。"
    echo
    extract_section "$SRC/rules/antigravity_qc_checklist.md" '^## 観点C'
    echo
    extract_section "$SRC/rules/antigravity_qc_checklist.md" '^## 出力形式'
  fi
}

if [ "$PRINT_RULES" = "1" ]; then
  echo "===== .agent/rules/git_safety.md ====="
  build_git_safety
  echo
  echo "===== .agent/rules/antigravity_qc_checklist.md ====="
  build_qc_checklist
  if [ "$TYPE" = "client-delivery" ]; then
    echo
    echo "===== .agent/rules/coding_standards.md ====="
    strip_stack < "$SRC/rules/coding_standards.md"
  fi
  exit 0
fi

for d in rules skills templates hooks scripts; do
  if [ ! -d "$SRC/$d" ]; then
    echo "ERROR: $SRC/$d が見つかりません。中断します。" >&2
    exit 1
  fi
done

if [ -e "$DEST/.agent" ]; then
  echo "ERROR: $DEST/.agent が既に存在します。既存プロジェクトの更新は update.sh を、" >&2
  echo "       dev-standards 由来ではない .agent と共存させたい場合は" >&2
  echo "       docs/APPLYING_TO_EXISTING_PROJECT.md の手順（--print-rules）を使ってください。" >&2
  exit 1
fi
if [ -e "$DEST/CLAUDE.md" ]; then
  echo "ERROR: $DEST/CLAUDE.md が既に存在します。上書きを防ぐため中断します。" >&2
  exit 1
fi

mkdir -p "$DEST/.agent"

# dev-standards リポジトリ自身の保守用で、配布先には不要なファイル（SRC からの相対パス）。
# client-delivery のコピー直後に、配布先側のコピーだけから取り除く（SRC は変更しない）。
DIST_EXCLUDE="scripts/repo_checkup.sh scripts/goal_loop.sh scripts/local_delegate.py"

if [ "$TYPE" = "client-delivery" ]; then
  for d in rules skills templates hooks scripts; do
    cp -R "$SRC/$d" "$DEST/.agent/$d"
  done
  for ex in $DIST_EXCLUDE; do
    rm -f "$DEST/.agent/$ex"
  done
  build_git_safety > "$DEST/.agent/rules/git_safety.md"
  strip_stack < "$SRC/rules/coding_standards.md" > "$DEST/.agent/rules/coding_standards.md"
  cp "$SRC/project_template/CLAUDE.md" "$DEST/CLAUDE.md"
  cp "$SRC/project_template/project.md" "$DEST/.agent/project.md"
  cp "$SRC/project_template/delivery.conf" "$DEST/.agent/delivery.conf"
  cp "$SRC/project_template/delivery_allowlist.txt" "$DEST/.agent/delivery_allowlist.txt"
  chmod +x "$DEST/.agent/hooks/pre-push" "$DEST/.agent/scripts/"*.sh
  PRE_PUSH_SRC="$DEST/.agent/hooks/pre-push"
else
  mkdir -p "$DEST/.agent/rules"
  build_git_safety > "$DEST/.agent/rules/git_safety.md"
  build_qc_checklist > "$DEST/.agent/rules/antigravity_qc_checklist.md"

  cat > "$DEST/CLAUDE.md" <<'EOF'
# 共有ルール（.agent/ をシングルソースとする）
本プロジェクトは internal-only プロファイルです。
.agent/rules/ の内容は dev-standards の抜粋であり、全文コピーではありません。
編集は dev-standards リポジトリ側で行い、反映は init.sh のプロファイル抽出を
再実行して行うこと（現時点で update.sh はプロファイルに対応していません）。

## 常時適用ルール（起動時に自動読込）
@.agent/rules/git_safety.md
@.agent/rules/antigravity_qc_checklist.md
EOF
  PRE_PUSH_SRC=""
fi

cat > "$DEST/.agent/project_type.conf" <<EOF
# init.sh が記録したプロジェクトタイプ。update.sh は STACK を参照して rules/ を加工する（TYPE は現時点で参照しない）。
TYPE=$TYPE
STACK=$STACK
EOF

if [ -n "$PRE_PUSH_SRC" ]; then
  if [ -d "$DEST/.git" ]; then
    cp "$PRE_PUSH_SRC" "$DEST/.git/hooks/pre-push"
    chmod +x "$DEST/.git/hooks/pre-push"
    echo "OK: pre-push フックを .git/hooks に設置しました。"
  else
    echo "WARNING: git リポジトリではないため pre-push フックを設置していません。" >&2
    echo "         git init / clone 後に以下を実行してください:" >&2
    echo "         cp .agent/hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push" >&2
  fi
fi

echo "OK: type=$TYPE, stack=$STACK で .agent/ と CLAUDE.md を配置しました。"
if [ "$TYPE" = "client-delivery" ]; then
  echo "    .agent/project.md と .agent/delivery.conf をプロジェクトに合わせて編集してください。"
fi
