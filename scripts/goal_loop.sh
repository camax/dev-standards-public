#!/usr/bin/env bash
# goal_loop.sh — PLAN.md 形式のタスクリストを上から1項目ずつ実行エージェント（claude -p）に委譲し、
# 検証コマンドの成否で完了判定・再試行・コミットまでを回すオーケストレーター。
# 人間が明示的に起動する前提（launchd 等の定期実行には組み込まない）。
#
# 使い方:
#   scripts/goal_loop.sh <plan.md> [max_iterations]
#     max_iterations … 実行エージェントの起動回数の上限（既定 10）。再試行も1回と数える。
#
# 計画ファイルの書式（1項目 = "- [ ] " 行から、次の "- [ ] " / "- [x] " 行または見出し行の手前まで）:
#   - [ ] 項目のタイトル
#     説明（インデントした後続行。そのまま実行エージェントに渡す）
#     <!-- verify: bash tests/xxx.sh -->          … 必須。リポジトリのルートで実行し、終了コード 0 で成功
#     <!-- commit: feat: 〜 -->                    … 必須。Conventional Commits の件名
#     <!-- files: path/a.sh tests/test_*.sh -->    … 任意。変更してよいパス（glob、空白区切り）
#
# 1項目の流れ:
#   1. 検証コマンドを作業前に実行する。既に成功する場合は検証として機能しないので、停止して人間に判断を求める
#   2. claude -p に委譲する。リポジトリのルートで起動するので .claude/settings.json の
#      PreToolUse / PostToolUse フックがそのまま効く（--bare / --settings / 権限スキップは使わない）
#   3. 検証コマンドを実行する
#      成功 → 変更ファイルを個別パスでステージし、チェックを - [x] に更新して1項目1コミット
#      失敗 → 失敗理由と出力を添えて同じ項目を再試行する（前回の変更は作業ツリーに残したまま）
#   4. 同じ項目で GOAL_LOOP_MAX_ATTEMPTS 回失敗したら、変更を残したまま停止して人間に判断を求める
#
# 起動前チェック（満たさなければ何もせず終了）:
#   - 計画ファイルが Git 管理下にあり、作業ツリーがクリーン（変更・未追跡ファイルなし）
#   - .claude/settings.json に PreToolUse(Bash) と PostToolUse(Edit|Write) のフックが登録され、
#     フックスクリプトが実行可能。どの設定ファイルにも disableAllHooks: true がない
# エージェント実行後のチェック:
#   - Bash を使ったのに PreToolUse、Edit/Write を使ったのに PostToolUse のフックイベントが
#     stream-json に1件も無ければ、フックが効いていないとみなして停止する
#   - エージェントがコミット・ステージをしていたら停止する。計画ファイルを書き換えていたら元に戻して失敗扱い
#   - files: 指定がある項目で範囲外のファイルが変わっていたら失敗扱い
#
# 環境変数:
#   GOAL_LOOP_MAX_ATTEMPTS   1項目あたりの最大試行回数（既定 3）
#   GOAL_LOOP_LOG_DIR        ログの出力先（既定 ${TMPDIR:-/tmp}/goal_loop/<リポジトリ名>-<日時>。リポジトリ外に限る）
#   GOAL_LOOP_AGENT_TIMEOUT  claude -p 1回の制限時間（秒、既定 1800）
#   GOAL_LOOP_MODEL          claude -p に渡す --model（未指定なら claude の既定）
#   GOAL_LOOP_COAUTHOR       コミット末尾の Co-Authored-By（既定 "Claude Opus 5.5 <noreply@anthropic.com>"）
#   GOAL_LOOP_CLAUDE_BIN     claude コマンド（既定 claude。テストで差し替えるためのもの）
#
# 終了コード: 0 = 全項目完了 / 1 = 引数・環境・起動前チェック・計画ファイル書式のエラー
#             2 = max_iterations に到達（未完了の項目あり） / 3 = 人間の判断が必要
set -euo pipefail

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() { echo "ERROR: $*" >&2; exit 1; }
log() { printf '[goal_loop %s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 1 ] && [ $# -le 2 ] || die "使い方: scripts/goal_loop.sh <plan.md> [max_iterations]（--help 参照）"

PLAN_ARG="$1"
MAX_ITER="${2:-10}"
MAX_ATTEMPTS="${GOAL_LOOP_MAX_ATTEMPTS:-3}"
AGENT_TIMEOUT="${GOAL_LOOP_AGENT_TIMEOUT:-1800}"
CLAUDE_BIN="${GOAL_LOOP_CLAUDE_BIN:-claude}"
COAUTHOR="${GOAL_LOOP_COAUTHOR:-Claude Opus 5.5 <noreply@anthropic.com>}"

is_uint "$MAX_ITER" && [ "$MAX_ITER" -ge 1 ] || die "max_iterations は 1 以上の整数: $MAX_ITER"
is_uint "$MAX_ATTEMPTS" && [ "$MAX_ATTEMPTS" -ge 1 ] || die "GOAL_LOOP_MAX_ATTEMPTS は 1 以上の整数: $MAX_ATTEMPTS"
is_uint "$AGENT_TIMEOUT" && [ "$AGENT_TIMEOUT" -ge 1 ] || die "GOAL_LOOP_AGENT_TIMEOUT は 1 以上の整数: $AGENT_TIMEOUT"

for c in git jq perl "$CLAUDE_BIN"; do
  command -v "$c" >/dev/null 2>&1 || die "$c が見つからない"
done

[ -f "$PLAN_ARG" ] || die "計画ファイルが無い: $PLAN_ARG"
PLAN_ABS="$(cd "$(dirname "$PLAN_ARG")" && pwd -P)/$(basename "$PLAN_ARG")"
ROOT="$(git -C "$(dirname "$PLAN_ABS")" rev-parse --show-toplevel 2>/dev/null)" || die "計画ファイルが Git リポジトリ内にない: $PLAN_ARG"
ROOT="$(cd "$ROOT" && pwd -P)"
cd "$ROOT"
PLAN_REL="${PLAN_ABS#"$ROOT"/}"
git ls-files --error-unmatch -- "$PLAN_REL" >/dev/null 2>&1 || die "計画ファイルが Git 管理下にない: $PLAN_REL"

# --- 起動前チェック ----------------------------------------------------------

check_hooks() {
  local s=".claude/settings.json" f cmd rel p
  [ -f "$s" ] || die "$s が無い（安全フックが未設定）"
  jq empty "$s" 2>/dev/null || die "$s が JSON として不正"
  jq -e '[.hooks.PreToolUse[]? | select((.matcher // "") | test("Bash"))] | length > 0' "$s" >/dev/null \
    || die "$s に PreToolUse(Bash) フックが登録されていない"
  jq -e '[.hooks.PostToolUse[]? | select((.matcher // "") | test("Edit") and test("Write"))] | length > 0' "$s" >/dev/null \
    || die "$s に PostToolUse(Edit|Write) フックが登録されていない"
  for f in "$s" .claude/settings.local.json "$HOME/.claude/settings.json"; do
    [ -f "$f" ] || continue
    if jq -e '.disableAllHooks == true' "$f" >/dev/null 2>&1; then
      die "$f で disableAllHooks が true（フックを無効化したままは実行しない）"
    fi
  done
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in
      '"$CLAUDE_PROJECT_DIR"/'*) rel="${cmd#\"\$CLAUDE_PROJECT_DIR\"/}"; p="$ROOT/${rel%% *}" ;;
      '$CLAUDE_PROJECT_DIR/'*) rel="${cmd#\$CLAUDE_PROJECT_DIR/}"; p="$ROOT/${rel%% *}" ;;
      *) p="${cmd%% *}" ;;
    esac
    case "$p" in
      */*) [ -x "$p" ] || die "フックスクリプトが無いか実行できない: $p" ;;
      *) command -v "$p" >/dev/null 2>&1 || die "フックのコマンドが見つからない: $p" ;;
    esac
  done < <(jq -r '(.hooks.PreToolUse[]?, .hooks.PostToolUse[]?) | .hooks[]? | .command // empty' "$s")
}

check_hooks
[ -z "$(git status --porcelain --untracked-files=all)" ] \
  || die "作業ツリーがクリーンでない（変更・未追跡ファイルをコミットか退避してから実行する）"

TS="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${GOAL_LOOP_LOG_DIR:-${TMPDIR:-/tmp}/goal_loop/$(basename "$ROOT")-$TS}"
mkdir -p "$LOG_DIR"
LOG_DIR="$(cd "$LOG_DIR" && pwd -P)"
case "$LOG_DIR/" in "$ROOT"/*) die "GOAL_LOOP_LOG_DIR はリポジトリ外を指定する: $LOG_DIR" ;; esac

# 実行エージェントに許さない Git の書き込み操作（コミットはオーケストレーターだけが行う）
DENY_TOOLS=(
  "Bash(git commit:*)" "Bash(git push:*)" "Bash(git add:*)" "Bash(git rm:*)" "Bash(git mv:*)"
  "Bash(git reset:*)" "Bash(git checkout:*)" "Bash(git switch:*)" "Bash(git restore:*)"
  "Bash(git stash:*)" "Bash(git clean:*)" "Bash(git rebase:*)" "Bash(git merge:*)"
  "Bash(git branch:*)" "Bash(git tag:*)" "Bash(git cherry-pick:*)" "Bash(git revert:*)"
  "Bash(git fetch:*)" "Bash(git pull:*)"
)

# --- 計画ファイルの読み書き ---------------------------------------------------

first_open_line() { grep -n -m1 -E '^- \[ \] ' "$PLAN_REL" | cut -d: -f1 || true; }

item_block() { # $1: 項目の行番号
  awk -v s="$1" '
    NR == s { print; next }
    NR > s { if ($0 ~ /^- \[[ xX]\] / || $0 ~ /^#+ /) exit; print }
  ' "$PLAN_REL"
}

meta() { # $1: キー。項目ブロックの <!-- key: 値 --> の最初の値
  awk -v k="$1" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line) }
    index(line, "<!-- " k ": ") == 1 && line ~ / -->$/ {
      v = substr(line, length(k) + 8); sub(/ -->$/, "", v); print v; exit
    }
  ' <<<"$BLOCK"
}

plan_status() { grep -E '^- \[[ xX]\] ' "$PLAN_REL" || true; }

mark_done() { # $1: 行番号
  local tmp
  tmp="$(mktemp "$LOG_DIR/plan.XXXXXX")"
  awk -v n="$1" 'NR == n { sub(/^- \[ \] /, "- [x] ") } { print }' "$PLAN_REL" > "$tmp"
  cat "$tmp" > "$PLAN_REL"
  rm -f "$tmp"
}

# --- 実行 --------------------------------------------------------------------

summary() {
  echo
  echo "=== 計画ファイルの状態（${PLAN_REL}） ==="
  plan_status
  echo
  echo "=== このループで作成したコミット（$BASELINE..HEAD） ==="
  git log --oneline "$BASELINE..HEAD"
  echo
  echo "ログ: $LOG_DIR"
}

need_human() {
  echo
  echo "STOP（人間の判断が必要）: $*"
  summary
  exit 3
}

run_verify() { # $1: ログファイル。終了コードを VERIFY_RC に入れる
  VERIFY_RC=0
  bash -c "$VERIFY" > "$1" 2>&1 < /dev/null || VERIFY_RC=$?
  echo "----- 検証出力: $VERIFY -----"
  cat "$1"
  echo "----- 検証終了コード: $VERIFY_RC -----"
}

jl() { # $1: jq フィルタ。stream-json（1行1 JSON）から抽出する
  jq -R -r "fromjson? | $1" "$JSONL"
}

run_agent() { # $1: プロンプト。終了コードを AGENT_RC に入れる
  local args=(-p "$1" --output-format stream-json --verbose --include-hook-events
    --permission-mode acceptEdits
    --allowedTools Read Edit Write Glob Grep Bash
    --disallowedTools "${DENY_TOOLS[@]}"
    --no-session-persistence)
  [ -z "${GOAL_LOOP_MODEL:-}" ] || args+=(--model "$GOAL_LOOP_MODEL")
  AGENT_RC=0
  perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$AGENT_TIMEOUT" "$CLAUDE_BIN" "${args[@]}" \
    > "$JSONL" 2> "$JSONL.stderr" < /dev/null || AGENT_RC=$?
}

build_prompt() {
  local files_text="${FILES:-指定なし（ただしこの項目に必要な最小限に限る）}"
  cat <<EOF
あなたは scripts/goal_loop.sh から作業を委譲された実行エージェントです。
リポジトリ ${ROOT} で、計画ファイル ${PLAN_REL} の次の1項目だけを実施してください。

## 項目
${TITLE}

${DESC}

## 完了判定
作業後、オーケストレーターがリポジトリのルートで次のコマンドを実行し、終了コード 0 なら成功と判定します。

    ${VERIFY}

終える前に自分でも実行し、成功することを確かめてください。検証用のスクリプトは変更しないでください。

## 制約
- 変更してよいファイル: ${files_text}
- 計画ファイル ${PLAN_REL} は編集しない（チェックはオーケストレーターが更新する）
- git commit / add / push などの Git の書き込み操作はしない（コミットはオーケストレーターが行う）
- PreToolUse / PostToolUse フックの拒否・警告には従い、回避や無効化をしない
- リポジトリの CLAUDE.md / AGENTS.md のルールに従い、この項目と関係のない変更はしない
- 最後に、変更したファイルと検証コマンドの結果を短く報告する
EOF
  if [ -n "$FEEDBACK" ]; then
    cat <<EOF

## 前回の試行（${PREV_ATTEMPT}/${MAX_ATTEMPTS}）は失敗した
前回の変更は作業ツリーに残っている。下の内容を踏まえて修正すること。

${FEEDBACK}
EOF
  fi
}

collect_changed() {
  CHANGED=()
  local ent st p old
  while IFS= read -r -d '' ent; do
    st="${ent:0:2}"
    p="${ent:3}"
    case "$st" in
      R*|C*) IFS= read -r -d '' old || true; CHANGED+=("$old") ;;
    esac
    [ "$p" = "$PLAN_REL" ] || CHANGED+=("$p")
  done < <(git status --porcelain=v1 -z --untracked-files=all)
}

in_scope() { # $1: パス
  local pat
  [ ${#FILE_PATS[@]} -gt 0 ] || return 0
  for pat in "${FILE_PATS[@]}"; do
    # shellcheck disable=SC2053  # pat は glob として照合する
    [[ "$1" == $pat ]] && return 0
  done
  return 1
}

commit_item() { # 成功時 0。失敗時は FAIL_REASON / FAIL_LOG を設定して 1
  local p msg clog rc=0
  for p in "${CHANGED[@]}"; do
    git add -- "$p"
  done
  mark_done "$LINE"
  git add -- "$PLAN_REL"
  echo "----- git diff --cached --stat -----"
  git diff --cached --stat
  msg="$LOG_DIR/$TAG.commit_msg.txt"
  clog="$LOG_DIR/$TAG.commit.log"
  {
    echo "$COMMIT_SUBJECT"
    echo
    echo "scripts/goal_loop.sh による自動実行（計画: $PLAN_REL L${LINE}、試行 $ATTEMPT/${MAX_ATTEMPTS}）"
    echo "検証: $VERIFY"
    echo
    echo "Co-Authored-By: $COAUTHOR"
  } > "$msg"
  git commit -q -F "$msg" > "$clog" 2>&1 || rc=$?
  cat "$clog"
  if [ "$rc" -ne 0 ]; then
    git reset -q -- "${CHANGED[@]}" "$PLAN_REL"
    cat "$PLAN_SNAPSHOT" > "$PLAN_REL"
    FAIL_REASON="検証は成功したが git commit が失敗した（終了コード ${rc}。コミットフックの出力を確認すること）"
    FAIL_LOG="$clog"
    return 1
  fi
  echo "----- git log -1 --stat -----"
  git log -1 --stat
  return 0
}

BASELINE="$(git rev-parse --short HEAD)"
ITER=0
log "開始: plan=$PLAN_REL root=$ROOT baseline=$BASELINE max_iterations=$MAX_ITER max_attempts=$MAX_ATTEMPTS"
log "ログ: $LOG_DIR"
echo "=== 開始時の計画ファイル ==="
plan_status

while :; do
  LINE="$(first_open_line)"
  if [ -z "$LINE" ]; then
    log "全項目完了"
    summary
    exit 0
  fi
  if [ "$ITER" -ge "$MAX_ITER" ]; then
    log "max_iterations（${MAX_ITER}）に到達した。未完了の項目が残っている"
    summary
    exit 2
  fi

  BLOCK="$(item_block "$LINE")"
  TITLE="$(sed -n '1s/^- \[ \] //p' <<<"$BLOCK")"
  DESC="$(sed '1d' <<<"$BLOCK" | grep -v -E '^[[:space:]]*<!-- (verify|commit|files): .* -->[[:space:]]*$' || true)"
  VERIFY="$(meta verify)"
  COMMIT_SUBJECT="$(meta commit)"
  FILES="$(meta files)"
  FILE_PATS=()
  [ -z "$FILES" ] || read -r -a FILE_PATS <<<"$FILES"
  [ -n "$VERIFY" ] || die "$PLAN_REL L${LINE}「${TITLE}」に <!-- verify: ... --> が無い"
  [ -n "$COMMIT_SUBJECT" ] || die "$PLAN_REL L${LINE}「${TITLE}」に <!-- commit: ... --> が無い"

  echo
  log "===== 項目 L$LINE: $TITLE ====="
  log "検証コマンド: $VERIFY"
  log "変更してよいファイル: ${FILES:-指定なし}"
  log "作業前の検証（失敗することを確認する）"
  run_verify "$LOG_DIR/L${LINE}_pre_verify.log"
  if [ "$VERIFY_RC" -eq 0 ]; then
    need_human "L${LINE}「${TITLE}」は作業前に検証コマンドが既に成功している。検証として機能しないか、既に完了している"
  fi
  log "作業前の検証は失敗（想定どおり）"

  ATTEMPT=0
  FEEDBACK=""
  while :; do
    if [ "$ITER" -ge "$MAX_ITER" ]; then
      log "max_iterations（${MAX_ITER}）に到達した。L$LINE の途中の変更が作業ツリーに残っている"
      summary
      exit 2
    fi
    ITER=$((ITER + 1))
    ATTEMPT=$((ATTEMPT + 1))
    TAG="$(printf 'iter%02d_L%s_try%d' "$ITER" "$LINE" "$ATTEMPT")"
    JSONL="$LOG_DIR/$TAG.agent.jsonl"
    PROMPT_FILE="$LOG_DIR/$TAG.prompt.md"
    PLAN_SNAPSHOT="$LOG_DIR/$TAG.plan_before.md"
    cp "$PLAN_REL" "$PLAN_SNAPSHOT"
    HEAD_BEFORE="$(git rev-parse HEAD)"

    echo
    log "--- iteration $ITER/${MAX_ITER}（L$LINE 試行 $ATTEMPT/${MAX_ATTEMPTS}）: claude -p に委譲 ---"
    build_prompt > "$PROMPT_FILE"
    started="$(date +%s)"
    run_agent "$(cat "$PROMPT_FILE")"
    log "claude -p 終了: 終了コード ${AGENT_RC}、$(( $(date +%s) - started )) 秒"

    n_bash="$(jl 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash") | .name' | grep -c . || true)"
    n_edit="$(jl 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit")) | .name' | grep -c . || true)"
    n_pre="$(jl 'select(.type == "system" and .subtype == "hook_started" and .hook_event == "PreToolUse") | .hook_name' | grep -c . || true)"
    n_post="$(jl 'select(.type == "system" and .subtype == "hook_started" and .hook_event == "PostToolUse") | .hook_name' | grep -c . || true)"
    n_deny="$(jl 'select(.type == "result") | (.permission_denials // []) | length' | tail -n1)"
    log "ツール使用: Bash ${n_bash} 回 / Edit・Write ${n_edit} 回、フック発火: PreToolUse ${n_pre} 件 / PostToolUse ${n_post} 件、権限拒否 ${n_deny:-0} 件"
    echo "----- エージェントの最終報告 -----"
    jl 'select(.type == "result") | .result // empty'
    echo "----- ここまで（stream-json 全体: ${JSONL}） -----"
    if [ -s "$JSONL.stderr" ]; then
      echo "----- claude -p の stderr（末尾 20 行） -----"
      tail -n 20 "$JSONL.stderr"
    fi

    if [ "$n_bash" -gt 0 ] && [ "$n_pre" -eq 0 ]; then
      need_human "エージェントが Bash を ${n_bash} 回使ったのに PreToolUse フックが1件も発火していない（安全フックが効いていない可能性）"
    fi
    if [ "$n_edit" -gt 0 ] && [ "$n_post" -eq 0 ]; then
      need_human "エージェントが Edit/Write を ${n_edit} 回使ったのに PostToolUse フックが1件も発火していない（安全フックが効いていない可能性）"
    fi
    if [ "$(git rev-parse HEAD)" != "$HEAD_BEFORE" ] || ! git diff --cached --quiet; then
      need_human "エージェントがコミットまたはステージを行った（git log / git status を確認すること）"
    fi

    FAIL_REASON=""
    FAIL_LOG=""
    if ! cmp -s "$PLAN_REL" "$PLAN_SNAPSHOT"; then
      cat "$PLAN_SNAPSHOT" > "$PLAN_REL"
      FAIL_REASON="計画ファイル $PLAN_REL を変更した（オーケストレーターが元に戻した）"
    fi

    collect_changed
    echo "----- 変更ファイル -----"
    if [ ${#CHANGED[@]} -gt 0 ]; then printf '%s\n' "${CHANGED[@]}"; else echo "（なし）"; fi
    out_of_scope=()
    for p in ${CHANGED[@]+"${CHANGED[@]}"}; do
      in_scope "$p" || out_of_scope+=("$p")
    done
    if [ -z "$FAIL_REASON" ] && [ ${#out_of_scope[@]} -gt 0 ]; then
      FAIL_REASON="変更してよいファイル（${FILES}）の範囲外を変更した: ${out_of_scope[*]}"
    fi

    if [ -z "$FAIL_REASON" ]; then
      log "検証コマンドを実行"
      run_verify "$LOG_DIR/$TAG.verify.log"
      if [ "$VERIFY_RC" -eq 0 ]; then
        if [ ${#CHANGED[@]} -eq 0 ]; then
          need_human "L$LINE は変更なしで検証が成功した（作業前は失敗していたので、検証が不安定な可能性）"
        fi
        log "判定: 成功。コミットする"
        if commit_item; then
          log "L${LINE}「${TITLE}」完了（$(git rev-parse --short HEAD)）"
          break
        fi
      else
        FAIL_REASON="検証コマンドが失敗した（終了コード ${VERIFY_RC}）"
        FAIL_LOG="$LOG_DIR/$TAG.verify.log"
      fi
    fi

    log "判定: 失敗 — $FAIL_REASON"
    if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
      need_human "L${LINE}「${TITLE}」が最大試行回数（$MAX_ATTEMPTS 回）失敗した。最後の試行の変更は作業ツリーに残している"
    fi
    PREV_ATTEMPT="$ATTEMPT"
    FEEDBACK="理由: $FAIL_REASON"
    if [ -n "$FAIL_LOG" ]; then
      FEEDBACK="$FEEDBACK
----- 出力（末尾 80 行） -----
$(tail -n 80 "$FAIL_LOG")
----- ここまで -----"
    fi
  done
done
