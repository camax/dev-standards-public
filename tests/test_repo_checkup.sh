#!/usr/bin/env bash
# scripts/repo_checkup.sh のテスト。
# 一時ディレクトリに検知対象を仕込んだ Git リポジトリ（と bare リモート）を作り、
# レポートの検知件数・内容・終了コードと、実行前後でリポジトリが一切変わらないことを確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKUP="$SCRIPT_DIR/../scripts/repo_checkup.sh"

[ -x "$CHECKUP" ] || { echo "Error: $CHECKUP が無いか実行権限がない" >&2; exit 1; }

TMP_DIR="$(mktemp -d /tmp/test-repo-checkup-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "[PASS] $*"; }
ng() { FAIL=$((FAIL + 1)); echo "[FAIL] $*"; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# グローバルのフック（~/.config/git-hooks）をフィクスチャ作成に巻き込まない
g() { git -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }

# 200〜300字・明示トリガーつきの description を作る
good_desc() {
  local body="テスト用の正しい形式のスキル説明文。"
  local d=""
  while [ "${#d}" -lt 200 ]; do d="${d}${body}"; done
  printf '%s' "${d}ユーザーが「テスト」と言及したら必ず使用すること。"
}

write_skill() { # $1: パス, $2: name, $3: description
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: %s\ndescription: "%s"\n---\n\n# 本文\n' "$2" "$3" > "$1"
}

run() { # OUT と RC を設定する
  RC=0
  OUT="$("$CHECKUP" "$@" 2>&1)" || RC=$?
}

expect_contains() { # $1: 期待文字列, $2: 説明
  if grep -qF -- "$1" <<<"$OUT"; then ok "$2"; else ng "$2 | '$1' が出力にない"; fi
}

expect_not_contains() {
  if grep -qF -- "$1" <<<"$OUT"; then ng "$2 | '$1' が出力にある"; else ok "$2"; fi
}

expect_rc() { # $1: 期待終了コード, $2: 説明
  if [ "$RC" -eq "$1" ]; then ok "$2 (exit $RC)"; else ng "$2 | exit $RC（期待 $1）| $OUT"; fi
}

# 作業ツリー（.git 以外）の全ファイルの内容・refs・status をまとめたスナップショット
snapshot() {
  (
    cd "$1"
    find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s %s\n' "$(shasum "$f" | cut -d' ' -f1)" "$f"
    done
    git for-each-ref --format='%(refname) %(objectname)'
    git status --porcelain --ignored
    git config --local --list
  )
  git -C "$2" for-each-ref --format='remote %(refname) %(objectname)'
}

DESC_OK="$(good_desc)"

echo "=== フィクスチャ: 検知対象を仕込んだリポジトリ ==="
BARE="$TMP_DIR/remote.git"
W="$TMP_DIR/work"
g init -q --bare "$BARE"
g init -q "$W"
cd "$W"
g remote add origin "$BARE"

write_skill skills/good_skill/SKILL.md good_skill "$DESC_OK"
write_skill skills/grp_ops/sub/SKILL.md grp_sub "$DESC_OK"
write_skill skills/bad_skill/SKILL.md "Bad Skill Protocol" "Bad Skill Title：短い説明"
write_skill skills/wrong_name/SKILL.md other_name "$DESC_OK"
write_skill skills/grp_ops/nested/SKILL.md nested "$DESC_OK"
mkdir -p skills/no_fm && printf '# frontmatter なし\n' > skills/no_fm/SKILL.md
cat > skills/README.md <<'EOF'
| [good_skill](./good_skill/SKILL.md) | 正常 |
| [grp_ops/sub](./grp_ops/sub/SKILL.md) | 正常 |
| [bad_skill](./bad_skill/SKILL.md) | 不正 |
| [wrong_name](./wrong_name/SKILL.md) | 不正 |
| [grp_ops/nested](./grp_ops/nested/SKILL.md) | 不正 |
| [ghost](./ghost/SKILL.md) | リンク切れ |
EOF

# 空行を挟んだ5行の同一ブロックを3ファイルに置く（空行の有無が違っても同一とみなす）
mkdir -p rules docs
for f in rules/a.md rules/b.md; do
  printf '# %s\n\n## 共通ブロック\n\n行1の本文\n\n1. 手順一\n2. 手順二\n3. 手順三\n\n末尾 %s\n' "$f" "$f" > "$f"
done
printf '# c\n## 共通ブロック\n行1の本文\n1. 手順一\n2. 手順二\n3. 手順三\n末尾 c\n' > rules/c.md
# 4行だけの重複は既定（5行）では検知しない
for f in rules/d.md rules/e.md rules/f.md; do
  printf '固有 %s\n短1\n短2\n短3\n短4\n固有末尾 %s\n' "$f" "$f" > "$f"
done

printf '本文に改修前には必ず事前分析を行え。\n' > rules/banned.md
printf '監査記録の引用: 改修前には必ず\n' > docs/claude_agents_md_audit_2026-10.md
printf 'tracked orig\n' > rules/x.orig

g add -A
g commit -qm init
g push -q -u origin main

# 60日前のコミットだけを持つブランチ、最近のブランチ、リモートから消えたブランチ
OLD="$(( $(date +%s) - 60 * 86400 )) +0900"
g switch -q -c old-feature
printf 'old\n' > old.txt && g add old.txt
GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" g commit -qm old
g push -q origin old-feature
g switch -q main
g switch -q -c fresh-feature
printf 'fresh\n' > fresh.txt && g add fresh.txt && g commit -qm fresh
g push -q origin fresh-feature
g switch -q main
g branch -q gone-feature
g push -q origin gone-feature
g -C "$BARE" update-ref -d refs/heads/gone-feature   # リモート側だけ消す（追跡ブランチは残る）

# 未追跡の残骸（.gitignore 対象と対象外）
printf 'bak\n' > notes.md.bak
printf '*.swp\n' > .gitignore
printf 'swp\n' > rules/.a.md.swp

BEFORE="$(snapshot "$W" "$BARE")"
run --repo "$W"
expect_rc 0 "検知ありでも既定は exit 0"
AFTER="$(snapshot "$W" "$BARE")"
if [ "$BEFORE" = "$AFTER" ]; then
  ok "実行前後で作業ツリー・refs・status・config・リモートが変わらない"
else
  ng "実行前後で差分がある"; diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") || true
fi

echo "=== 1. スキル frontmatter ==="
# NG: bad_skill 4件（スペース・snake_case・英語タイトル・トリガーなし）+ wrong_name・nested・no_fm 各1件
expect_contains "| 1 | スキル frontmatter（phase1 基準、6 本） | NG 7 / WARN 1 |" "NG/WARN の件数"
expect_contains "name にスペースがある: \`Bad Skill Protocol\`" "スペース入り name"
expect_contains "name が snake_case（小文字英数字と _）でない: \`Bad Skill Protocol\`" "snake_case でない name"
expect_contains "description が英語タイトルで始まる" "英語タイトルの description"
expect_contains "| \`skills/bad_skill/SKILL.md\` | WARN | description が" "短すぎる description は WARN"
expect_contains "name \`other_name\` が期待値 \`wrong_name\` と一致しない" "ディレクトリ名との不一致"
expect_contains "name \`nested\` が期待値 \`grp_nested\` と一致しない" "入れ子スキルの name 規則"
expect_contains "| \`skills/no_fm/SKILL.md\` | NG | frontmatter" "frontmatter なし"
expect_not_contains "skills/good_skill/SKILL.md\` |" "正しいスキルは検知しない"
expect_not_contains "skills/grp_ops/sub/SKILL.md\` |" "正しい入れ子スキルは検知しない"

echo "=== 2. 逐語重複ブロック ==="
expect_contains "| 2 | 逐語重複ブロック | 1 |" "5行×3ファイルの重複を1件検知（4行の重複は対象外）"
expect_contains "- \`rules/c.md\` L2–6" "空行の有無が違うファイルも同一ブロックとして行番号つきで列挙"
expect_not_contains "rules/d.md" "4行の重複は検知しない"

echo "=== 3. 残骸ファイル ==="
expect_contains "| 3 | 残骸ファイル | 3 |" "残骸3件"
expect_contains "| \`notes.md.bak\` | 未追跡 |" "未追跡の .bak"
expect_contains "| \`rules/x.orig\` | Git 管理下 |" "Git 管理下の .orig"
expect_contains "| \`rules/.a.md.swp\` | 未追跡（.gitignore 対象） |" ".gitignore 対象の .swp"
[ -f "$W/notes.md.bak" ] && [ -f "$W/rules/x.orig" ] && ok "残骸ファイルは削除されていない" || ng "残骸ファイルが消えた"

echo "=== 4. リモートブランチ ==="
expect_contains "| 4 | 長期間更新のない／リモートに無いリモートブランチ | 2 |" "古いブランチとリモートに無いブランチで2件"
expect_contains "| \`origin/old-feature\` |" "古いブランチを列挙"
expect_contains "30 日以上更新なし" "30日超を判定"
expect_contains "リモートに存在しない（追跡ブランチのみ残存）" "リモートから消えたブランチを判定"
if grep -F "| \`origin/fresh-feature\` |" <<<"$OUT" | grep -qF "| — |"; then ok "最近のブランチは判定なし"; else ng "最近のブランチが検知された"; fi
expect_not_contains "| \`origin/main\` |" "既定ブランチは対象外"
g -C "$W" show-ref -q --verify refs/remotes/origin/gone-feature && ok "追跡ブランチは削除されていない" || ng "追跡ブランチが消えた"

echo "=== 5. 削除済み定型句 ==="
expect_contains "| 5 | 削除済み定型句の再出現 | 1 |" "定型句1件（監査記録は除外）"
expect_contains "rules/banned.md:1:本文に改修前には必ず" "ファイル名と行番号つきで列挙"
expect_not_contains "docs/claude_agents_md_audit_2026-10.md:" "監査記録は除外"

echo "=== 6. 索引 ==="
expect_contains "| 6 | 参考: スキル索引の不整合 | 2 |" "未掲載1件 + リンク切れ1件"
expect_contains "索引に未掲載: \`skills/no_fm/SKILL.md\`" "未掲載スキル"
expect_contains "索引のリンク切れ: \`skills/ghost/SKILL.md\`" "リンク切れ"

echo "=== オプション ==="
run --repo "$W" --no-remote
expect_contains "| 4 | 長期間更新のない／リモートに無いリモートブランチ | 1 |" "--no-remote ではリモート存在確認をしない"
expect_contains "リモート存在確認: 未確認（--no-remote）" "--no-remote の明記"

run --repo "$W" --no-remote --stale-days 90
expect_contains "| 4 | 長期間更新のない／リモートに無いリモートブランチ | 0 |" "--stale-days 90 では60日前のブランチを検知しない"

run --repo "$W" --no-remote --dup-lines 4
expect_contains "| 2 | 逐語重複ブロック | 2 |" "--dup-lines 4 では4行の重複も検知"

run --repo "$W" --no-remote --fail-on-findings
expect_rc 1 "--fail-on-findings で検知あり"

REPORT="$TMP_DIR/report.md"
run --repo "$W" --no-remote --output "$REPORT"
expect_rc 0 "--output"
if [ -s "$REPORT" ] && grep -qF "# dev-standards リポジトリ定期チェック レポート" "$REPORT"; then
  ok "--output でファイルに書き出す"
else
  ng "--output のファイルが無い"
fi

run --repo "$W" --dup-lines 1
expect_rc 2 "--dup-lines 1 は引数エラー"
run --repo "$W" --bogus
expect_rc 2 "不明な引数は引数エラー"
run --repo "$TMP_DIR"
expect_rc 2 "Git リポジトリでないディレクトリはエラー"

echo "=== 検知なしのリポジトリ ==="
C="$TMP_DIR/clean"
g init -q "$C"
(
  cd "$C"
  write_skill skills/good_skill/SKILL.md good_skill "$DESC_OK"
  printf '| [good_skill](./good_skill/SKILL.md) | 正常 |\n' > skills/README.md
  g add -A && g commit -qm init
)
run --repo "$C" --fail-on-findings
expect_rc 0 "検知なしなら --fail-on-findings でも exit 0"
expect_contains "| | 合計 | 0 |" "合計0件"
expect_contains "既定ブランチ以外のリモート追跡ブランチはない。" "リモートなしでも動く"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
