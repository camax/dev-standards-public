#!/usr/bin/env bash
# dev-standards リポジトリ自身の状態劣化を検知し、Markdown レポートを出力する定期チェック。
# 検知のみを行い、ファイル・ブランチ・設定には一切変更を加えない（git fetch も行わない）。
#
# 検知項目:
#   1. スキル frontmatter（phase1 基準: name は snake_case でディレクトリ名と一致、
#      description は日本語・明示トリガー「〜と言及したら必ず使用すること」・200〜300字）
#   2. 逐語重複ブロック（空行を除く連続 N 行が M ファイル以上に存在。既定 N=5, M=3。
#      P-10 の「環境乖離」ブロックは空行込み7行・空行抜き5行で、N=7 では検知できなかったため 5 とした）
#   3. .bak / .orig 等の残骸ファイル
#   4. 長期間更新のないリモートブランチ（リモート追跡ブランチの最終コミット日で判定）
#   5. 過去に削除した定型句の再出現
#   6. 参考: skills/README.md の索引とスキル実体の不整合
#
# 使い方:
#   scripts/repo_checkup.sh [--repo DIR] [--output FILE] [--stale-days N]
#                           [--dup-lines N] [--dup-files N] [--no-remote] [--fail-on-findings]
#   --output はリポジトリ外を指定すること（リポジトリ内に置くと次回の定型句検知に掛かる）。
#
# 終了コード: 0 = 正常終了（検知の有無を問わない） / 1 = --fail-on-findings 指定時に検知あり / 2 = 引数・環境エラー
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO=""
OUTPUT=""
STALE_DAYS=30
DUP_LINES=5
DUP_FILES=3
CHECK_REMOTE=1
FAIL_ON_FINDINGS=0

# 過去の改修（phase1〜3）で削除した文言。再出現したら検知する
BANNED_PHRASES=(
  "改修前には必ず"                                  # P-8: description 末尾の定型句
  "【トリガー："                                    # P-8: 旧 description 形式
  "職人品質"                                        # P-8: 起動条件ではない自己評価
  "【重要】環境乖離・異常検知プロトコル"            # P-10: git_safety.md 2.8 の逐語コピー見出し
  "本スキルの実行にあたり、ローカルリポジトリ"      # P-10: 同ブロックの本文
  "5分おき実況"                                     # P-7: 存在しないプロトコルへの言及
  "claps push"                                      # P-7: typo
)

# 定型句検知から除外するパス（git pathspec）。監査記録は削除済み文言を引用しているため除く
BANNED_EXCLUDES=(
  ":(exclude,glob)docs/claude_agents_md_audit_*.md"
  ":(exclude)scripts/repo_checkup.sh"
  ":(exclude)tests/test_repo_checkup.sh"
)

# 残骸とみなすファイル名パターン（find -name）
REMNANT_PATTERNS=(
  "*.bak" "*.orig" "*.rej" "*.swp" "*.swo" "*~" "*.tmp" "*.old"
  "*.backup" "*.backup_*" "*.BACKUP.*" "*.BASE.*" "*.LOCAL.*" "*.REMOTE.*" ".DS_Store"
)

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() { echo "Error: $*" >&2; exit 2; }

is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo に値がない"; REPO="$2"; shift 2 ;;
    --output) [ $# -ge 2 ] || die "--output に値がない"; OUTPUT="$2"; shift 2 ;;
    --stale-days) [ $# -ge 2 ] && is_uint "$2" || die "--stale-days は 0 以上の整数"; STALE_DAYS="$2"; shift 2 ;;
    --dup-lines) [ $# -ge 2 ] && is_uint "$2" && [ "$2" -ge 2 ] || die "--dup-lines は 2 以上の整数"; DUP_LINES="$2"; shift 2 ;;
    --dup-files) [ $# -ge 2 ] && is_uint "$2" && [ "$2" -ge 2 ] || die "--dup-files は 2 以上の整数"; DUP_FILES="$2"; shift 2 ;;
    --no-remote) CHECK_REMOTE=0; shift ;;
    --fail-on-findings) FAIL_ON_FINDINGS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "不明な引数: $1（--help 参照）" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git が見つからない"
command -v python3 >/dev/null 2>&1 || die "python3 が見つからない"

[ -n "$REPO" ] || REPO="$SCRIPT_DIR/.."
REPO="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || die "Git リポジトリではない: $REPO"
cd "$REPO"

# 以降の git コマンドはロックや index 更新を伴わないようにする
export GIT_OPTIONAL_LOCKS=0
export GIT_TERMINAL_PROMPT=0

NOW="$(date +%s)"

# --- 1. スキル frontmatter ---------------------------------------------------

# frontmatter（1行目が --- で、閉じの --- がある）を持つか
has_frontmatter() {
  awk 'NR==1 { if ($0 != "---") exit 1; next } $0 == "---" { found=1; exit } END { exit !found }' "$1"
}

# frontmatter から key の値を取り出す（前後の引用符は外さない）
fm_get() {
  awk -v k="$2" '
    NR==1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }
  ' "$1"
}

strip_quotes() {
  local v="$1"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# description の「文字数|日本語を含むか|英語タイトルで始まるか」を返す
desc_metrics() {
  python3 - "$1" <<'PY'
import re, sys
d = sys.argv[1]
ja = bool(re.search(r"[\u3040-\u30ff\u4e00-\u9fff]", d))
# 大文字始まりの英単語2語以上の直後が文末か区切り記号なら英語タイトルとみなす（「Kintone JSの…」は対象外）
en_title = bool(re.match(r"[A-Z][A-Za-z0-9&'-]*(\s+[A-Z&][A-Za-z0-9&'-]*)+\s*($|[:：\-–—（(「【|])", d))
print(f"{len(d)}|{int(ja)}|{int(en_title)}")
PY
}

SKILL_FILES="$(find skills -name SKILL.md -not -path '*/.git/*' 2>/dev/null | LC_ALL=C sort || true)"

C1_NG=0
C1_WARN=0
C1_BODY=""
c1_add() { C1_BODY="${C1_BODY}| \`$1\` | $2 | $3 |"$'\n'; }

while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#skills/}"
  skill_dir="$(dirname "$rel")"
  dir_name="$(basename "$skill_dir")"
  if [ "$skill_dir" = "$dir_name" ]; then
    expected="$dir_name"
  else
    # 入れ子スキルは「グループ名から _ops を除いたもの + _ + ディレクトリ名」（phase3 の規則）
    group="${skill_dir%%/*}"
    expected="${group%_ops}_${dir_name}"
  fi

  if ! has_frontmatter "$f"; then
    c1_add "$f" NG "frontmatter（--- で囲んだ name/description）が無い"
    C1_NG=$((C1_NG + 1))
    continue
  fi

  name="$(strip_quotes "$(fm_get "$f" name)")"
  desc="$(strip_quotes "$(fm_get "$f" description)")"

  if [ -z "$name" ]; then
    c1_add "$f" NG "name が無い"; C1_NG=$((C1_NG + 1))
  else
    case "$name" in
      *" "*) c1_add "$f" NG "name にスペースがある: \`$name\`"; C1_NG=$((C1_NG + 1)) ;;
    esac
    if ! LC_ALL=C grep -Eq '^[a-z0-9_]+$' <<<"$name"; then
      c1_add "$f" NG "name が snake_case（小文字英数字と _）でない: \`$name\`"; C1_NG=$((C1_NG + 1))
    elif [ "$name" != "$expected" ]; then
      c1_add "$f" NG "name \`$name\` が期待値 \`$expected\` と一致しない"; C1_NG=$((C1_NG + 1))
    fi
  fi

  if [ -z "$desc" ]; then
    c1_add "$f" NG "description が無い"; C1_NG=$((C1_NG + 1))
    continue
  fi

  IFS='|' read -r d_len d_ja d_en <<EOF
$(desc_metrics "$desc")
EOF
  if [ "$d_ja" = 0 ]; then
    c1_add "$f" NG "description に日本語が無い（英語のみ）"; C1_NG=$((C1_NG + 1))
  fi
  if [ "$d_en" = 1 ]; then
    c1_add "$f" NG "description が英語タイトルで始まる: \`$(printf '%s' "$desc" | cut -c1-40)…\`"; C1_NG=$((C1_NG + 1))
  fi
  case "$desc" in
    *"と言及したら必ず使用すること"*) ;;
    *) c1_add "$f" NG "明示トリガー「〜と言及したら必ず使用すること」が無い"; C1_NG=$((C1_NG + 1)) ;;
  esac
  case "$desc" in
    *"【トリガー"*) c1_add "$f" NG "旧形式「【トリガー：…】」が残っている"; C1_NG=$((C1_NG + 1)) ;;
  esac
  if [ "$d_len" -lt 200 ] || [ "$d_len" -gt 300 ]; then
    c1_add "$f" WARN "description が ${d_len} 字（基準 200〜300 字）"; C1_WARN=$((C1_WARN + 1))
  fi
done <<EOF
$SKILL_FILES
EOF

SKILL_COUNT="$(printf '%s\n' "$SKILL_FILES" | grep -c . || true)"

# --- 2. 逐語重複ブロック -----------------------------------------------------

# stdin はファイル一覧に使うため、Python コードは変数に読み込んで -c で渡す
read -r -d '' DUP_PY <<'PY' || true
import os, sys

min_lines, min_files = int(sys.argv[1]), int(sys.argv[2])
paths = [p for p in sys.stdin.buffer.read().decode("utf-8", "replace").split("\0") if p]

docs = {}
for p in paths:
    if not os.path.isfile(p) or os.path.islink(p):
        continue
    try:
        raw = open(p, "rb").read()
    except OSError:
        continue
    if b"\0" in raw:
        continue  # バイナリ
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        continue
    # 空行を除き、前後の空白を落とした行で比較する（行番号は元ファイルのもの）
    docs[p] = [(i, s.strip()) for i, s in enumerate(text.splitlines(), 1) if s.strip()]

# ウィンドウ（連続 min_lines 行）→ 出現位置
occ = {}
for p, lines in docs.items():
    for k in range(len(lines) - min_lines + 1):
        key = tuple(s for _, s in lines[k:k + min_lines])
        occ.setdefault(key, []).append((p, k))

dup_keys = {key for key, locs in occ.items() if len({p for p, _ in locs}) >= min_files}

# ファイルごとに、重複ウィンドウが連続する区間を1ブロックにまとめる
runs = []  # (path, start_idx, end_idx, keys)
for p, lines in docs.items():
    cur = None
    for k in range(len(lines) - min_lines + 1):
        key = tuple(s for _, s in lines[k:k + min_lines])
        if key in dup_keys:
            if cur and cur[2] == k - 1:
                cur[2] = k
                cur[3].add(key)
            else:
                cur = [p, k, k, {key}]
                runs.append(cur)
        else:
            cur = None

# 共通のウィンドウを持つブロック同士を同じクラスタにまとめる（union-find）
parent = list(range(len(runs)))
def find(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i
first_run = {}
for i, r in enumerate(runs):
    for key in r[3]:
        if key in first_run:
            parent[find(i)] = find(first_run[key])
        else:
            first_run[key] = i

clusters = {}
for i in range(len(runs)):
    clusters.setdefault(find(i), []).append(runs[i])

result = []
for members in clusters.values():
    files = sorted({m[0] for m in members})
    if len(files) < min_files:
        continue
    result.append((files, members))
result.sort(key=lambda c: (-len(c[0]), c[0]))

print(len(result))
for n, (files, members) in enumerate(result, 1):
    first = min(members, key=lambda m: (m[0], m[1]))
    lines = docs[first[0]]
    block = [s for _, s in lines[first[1]:first[2] + min_lines]]
    print(f"### 2-{n}. {len(files)} ファイルに重複（{first[0]} では {len(block)} 行）")
    print()
    for m in sorted(members, key=lambda m: (m[0], m[1])):
        ls = docs[m[0]]
        print(f"- `{m[0]}` L{ls[m[1]][0]}–{ls[m[2] + min_lines - 1][0]}")
    print()
    print("先頭3行:")
    print()
    print("```text")
    for s in block[:3]:
        print(s)
    print("```")
    print()
PY
DUP_OUT="$(git ls-files -z -co --exclude-standard | python3 -c "$DUP_PY" "$DUP_LINES" "$DUP_FILES")"
# 1行目が件数、2行目以降が本文（パイプで head すると pipefail 下で SIGPIPE になるため展開で分ける）
C2_COUNT="${DUP_OUT%%$'\n'*}"
C2_BODY=""
case "$DUP_OUT" in *$'\n'*) C2_BODY="${DUP_OUT#*$'\n'}" ;; esac
is_uint "$C2_COUNT" || die "重複検知の出力が不正: $C2_COUNT"

# --- 3. 残骸ファイル ---------------------------------------------------------

FIND_ARGS=()
for pat in "${REMNANT_PATTERNS[@]}"; do
  [ ${#FIND_ARGS[@]} -eq 0 ] || FIND_ARGS+=(-o)
  FIND_ARGS+=(-name "$pat")
done
REMNANTS="$(find . -path ./.git -prune -o -type f \( "${FIND_ARGS[@]}" \) -print 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort || true)"

C3_COUNT=0
C3_BODY=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    state="Git 管理下"
  elif git check-ignore -q -- "$f" 2>/dev/null; then
    state="未追跡（.gitignore 対象）"
  else
    state="未追跡"
  fi
  C3_BODY="${C3_BODY}| \`$f\` | $state |"$'\n'
  C3_COUNT=$((C3_COUNT + 1))
done <<EOF
$REMNANTS
EOF

# --- 4. リモートブランチ -----------------------------------------------------

DEFAULT_REF="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -z "$DEFAULT_REF" ] && git show-ref -q --verify refs/remotes/origin/main; then
  DEFAULT_REF="origin/main"
fi

# 最後に fetch した時刻（リモート追跡ブランチの鮮度の目安）
FETCH_INFO="記録なし"
if [ -f "$(git rev-parse --git-dir)/FETCH_HEAD" ]; then
  fh="$(git rev-parse --git-dir)/FETCH_HEAD"
  # [2026-10-15 FIX] GNU stat の -f 失敗時の標準出力を日時の数値に混入させない。
  if ! fetch_epoch="$(stat -f %m "$fh" 2>/dev/null)"; then
    fetch_epoch="$(stat -c %Y "$fh" 2>/dev/null || echo "")"
  fi
  if is_uint "$fetch_epoch"; then
    FETCH_INFO="$(date -r "$fetch_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$fetch_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$fetch_epoch")（$(( (NOW - fetch_epoch) / 86400 )) 日前）"
  fi
fi

# 読み取り専用の ls-remote で、リモートに今もあるブランチ名を取得する
REMOTE_HEADS=""
REMOTE_STATUS="未確認（--no-remote）"
if [ "$CHECK_REMOTE" -eq 1 ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    if ls_out="$(git ls-remote --heads origin 2>/dev/null)"; then
      REMOTE_HEADS="$(printf '%s\n' "$ls_out" | awk '{ sub("^refs/heads/", "", $2); print $2 }')"
      REMOTE_STATUS="git ls-remote --heads origin で確認済み"
    else
      REMOTE_STATUS="git ls-remote に失敗（オフライン等）。存在確認は未実施"
      CHECK_REMOTE=0
    fi
  else
    REMOTE_STATUS="origin が未設定"
    CHECK_REMOTE=0
  fi
fi

C4_COUNT=0
C4_BODY=""
BRANCH_LINES="$(git for-each-ref --format='%(refname:short)|%(committerdate:unix)|%(committerdate:short)|%(objectname:short)' refs/remotes 2>/dev/null || true)"
while IFS='|' read -r ref cdate cshort sha; do
  [ -n "$ref" ] || continue
  case "$ref" in */HEAD|origin) continue ;; esac
  [ "$ref" != "$DEFAULT_REF" ] || continue

  age=$(( (NOW - cdate) / 86400 ))
  merged="—"
  ab="—"
  if [ -n "$DEFAULT_REF" ]; then
    if git merge-base --is-ancestor "$ref" "$DEFAULT_REF" 2>/dev/null; then merged="済"; else merged="未"; fi
    ab="$(git rev-list --left-right --count "$DEFAULT_REF...$ref" 2>/dev/null | awk '{ print "+" $2 " / -" $1 }')"
  fi

  verdict=""
  if [ "$age" -ge "$STALE_DAYS" ]; then
    verdict="${STALE_DAYS} 日以上更新なし"
  fi
  on_remote="—"
  if [ "$CHECK_REMOTE" -eq 1 ]; then
    short="${ref#*/}"
    if grep -qxF "$short" <<<"$REMOTE_HEADS"; then
      on_remote="あり"
    else
      on_remote="なし"
      verdict="${verdict:+$verdict / }リモートに存在しない（追跡ブランチのみ残存）"
    fi
  fi
  if [ -n "$verdict" ]; then
    C4_COUNT=$((C4_COUNT + 1))
  else
    verdict="—"
  fi
  C4_BODY="${C4_BODY}| \`$ref\` | ${cshort}（${age} 日前） | \`$sha\` | $merged | $ab | $on_remote | $verdict |"$'\n'
done <<EOF
$BRANCH_LINES
EOF

# --- 5. 削除済み定型句の再出現 -----------------------------------------------

C5_COUNT=0
C5_BODY=""
for phrase in "${BANNED_PHRASES[@]}"; do
  hits="$(git grep --untracked -n -I -F -e "$phrase" -- . "${BANNED_EXCLUDES[@]}" 2>/dev/null || true)"
  [ -n "$hits" ] || continue
  n="$(printf '%s\n' "$hits" | grep -c .)"
  C5_COUNT=$((C5_COUNT + n))
  C5_BODY="${C5_BODY}#### 「${phrase}」（${n} 件）"$'\n\n```text\n'"$(printf '%s\n' "$hits" | cut -c1-200)"$'\n```\n\n'
done

# --- 6. 参考: スキル索引の不整合 ---------------------------------------------

C6_COUNT=0
C6_BODY=""
README="skills/README.md"
if [ -f "$README" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#skills/}"
    if ! grep -qF "](./$rel)" "$README"; then
      C6_BODY="${C6_BODY}- 索引に未掲載: \`$f\`"$'\n'
      C6_COUNT=$((C6_COUNT + 1))
    fi
  done <<EOF
$SKILL_FILES
EOF
  LINKS="$(grep -oE '\]\(\./[^)]*SKILL\.md\)' "$README" | sed -E 's/^\]\(\.\///; s/\)$//' | LC_ALL=C sort -u || true)"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    if [ ! -f "skills/$l" ]; then
      C6_BODY="${C6_BODY}- 索引のリンク切れ: \`skills/$l\`"$'\n'
      C6_COUNT=$((C6_COUNT + 1))
    fi
  done <<EOF
$LINKS
EOF
else
  C6_BODY="- \`$README\` が存在しない"$'\n'
  C6_COUNT=1
fi

# --- レポート出力 ------------------------------------------------------------

TOTAL=$((C1_NG + C1_WARN + C2_COUNT + C3_COUNT + C4_COUNT + C5_COUNT + C6_COUNT))
HEAD_INFO="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') @ $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
DIRTY="$(git status --porcelain 2>/dev/null | grep -c . || true)"

emit_report() {
  echo "# dev-standards リポジトリ定期チェック レポート"
  echo
  echo "- 実行日時: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- 対象: \`$REPO\`（${HEAD_INFO}、未コミットの変更 ${DIRTY} 件）"
  echo "- 閾値: 重複 = 空行を除く連続 ${DUP_LINES} 行が ${DUP_FILES} ファイル以上 / ブランチ = 最終コミットから ${STALE_DAYS} 日以上"
  echo "- 本レポートは検知のみ。ファイル・ブランチには一切変更を加えていない。"
  echo "  対応する場合は rm ではなく mv で退避し、人間の承認を得てから行うこと。"
  echo
  echo "## サマリ"
  echo
  echo "| # | チェック | 検知 |"
  echo "|---|---|---|"
  echo "| 1 | スキル frontmatter（phase1 基準、${SKILL_COUNT} 本） | NG ${C1_NG} / WARN ${C1_WARN} |"
  echo "| 2 | 逐語重複ブロック | ${C2_COUNT} |"
  echo "| 3 | 残骸ファイル | ${C3_COUNT} |"
  echo "| 4 | 長期間更新のない／リモートに無いリモートブランチ | ${C4_COUNT} |"
  echo "| 5 | 削除済み定型句の再出現 | ${C5_COUNT} |"
  echo "| 6 | 参考: スキル索引の不整合 | ${C6_COUNT} |"
  echo "| | 合計 | ${TOTAL} |"
  echo
  echo "## 1. スキル frontmatter"
  echo
  echo "基準: name は空白なしの snake_case で、ディレクトリ名と一致（入れ子は \`<グループ名から _ops を除く>_<ディレクトリ名>\`）。"
  echo "description は日本語で、英語タイトルで始まらず、「〜と言及したら必ず使用すること」を含み、200〜300 字（範囲外は WARN）。"
  echo
  if [ -n "$C1_BODY" ]; then
    echo "| ファイル | 判定 | 内容 |"
    echo "|---|---|---|"
    printf '%s' "$C1_BODY"
  else
    echo "検知なし。"
  fi
  echo
  echo "## 2. 逐語重複ブロック"
  echo
  echo "対象: Git 管理下と未追跡（.gitignore 対象外）のテキストファイル。"
  echo
  if [ "$C2_COUNT" -gt 0 ]; then
    printf '%s\n' "$C2_BODY"
  else
    echo "検知なし。"
  fi
  echo
  echo "## 3. 残骸ファイル"
  echo
  echo "パターン: \`${REMNANT_PATTERNS[*]}\`（.git/ 配下は除く。.gitignore 対象も含めて列挙）"
  echo
  if [ -n "$C3_BODY" ]; then
    echo "| ファイル | 状態 |"
    echo "|---|---|"
    printf '%s' "$C3_BODY"
    echo
    echo "上記は削除候補の列挙のみ。移動・削除はしていない。"
  else
    echo "検知なし。"
  fi
  echo
  echo "## 4. リモートブランチ"
  echo
  echo "- 既定ブランチ: \`${DEFAULT_REF:-不明}\`（判定対象外）"
  echo "- 最終 fetch: ${FETCH_INFO}。本スクリプトは fetch しないため、日付はこの時点のリモート追跡ブランチに基づく"
  echo "- リモート存在確認: ${REMOTE_STATUS}"
  echo
  if [ -n "$C4_BODY" ]; then
    echo "| ブランチ | 最終コミット | SHA | 既定へマージ | 既定比（先行 / 遅れ） | リモート | 判定 |"
    echo "|---|---|---|---|---|---|---|"
    printf '%s' "$C4_BODY"
    echo
    echo "上記は列挙のみ。ブランチの削除はしていない。"
  else
    echo "既定ブランチ以外のリモート追跡ブランチはない。"
  fi
  echo
  echo "## 5. 削除済み定型句の再出現"
  echo
  echo "除外: \`${BANNED_EXCLUDES[*]}\`"
  echo
  if [ -n "$C5_BODY" ]; then
    printf '%s' "$C5_BODY"
  else
    echo "検知なし（対象 ${#BANNED_PHRASES[@]} 句）。"
  fi
  echo
  echo "## 6. 参考: スキル索引の不整合"
  echo
  echo "skills/ 配下の SKILL.md と \`$README\` のリンクを突き合わせた結果。利用実績（未使用かどうか）はリポジトリからは判定できないため対象外。"
  echo
  if [ -n "$C6_BODY" ]; then
    printf '%s' "$C6_BODY"
  else
    echo "検知なし。"
  fi
}

if [ -n "$OUTPUT" ]; then
  emit_report > "$OUTPUT"
  echo "レポートを出力しました: ${OUTPUT}（検知合計 ${TOTAL} 件）" >&2
else
  emit_report
fi

if [ "$FAIL_ON_FINDINGS" -eq 1 ] && [ "$TOTAL" -gt 0 ]; then
  exit 1
fi
exit 0
