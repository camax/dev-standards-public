#!/usr/bin/env bash
# PreToolUse(Bash) フック: 破壊的コマンドを実行前に拒否する。
#
# stdin で受け取る JSON の tool_input.command を検査し、危険なパターンを
# 検知したら permissionDecision=deny を stdout に出力する。
# 安全と判定した場合は何も出力せず exit 0 とし、通常の権限確認フローに委ねる。
# "allow" は決して出力しない（既存の権限設定・ユーザー承認を迂回しない）。
# 判定不能（jq 不在・JSON 不正）の場合は拒否する。
#
# 検知対象:
#   - rm の再帰+強制削除（-rf / -fr / -r -f / --recursive --force 等。対象を問わない）
#   - rm の再帰削除で、カレントディレクトリ外・全体を指す対象（/ ~ .. $VAR * .）
#   - git push の強制（--force / -f / --force-with-lease / +refspec）
#   - git reset --hard
#   - git add の一括ステージング（. / -A / --all / -u / ワイルドカード）
#   - git commit -a / -am / --all
#
# 判定は文字列解析のみで、検査対象のコマンドを実行することはない。
# 引用符内（コミットメッセージ等）も検査対象に含めるため誤検知は起こりうるが、
# 疑わしきは拒否する（安全側に倒す）設計とする。

set -u

PREFIX="[block-destructive]"
REASONS=""

deny() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$PREFIX $1" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  else
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[block-destructive] jq が見つからないためコマンドを検査できず拒否"}}'
  fi
  exit 0
}

add_reason() {
  case "$REASONS" in
    *"$1"*) ;;
    *) REASONS="${REASONS:+$REASONS / }$1" ;;
  esac
}

# rm -r の対象がカレントディレクトリ外・全体を指すか
is_risky_rm_target() {
  case "$1" in
    /*|\~*|*..*|.|./|\$*|*\**) return 0 ;;
  esac
  return 1
}

check_rm() {
  local i=0 n=${#TOKENS[@]} t in_rm=0 rec=0 force=0 risky=0
  while [ $i -lt $n ]; do
    t="${TOKENS[$i]}"
    i=$((i + 1))
    if [ $in_rm -eq 0 ]; then
      case "$t" in rm|*/rm) in_rm=1 ;; esac
      continue
    fi
    case "$t" in
      --recursive) rec=1 ;;
      --force) force=1 ;;
      --*) ;;
      -*)
        case "$t" in *[rR]*) rec=1 ;; esac
        case "$t" in *f*) force=1 ;; esac
        ;;
      *) is_risky_rm_target "$t" && risky=1 ;;
    esac
  done
  [ $in_rm -eq 1 ] || return 0
  if [ $rec -eq 1 ] && [ $force -eq 1 ]; then
    add_reason "rm -rf（再帰+強制削除）を検知: 広範・不可逆な削除のため拒否。必要ならユーザーが手動で実行すること"
  elif [ $rec -eq 1 ] && [ $risky -eq 1 ]; then
    add_reason "rm -r でカレントディレクトリ外・全体を指す対象（絶対パス / ~ / .. / 変数 / ワイルドカード / .）を検知: 広範な削除のため拒否"
  fi
}

# commit のショートオプション群（-am 等）に -a が含まれるか。
# -m / -F / -c / -C / -t 以降の文字はその引数なので見ない。
commit_short_has_a() {
  local s="${1#-}" c
  while [ -n "$s" ]; do
    c="${s%"${s#?}"}"
    s="${s#?}"
    case "$c" in
      a) return 0 ;;
      m|F|c|C|t) return 1 ;;
    esac
  done
  return 1
}

# TOKENS[$1] が git であるとき、そのサブコマンドと引数を検査する
check_git_at() {
  local i=$(($1 + 1)) n=${#TOKENS[@]} t sub=""
  while [ $i -lt $n ]; do
    t="${TOKENS[$i]}"
    case "$t" in
      -C|-c|--git-dir|--work-tree|--namespace|--config-env) i=$((i + 2)); continue ;;
      -*) i=$((i + 1)); continue ;;
    esac
    sub="$t"
    i=$((i + 1))
    break
  done

  while [ $i -lt $n ]; do
    t="${TOKENS[$i]}"
    i=$((i + 1))
    case "$sub" in
      push)
        case "$t" in
          --force|--force=*|--force-with-lease|--force-with-lease=*|--force-if-includes|+*)
            add_reason "git push の強制オプション（--force / -f / --force-with-lease / +refspec）を検知: リモート履歴を破壊するため拒否" ;;
          --*) ;;
          -*)
            case "$t" in *f*)
              add_reason "git push の強制オプション（--force / -f / --force-with-lease / +refspec）を検知: リモート履歴を破壊するため拒否" ;;
            esac
            ;;
        esac
        ;;
      reset)
        case "$t" in --hard)
          add_reason "git reset --hard を検知: 未コミットの変更を不可逆に破棄するため拒否" ;;
        esac
        ;;
      add)
        case "$t" in
          .|./|..|../|:/|:/*|*\**|-A|--all|-u|--update|--no-ignore-removal)
            add_reason "git add の一括ステージング（. / -A / --all / -u / ワイルドカード）を検知: 個別パス指定ルール（rules/git_safety.md 2.7）違反のため拒否" ;;
          --*) ;;
          -*)
            case "$t" in *[Au]*)
              add_reason "git add の一括ステージング（. / -A / --all / -u / ワイルドカード）を検知: 個別パス指定ルール（rules/git_safety.md 2.7）違反のため拒否" ;;
            esac
            ;;
        esac
        ;;
      commit)
        case "$t" in
          --all)
            add_reason "git commit -a / -am / --all を検知: 個別パス指定ルール（rules/git_safety.md 2.7）違反のため拒否" ;;
          --*) ;;
          -*)
            if commit_short_has_a "$t"; then
              add_reason "git commit -a / -am / --all を検知: 個別パス指定ルール（rules/git_safety.md 2.7）違反のため拒否"
            fi
            ;;
        esac
        ;;
      *) return 0 ;;
    esac
  done
}

check_git() {
  local i=0 n=${#TOKENS[@]}
  while [ $i -lt $n ]; do
    case "${TOKENS[$i]}" in git|*/git) check_git_at "$i" ;; esac
    i=$((i + 1))
  done
}

command -v jq >/dev/null 2>&1 || deny "jq が見つからないためコマンドを検査できず拒否"

INPUT="$(cat)"
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || deny "フック入力の JSON を解析できないため拒否"

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // "" | if type == "string" then . else tostring end' 2>/dev/null)" \
  || deny "tool_input.command を取得できないため拒否"

[ -n "$CMD" ] || exit 0

# 正規化: 改行をコマンド区切りに揃え、引用符とバックスラッシュを除去し
# （bash -c '...' や \rm も検査できるようにする）、区切り文字で 1 行 1 コマンドに分割する
NORM="$(printf '%s\n' "$CMD" \
  | tr '\r\n' ';;' \
  | sed -e "s/[\"'\\\\]//g" \
  | tr ';&|(){}`' '\n')"

while IFS= read -r SEG || [ -n "$SEG" ]; do
  read -r -a TOKENS <<< "$SEG"
  [ ${#TOKENS[@]} -gt 0 ] || continue
  check_rm
  check_git
done <<< "$NORM"

[ -z "$REASONS" ] || deny "$REASONS"
exit 0
