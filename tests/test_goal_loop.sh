#!/usr/bin/env bash
# scripts/goal_loop.sh のテスト。
# 一時ディレクトリに計画ファイル・安全フック設定を持つ Git リポジトリを作り、claude の代わりに
# 偽エージェント（呼ばれるたびに actions.txt の n 行目を実行し、stream-json を出す）を使って
# 成功・再試行・最大試行回数での停止・max_iterations・起動前チェック・各種ガードを確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP="$SCRIPT_DIR/../scripts/goal_loop.sh"

[ -x "$LOOP" ] || { echo "Error: $LOOP が無いか実行権限がない" >&2; exit 1; }

TMP_DIR="$(mktemp -d /tmp/test-goal-loop-XXXXXX)"
TMP_DIR="$(cd "$TMP_DIR" && pwd -P)"
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME="$TMP_DIR/home"
mkdir -p "$HOME"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
ng() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# 偽エージェント。引数は claude -p と同じ形（-p <prompt> ...）で受け取る
FAKE="$TMP_DIR/fake-claude"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
set -u
n=$(( $(cat "$FAKE_STATE/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_STATE/count"
printf '%s' "$2" > "$FAKE_STATE/prompt_$n.txt"
printf '%s\n' "$@" > "$FAKE_STATE/args_$n.txt"
pwd -P > "$FAKE_STATE/cwd_$n.txt"
action="$(sed -n "${n}p" "$FAKE_STATE/actions.txt")"
[ -z "$action" ] || eval "$action" >&2
printf '%s\n' '{"type":"system","subtype":"init"}'
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}'
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{}}]}}'
if [ "${FAKE_NO_HOOKS:-0}" != 1 ]; then
  printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"PreToolUse","hook_name":"PreToolUse:Bash"}'
  printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"PostToolUse","hook_name":"PostToolUse:Edit"}'
fi
printf '%s\n' "{\"type\":\"result\",\"result\":\"fake attempt $n\",\"permission_denials\":[]}"
EOF
chmod +x "$FAKE"
export GOAL_LOOP_CLAUDE_BIN="$FAKE"

# $1: テスト名。$REPO に安全フック設定・検査スクリプト・空の計画ファイルを持つリポジトリを作る
setup_repo() {
  CASE_DIR="$TMP_DIR/$1"
  REPO="$CASE_DIR/repo"
  export FAKE_STATE="$CASE_DIR/state"
  export GOAL_LOOP_LOG_DIR="$CASE_DIR/logs"
  mkdir -p "$REPO/.claude/hooks" "$FAKE_STATE" "$CASE_DIR/githooks"
  : > "$FAKE_STATE/actions.txt"
  git -c init.defaultBranch=main init -q "$REPO"
  # グローバルのフック（~/.config/git-hooks）を巻き込まない
  git -C "$REPO" config core.hooksPath "$CASE_DIR/githooks"
  cat > "$REPO/.claude/settings.json" <<'EOF'
{"hooks":{
  "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre.sh"}]}],
  "PostToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post.sh"}]}]
}}
EOF
  printf '#!/bin/sh\nexit 0\n' > "$REPO/.claude/hooks/pre.sh"
  printf '#!/bin/sh\nexit 0\n' > "$REPO/.claude/hooks/post.sh"
  chmod +x "$REPO/.claude/hooks/pre.sh" "$REPO/.claude/hooks/post.sh"
  printf '#!/bin/sh\n[ "$(cat "$1" 2>/dev/null)" = ok ] || { echo "MISMATCH: $1 = $(cat "$1" 2>/dev/null)"; exit 1; }\n' > "$REPO/check.sh"
  printf '# plan\n' > "$REPO/PLAN.md"
}

add_item() { # $1: タイトル, $2: 対象ファイル, $3: 追加のメタ行（任意）
  {
    echo "- [ ] $1"
    echo "  $2 を ok にする。"
    echo "  <!-- verify: sh check.sh $2 -->"
    echo "  <!-- commit: feat: $1 -->"
    [ -z "${3:-}" ] || echo "  $3"
  } >> "$REPO/PLAN.md"
}

commit_fixture() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "chore: fixture"
}

actions() { printf '%s\n' "$@" > "$FAKE_STATE/actions.txt"; }

run_loop() { # 引数は goal_loop.sh にそのまま渡す。OUT と RC を設定する
  RC=0
  OUT="$(cd "$REPO" && "$LOOP" "$@" 2>&1)" || RC=$?
  printf '%s\n' "$OUT" > "$CASE_DIR/out.txt"
}

calls() { cat "$FAKE_STATE/count" 2>/dev/null || echo 0; }
n_commits() { git -C "$REPO" rev-list --count HEAD; }

expect_rc() { if [ "$RC" -eq "$1" ]; then ok "$2 (exit $RC)"; else ng "$2 | exit ${RC}（期待 $1）"; sed 's/^/    | /' "$CASE_DIR/out.txt" | tail -n 30; fi; }
expect_eq() { if [ "$1" = "$2" ]; then ok "$3"; else ng "$3 | '$1'（期待 '$2'）"; fi; }
expect_out() { if grep -qF -- "$1" <<<"$OUT"; then ok "$2"; else ng "$2 | 出力に '$1' がない"; fi; }
expect_file_has() { if grep -qF -- "$2" "$1"; then ok "$3"; else ng "$3 | $1 に '$2' がない"; fi; }
expect_file_lacks() { if grep -qF -- "$2" "$1"; then ng "$3 | $1 に '$2' がある"; else ok "$3"; fi; }

echo "=== 1. 2項目とも1回で成功 ==="
setup_repo t1
add_item "item A" a.txt
add_item "item B" b.txt
commit_fixture
actions "echo ok > a.txt" "echo ok > b.txt"
run_loop PLAN.md
expect_rc 0 "全項目完了で終了"
expect_eq "$(calls)" 2 "エージェントは2回呼ばれた"
expect_eq "$(grep -c '^- \[x\] ' "$REPO/PLAN.md")" 2 "2項目とも - [x]"
expect_eq "$(n_commits)" 3 "1項目1コミット（fixture + 2）"
expect_eq "$(git -C "$REPO" log -1 --format=%s)" "feat: item B" "コミット件名は commit: の値"
expect_eq "$(git -C "$REPO" show --name-only --format= HEAD~1 | LC_ALL=C sort | tr '\n' ' ')" "PLAN.md a.txt " "1件目のコミットは a.txt と PLAN.md だけ"
expect_file_has "$FAKE_STATE/args_1.txt" "--include-hook-events" "stream-json にフックイベントを含める"
expect_file_has "$FAKE_STATE/args_1.txt" "acceptEdits" "権限モードは acceptEdits"
expect_file_has "$FAKE_STATE/args_1.txt" "Bash(git commit:*)" "エージェントの git commit を禁止"
expect_file_lacks "$FAKE_STATE/args_1.txt" "--bare" "--bare（フック無効）を使わない"
expect_file_lacks "$FAKE_STATE/args_1.txt" "--settings" "--settings で設定を差し替えない"
expect_file_lacks "$FAKE_STATE/args_1.txt" "dangerously" "権限スキップを使わない"
expect_eq "$(cat "$FAKE_STATE/cwd_1.txt")" "$(cd "$REPO" && pwd -P)" "エージェントはリポジトリのルートで起動する"
expect_file_has "$FAKE_STATE/prompt_1.txt" "item A" "プロンプトに項目のタイトル"
expect_file_has "$FAKE_STATE/prompt_1.txt" "sh check.sh a.txt" "プロンプトに検証コマンド"
expect_file_lacks "$FAKE_STATE/prompt_1.txt" "<!-- verify" "メタ行は説明に含めない"
expect_eq "$(git -C "$REPO" status --porcelain)" "" "完了後の作業ツリーはクリーン"
expect_out "フック発火: PreToolUse 1 件 / PostToolUse 1 件" "フック発火件数をログに出す"

echo "=== 2. 1回目失敗 → 失敗出力つきで再試行して成功 ==="
setup_repo t2
add_item "item A" a.txt
commit_fixture
actions "echo ng > a.txt" "echo ok > a.txt"
run_loop PLAN.md
expect_rc 0 "再試行で完了"
expect_eq "$(calls)" 2 "エージェントは2回呼ばれた"
expect_file_has "$FAKE_STATE/prompt_2.txt" "前回の試行（1/3）は失敗した" "再試行のプロンプトに失敗の通知"
expect_file_has "$FAKE_STATE/prompt_2.txt" "MISMATCH: a.txt = ng" "再試行のプロンプトに検証の失敗出力"
expect_file_lacks "$FAKE_STATE/prompt_1.txt" "前回の試行" "初回のプロンプトには失敗の通知がない"
expect_eq "$(n_commits)" 2 "コミットは1件だけ"

echo "=== 3. 最大試行回数で停止 ==="
setup_repo t3
add_item "item A" a.txt
commit_fixture
actions "echo ng > a.txt" "echo ng2 > a.txt" "echo ok > a.txt"
GOAL_LOOP_MAX_ATTEMPTS=2 run_loop PLAN.md
expect_rc 3 "人間の判断待ちで停止"
expect_eq "$(calls)" 2 "最大試行回数（2）を超えて呼ばない"
expect_out "STOP（人間の判断が必要）" "停止理由を出す"
expect_eq "$(grep -c '^- \[ \] ' "$REPO/PLAN.md")" 1 "項目は未完了のまま"
expect_eq "$(n_commits)" 1 "コミットしない"
expect_eq "$(cat "$REPO/a.txt")" "ng2" "最後の試行の変更を作業ツリーに残す"

echo "=== 4. max_iterations で停止 ==="
setup_repo t4
add_item "item A" a.txt
add_item "item B" b.txt
commit_fixture
actions "echo ok > a.txt" "echo ok > b.txt"
run_loop PLAN.md 1
expect_rc 2 "max_iterations 到達で終了"
expect_eq "$(calls)" 1 "エージェントは1回だけ"
expect_eq "$(grep -c '^- \[x\] ' "$REPO/PLAN.md")" 1 "1項目だけ完了"

echo "=== 5. 作業前に検証が成功する項目は委譲せず停止 ==="
setup_repo t5
add_item "item A" a.txt
echo ok > "$REPO/a.txt"
commit_fixture
run_loop PLAN.md
expect_rc 3 "人間の判断待ちで停止"
expect_eq "$(calls)" 0 "エージェントを呼ばない"
expect_out "作業前に検証コマンドが既に成功している" "理由を出す"

echo "=== 6. 起動前チェック ==="
setup_repo t6a
add_item "item A" a.txt
jq 'del(.hooks.PostToolUse)' "$REPO/.claude/settings.json" > "$CASE_DIR/s.json" && mv "$CASE_DIR/s.json" "$REPO/.claude/settings.json"
commit_fixture
run_loop PLAN.md
expect_rc 1 "PostToolUse フック未登録なら起動しない"
expect_eq "$(calls)" 0 "エージェントを呼ばない（PostToolUse なし）"

setup_repo t6b
add_item "item A" a.txt
commit_fixture
mkdir -p "$HOME/.claude"
echo '{"disableAllHooks": true}' > "$HOME/.claude/settings.json"
run_loop PLAN.md
rm -f "$HOME/.claude/settings.json"
expect_rc 1 "disableAllHooks が true なら起動しない"
expect_out "disableAllHooks" "理由を出す（disableAllHooks）"
expect_eq "$(calls)" 0 "エージェントを呼ばない（disableAllHooks）"

setup_repo t6c
add_item "item A" a.txt
commit_fixture
git -C "$REPO" config core.fileMode false   # 実行権限の変更で作業ツリーが dirty 扱いにならないようにする
chmod -x "$REPO/.claude/hooks/pre.sh"
run_loop PLAN.md
expect_rc 1 "フックスクリプトが実行できなければ起動しない"
expect_out "フックスクリプトが無いか実行できない" "理由を出す（フックスクリプト）"

setup_repo t6d
add_item "item A" a.txt
commit_fixture
echo dirty > "$REPO/untracked.txt"
run_loop PLAN.md
expect_rc 1 "作業ツリーがクリーンでなければ起動しない"
expect_eq "$(calls)" 0 "エージェントを呼ばない（dirty）"

setup_repo t6e
printf -- '- [ ] no verify\n  <!-- commit: feat: x -->\n' >> "$REPO/PLAN.md"
commit_fixture
run_loop PLAN.md
expect_rc 1 "verify: の無い項目は書式エラー"

setup_repo t6f
add_item "item A" a.txt
commit_fixture
GOAL_LOOP_LOG_DIR="$REPO/logs" run_loop PLAN.md
expect_rc 1 "ログ出力先がリポジトリ内なら起動しない"

echo "=== 7. files: の範囲外を変更したら失敗扱い ==="
setup_repo t7
add_item "item A" a.txt "<!-- files: a.txt -->"
commit_fixture
actions "echo ok > a.txt; echo x > other.txt" "rm other.txt"
run_loop PLAN.md
expect_rc 0 "範囲外を戻した再試行で完了"
expect_eq "$(calls)" 2 "エージェントは2回呼ばれた"
expect_file_has "$FAKE_STATE/prompt_2.txt" "範囲外を変更した: other.txt" "再試行のプロンプトに範囲外のファイル名"
expect_eq "$(git -C "$REPO" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' ')" "PLAN.md a.txt " "範囲外のファイルはコミットしない"

echo "=== 8. エージェントが計画ファイルを変えたら元に戻して失敗扱い ==="
setup_repo t8
add_item "item A" a.txt
commit_fixture
actions "echo ok > a.txt; echo '- [x] junk' >> PLAN.md" ":"
run_loop PLAN.md
expect_rc 0 "再試行で完了"
expect_eq "$(calls)" 2 "エージェントは2回呼ばれた"
expect_file_lacks "$REPO/PLAN.md" "junk" "エージェントの書き込みは残らない"
expect_file_has "$FAKE_STATE/prompt_2.txt" "計画ファイル PLAN.md を変更した" "再試行のプロンプトに理由"

echo "=== 9. フックが発火していなければ停止 ==="
setup_repo t9
add_item "item A" a.txt
commit_fixture
actions "echo ok > a.txt"
FAKE_NO_HOOKS=1 run_loop PLAN.md
expect_rc 3 "人間の判断待ちで停止"
expect_out "PreToolUse フックが1件も発火していない" "理由を出す"
expect_eq "$(n_commits)" 1 "コミットしない"

echo "=== 10. コミットフックの拒否は失敗扱いで再試行 ==="
setup_repo t10
add_item "item A" a.txt
commit_fixture
printf '#!/bin/sh\nif [ ! -f "%s" ]; then touch "%s"; echo "REJECTED BY HOOK" >&2; exit 1; fi\n' \
  "$CASE_DIR/flag" "$CASE_DIR/flag" > "$CASE_DIR/githooks/pre-commit"
chmod +x "$CASE_DIR/githooks/pre-commit"
actions "echo ok > a.txt" ":"
run_loop PLAN.md
expect_rc 0 "2回目のコミットで完了"
expect_eq "$(calls)" 2 "エージェントは2回呼ばれた"
expect_file_has "$FAKE_STATE/prompt_2.txt" "REJECTED BY HOOK" "再試行のプロンプトにフックの出力"
expect_eq "$(grep -c '^- \[x\] ' "$REPO/PLAN.md")" 1 "チェックは1回だけ付く"
expect_eq "$(n_commits)" 2 "コミットは1件だけ"

echo "=== 11. エージェントが自分でコミットしたら停止 ==="
setup_repo t11
add_item "item A" a.txt
commit_fixture
actions "echo ok > a.txt && git add a.txt && git commit -q -m sneaky"
run_loop PLAN.md
expect_rc 3 "人間の判断待ちで停止"
expect_out "コミットまたはステージを行った" "理由を出す"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
