# CLAUDE.md / AGENTS.md / rules / skills 監査レポート（2026-10-05）

- 対象: dev-standards リポジトリ（`~/Desktop/work/dev-standards`、HEAD `02e3db6`）
- 種別: **監査のみ（本レポート以外のファイルは一切変更していない。コミットもしていない）**
- 基準:
  1. CLAUDE.md/AGENTS.md は「AIが繰り返した間違い・ソースから読めない暗黙知」だけか（一般常識・局所ルールの混入なし）
  2. SKILL.md の `description` が約100語・明示的トリガー表現で、類似スキル間で発動条件が競合しないか
  3. SKILL.md 本体が500行以内か（超過時は references/ 退避余地）
  4. rules/*.md に常時読込不要な内容が混ざっていないか

> 注: 「約100語」は日本語では語数が数えにくいため、文字数（`description:` 行の値）で実測した。英語100語 ≒ 日本語200〜300字を目安とする。

---

## 0. 総括

| 基準 | 結果 |
|---|---|
| 1. CLAUDE.md/AGENTS.md | **要改善**。固有の暗黙知（L37–55）は良質だが、約45行が両ファイル間で逐語重複、「必要時に参照」15行は skills/README.md と二重管理、AGENTS.md にだけモデル選定ルール（14行）が混在 |
| 2. description | **要改善（最大の問題）**。15スキル中14が42〜182字と短く、`〜と言及したら必ず使用` 形式は0件。frontmatter 欠落1件、name とディレクトリ名の不一致2件。発動条件が重複・競合するクラスタが3つ |
| 3. 500行超 | **問題なし**。SKILL.md 最大は legacy_js_analysis の84行。退避が必要な SKILL.md はゼロ。ただし本体内に逐語重複ブロックあり（§3） |
| 4. rules の常時読込 | **要改善**。git_safety.md の §4・§5（69/170行＝41%）は client-delivery 案件のMR/Slack作業時のみ必要。coding_standards.md §1 は Kintone 固有なのに stack マーカー外 |

---

## 1. ファイル別の現状

### 1.1 CLAUDE.md / AGENTS.md / プロジェクトテンプレート

| ファイル | 行数 | 現状・問題点 |
|---|---:|---|
| `CLAUDE.md` | 55 | L8–10, L37–55 は良質な暗黙知。L19–35 の索引が重複（P-1, P-2）。L51–53 は冗長（P-3） |
| `AGENTS.md` | 79 | CLAUDE.md と L1–65 がほぼ同一。L66–79 に「モデル選定・エスカレーション」が追加（P-4）。L27–28 に空行が連続 |
| `project_template/CLAUDE.md` | 18 | 配布先用の薄い雛形。問題なし（スキル索引は csv_handling のみで、本リポの CLAUDE.md と非対称だが意図的と判断） |
| `project_template/project.md` | 21 | 問題なし |

### 1.2 rules/

| ファイル | 行数 | 常時読込 | 問題点 |
|---|---:|---|---|
| `language.md` | 10 | ✅ | `~/.claude/CLAUDE.md` の「回答は日本語」と重複。L7 の「5分おき実況」は局所ルール。L6 に typo `claps push`（正: `clasp push`） |
| `coding_standards.md` | 77 | ✅ | §1（L3–50）が全て Kintone 固有。stack マーカー外のため全スタックに配布される（P-6） |
| `git_safety.md` | 170 | ✅ | 下記 P-5 を参照 |
| `output_style.md` | 43 | ✅ | L32–37 の `file://` リンク規約は VS Code/Antigravity 向けで Claude Code では不要。L11–15 は一般的な文章作法 |
| `antigravity_qc_checklist.md` | 31 | ✅ | 観点A L10 の NFC/NFD は実害が出た暗黙知で **良質**。観点B L16、観点C L22 は Kintone/Gori 固有 |

### 1.3 skills/（SKILL.md 15本）

| スキル | 行数 | desc文字数 | frontmatter | 主な問題 |
|---|---:|---:|---|---|
| `anti_regression_protocol` | 36 | 71 | ✅ | トリガーが desc に無く、本文 L9 が「ファイル修正の依頼を受けた際」と過広。L28 の全返答末尾チェックリスト義務が output_style と衝突 |
| `comparative_schema_analysis` | 63 | 63 | ✅ | desc が最短級。トリガーは本文 L9 のみ |
| `csv_handling` | 68 | 0 | ❌ **欠落** | `---` ブロックなし。スキルとして自動検出されない |
| `diary_editing` | 41 | 111 | ✅ | トリガー語（日記・note）なし。`sns_editorial` と SNS 生成で競合 |
| `git_safe_renaming` | 52 | 104 | ✅ | desc は汎用だが本文は「日付サフィックス削除」専用 |
| `implementation_fidelity` | 79 | 87 | ✅ | desc は「整合性確認」だが本文 §5 は別主題（Read-After-Write） |
| `kintone_ops/app_analysis` | 46 | 108 | ✅ | 定型句「改修前には必ず…」付与 |
| `kintone_ops/field_validation` | 60 | 106 | ✅ | 同上。`legacy_js_analysis` と発動条件が重なる |
| `kintone_ops/legacy_js_analysis` | 84 | 109 | ✅ | 同上 |
| `kintone_ops/mapping_regression_prevention` | 61 | 182 | ✅ | 唯一長めだが、トリガーが `logic_fidelity_verification` と重なる |
| `logic_fidelity_verification` | 66 | 102 | ✅ | name が「Data Fidelity Assurance Strategy」でディレクトリ名と不一致 |
| `proactive_communication` | 55 | 94 | ✅ | トリガー「ユーザーへの報告時」は全応答に該当 |
| `requirements_evolve` | 39 | 118 | ✅ | name が `dynamic_requirements_management` でディレクトリ名と不一致。トリガー「全プロジェクトでの要件変更」が過広 |
| `safe_development` | 50 | **42** | ✅ | desc が最短で、トリガー表現なし |
| `sns_editorial` | 40 | 96 | ✅ | トリガー語なし。`diary_editing` と競合 |

SKILL.md の最大行数は `legacy_js_analysis` の84行で、**500行超は0件**。非 SKILL.md では `skills/sns_editorial/channels/instagram.md`（120行）と `skills/diary_editing/workflows/avatar_image.md`（122行）が最大。いずれも必要時のみ読込される構成で問題ない。

---

## 2. 問題箇所の引用と理由

### P-1【高】CLAUDE.md と AGENTS.md の逐語重複（ドリフトリスク）

- 該当: `CLAUDE.md` L37–55 ＝ `AGENTS.md` L46–64（「このリポジトリ固有の注意事項」4項目、一字一句同一）。`CLAUDE.md` L19–35 ＝ `AGENTS.md` L26–44（索引15行）
- 理由: 片方だけ更新される事故が起きやすい。init.sh の見出し抜粋ロジックに関する注意は、片方が古くなると配布事故に直結する。
- 案: 注意事項を1ファイルに寄せ、もう一方は `@`/参照で指す。Codex/Antigravity は `@import` を持たない（AGENTS.md L17–18 の自己申告）ため、AGENTS.md を正とし CLAUDE.md から `@AGENTS.md` で取り込む構成が最小。

### P-2【中】「必要時に参照」索引が skills/README.md と二重管理

- 該当: `CLAUDE.md` L19–35。スキル9本を列挙している（`skills/README.md` L8–19 に同内容の表がある）。
- 理由: スキル追加のたびに3か所（CLAUDE.md・AGENTS.md・README.md）の更新が必要。実際、`diary_editing` / `sns_editorial` は README.md にあるが CLAUDE.md/AGENTS.md には無く、既にずれている。さらに `~/.claude/skills` は symlink 済み（`docs/skill_optimization_architecture.md` §5）で、発見は description が担うため索引は冗長。
- 案: スキル行を削除し「スキル一覧: skills/README.md」の1行にする。templates/・導入手順の行は暗黙知として残す。

### P-3【低】既に常時読込済みのルールの再掲

- 該当: `CLAUDE.md` L51–53「本リポジトリ自身への変更も git_safety.md の全ルールに従う。特に 2.7 …」
- 理由: git_safety.md は L15 で `@` 読込済み。「全ルールに従う」はAIの間違いの再発防止というより一般的な念押し。2.7 は `~/.claude/CLAUDE.md` にも書かれている。
- 補足: L54–55（update.sh 反映要否を完了報告に書く）は暗黙知として **維持**。

### P-4【中】AGENTS.md L66–79「モデル選定・エスカレーション」の混在

- 引用: 「すべての新規依頼について、作業開始前に依頼を『低・中・高・最高』の4段階で判定する。」
- 理由: ①dev-standards 自体の編集ルールではなく、AIエージェント運用ポリシー全般。②CLAUDE.md に存在しないため、Claude Code 側だけ非対称。③配布先の AGENTS.md には含まれない。どこに置くべきかが未決定。
- 案: 全プロジェクト共通なら `rules/` か `~/.claude/CLAUDE.md` 相当へ。Codex/Antigravity 専用なら配布用 AGENTS.md 雛形側へ。方針決定をユーザーに仰ぐ。

### P-5【中】git_safety.md（170行）に常時読込不要な内容

構成と必要場面（行数は区間の概算）:

| 節 | 行 | 概算行数 | 常時必要か |
|---|---|---:|---|
| §1 着手時の安全確保 | L3–14 | 12 | 要（ただし 1.1 は後述の重複あり） |
| §2 QC監査 | L18–81 | 64 | 概ね要。2.4 は `~/.claude/CLAUDE.md` と重複、2.1/2.3 は一般常識 |
| §3 検証設計 | L85–95 | 11 | 要 |
| §4 クライアントリポジトリ運用 | L99–131 | 33 | **client-delivery のMR/push作業時のみ** |
| §5 Slack通知文生成 | L135–170 | 36 | **完了報告時のみ**。フォーマット例（L156–164）は templates/ 向き |

具体的な重複・一般常識:
- 引用 L38–48（2.4）「`feat`: 新しい機能や仕様の追加 / `fix`: バグや不具合の修正 …」→ Conventional Commits の type 説明は一般常識。`~/.claude/CLAUDE.md` にも同ルールがある。残すなら例（`fix(app583): …`）のプロジェクト固有の運用部分だけで十分。
- 引用 L20–24（2.1）「`console.log` のデバッグ出力が残っていないか」→ 一般常識。
- 1.1（L5–9）のバックアップコミットは、`anti_regression_protocol` Step 1、`safe_development` §1、`logic_fidelity_verification` Phase 3-0 の計4か所に重複。
- 2.5 / 2.6 / 2.7 は `~/.claude/CLAUDE.md` と同一内容。

注意: internal-only プロファイルでは `init.sh` が §2.5 / §2.9 / §3.1 だけを抜粋して配布している（`init.sh` L112–135）。§4・§5 を `skills/` や `templates/` に移しても internal-only 配布には影響しないが、client-delivery 配布は全文を `cp` する（L114）ため、移した内容へ辿れる参照行を残す必要がある。

### P-6【中】coding_standards.md §1 が Kintone 固有なのに全スタックへ常時配布

- 引用: 「### 1.1 フィールド存在確認のガード処理」「### 1.3 Kintoneイベントハンドラ内の try-catch 例外設計」（L3–50、全体の約62%）
- 理由: `skills/README.md` L21–22 は「Kintone を使う案件に強く依存した手順は他スタックで読む必要はない」と述べ、`kintone_ops/` に隔離している。一方で rules/ だけ隔離が徹底されていない。`1.2 Null-safety`（L21–30）は一般常識（`?.` / `??`）。
- 案: §1 を `skills/kintone_ops/` 配下（例: `gori_style/`）へ移すか、`<!-- stack:kintone-gas:start/end -->` で囲む。後者は init.sh の `strip_stack()` が既に処理するため、init.sh の変更は不要（マーカーを増やすだけ）。

### P-7【低】language.md / output_style.md の局所・重複記述

- `language.md` L7「『5分おき実況』などの稼働状況報告も…」→ 実況プロトコル自体がこのリポジトリに存在しない。局所ルールの残骸。L3–5 は `~/.claude/CLAUDE.md` の1行と重複。
- `output_style.md` L32–37 → `file://` リンクは Antigravity/VS Code 向け。端末の Claude Code では不要。
- `output_style.md` L39–43（2.3 段階承認）と `anti_regression_protocol` L28（全返答末尾にチェックリスト）は、L7–9（結論ファースト）と運用が衝突しうる。

### P-8【高】スキル description の形式不備（基準2の主因）

- 実測: 42〜182字（中央値約100字）。基準の「約100語＝日本語で200字超」に届くのは0本。
- `〜と言及したら必ず使用すること` 形式の明示的トリガー: **0本**（`【トリガー：…】` 形式が8本、残り7本はトリガー自体なし）。
- 引用（最短）: `safe_development` →「プロジェクト横断で安全な開発フロー（同期・解析・実装・検証）を実行するためのスキル。」（42字）。いつ起動すべきか不明。
- 引用: `anti_regression_protocol` →「…義務付ける『職人品質』の監査スキル。」「職人品質」は起動条件ではなく自己評価。
- 引用: `csv_handling` → frontmatter 自体が無い。`~/.claude/skills` への symlink 配備でも description が無いので、スキルとして選択されない可能性が高い。本文 L3–5「発動条件」は本文を読んだ後でしか機能しない。
- 引用（定型句）: 8スキルに「改修前には必ず〜の事前分析を行え」が付与されている。これはスキルの説明ではなく指示で、各スキルを無関係なタスクでも「改修前」トリガーに見せてしまう。
- name 不一致: `requirements_evolve/`（name: `dynamic_requirements_management`）、`logic_fidelity_verification/`（name: `Data Fidelity Assurance Strategy`）。他にスペース・大文字入りの name が6本ある（例: `Git Safe Renaming Protocol`）。

### P-9【高】発動条件が重複・競合するクラスタ

| クラスタ | スキル | 競合の内容 |
|---|---|---|
| A: 「コード修正時のデグレ防止」 | `anti_regression_protocol`, `safe_development`, `logic_fidelity_verification`, `git_safe_renaming`, git_safety 2.2 | トリガーが「修正の依頼を受けた際」と事実上同一。Gitバックアップ手順が4か所に重複。優先順位が未定義（ARP L35 は「他のいかなる作業よりも優先」と宣言） |
| B: 「Kintone JS／マッピング改修時の検証」 | `kintone_ops/legacy_js_analysis`, `kintone_ops/field_validation`, `kintone_ops/mapping_regression_prevention`, `logic_fidelity_verification`, `implementation_fidelity` | 全てが「リファクタリング・修正時」に該当。`legacy_js_analysis` Phase 1–2 と `logic_fidelity_verification` Phase 1–2 は As-Is 解析で同内容。相互の使い分けを書いているのは `logic_fidelity_verification` L380–383 のみ |
| C: 「SNS向け文章生成」 | `diary_editing`（ステップ4 SNS告知文）, `sns_editorial` | どちらも X/Threads/Instagram 向け投稿を生成する。どちらを使うかの分岐条件が description に無い |

加えて、`proactive_communication`（トリガー「ユーザーへの報告時」）と `requirements_evolve`（「要件変更・新規決定事項の発生時」＝「〜のようにして」への全反応）は適用範囲が過広で、実質的に常時発動してしまう。

### P-10【中】SKILL.md 本体の逐語重複（500行問題の代替として）

- 引用: 「## 【重要】環境乖離・異常検知プロトコル 本スキルの実行にあたり、ローカルリポジトリ（Git等）と本番環境のソースコードの間に…」→ 同一ブロック（約7行）が **10スキル＋git_safety 2.8 に逐語コピー**されている（`grep -rl "環境乖離"` で11ファイル）。
- 理由: 約70行が重複。スキル発動のたびにトークンを消費し、修正も11か所に及ぶ。2.8 は常時読込されるため、スキル側は「git_safety.md 2.8 に従う」の1行で足りる。
- 付随: `implementation_fidelity/SKILL.md` L294–312 のサンプルスクリプト（例に `MD004 Markdown Lint ルール` という無関係な項目が混入）と §5（L288–292、Read-After-Write）は、本体のコード照合手順とは別主題。500行未満だが `references/` 分離の候補。
- 付随: `requirements_evolve` L471–472 は「プロジェクト固有のエージェント振る舞いルール」を `SKILL.md` に書くよう指示している。ルールの置き場は CLAUDE.md/.agent/rules であり、スキル本体を書き換える指示は誤誘導になりうる。

### P-11【低】その他

- `skills/diary_editing/SKILL.md` L14 / `sns_editorial/SKILL.md` L16 にユーザー固有の絶対パス、`diary_editing` に一人称「俺」。個人用スキルが開発標準リポジトリに混在している（README.md 自身が「開発ルールとは独立」と明記）。
- `scripts/deploy_skills.py.bak` が git 管理下。
- `skills/README.md` L41–44「今回統合しなかったスキル」は時点情報で陳腐化している。
- `docs/skill_optimization_architecture.md` §6–8（データ移行原則、`.pre_deploy.bak` 管理）はスキル構成と無関係な内容が混在。

---

## 3. 改善の優先順位案

### 高

1. **P-8** description の再設計（全15本）。`〜と言及したら必ず使用すること` 形式で、約200〜300字、トリガー語・除外条件つきに統一。`csv_handling` に frontmatter を追加。name をディレクトリ名と一致させる。
2. **P-9** 発動条件クラスタ A/B/C の整理。1スキル1トリガー面にし、相互の使い分けを description に明記（または統合）。
3. **P-1** CLAUDE.md/AGENTS.md の重複解消（片方を正にして参照）。

### 中

4. **P-10** 「環境乖離・異常検知プロトコル」ブロックの10か所重複削除（git_safety 2.8 参照へ）。
5. **P-5** git_safety.md §4・§5 の分離検討、2.4 の一般常識部分の圧縮、1.1 の4重複解消。
6. **P-6** coding_standards.md §1 の Kintone 固有部分を stack マーカーまたは `kintone_ops/` へ。
7. **P-2** 「必要時に参照」索引の一本化。
8. **P-4** AGENTS.md の「モデル選定」の置き場決定（ユーザー判断が必要）。

### 低

9. **P-3** CLAUDE.md L51–53 の削除、**P-7** language.md/output_style.md の局所記述整理（`claps` typo 含む）、**P-11** 個人用スキル・`.bak`・陳腐化記述の整理。

---

## 4. 次回実行セッションの具体的な修正候補リスト（※本セッションでは未実施）

> 以下は着手前に必ず対象を再確認すること。init.sh の抜粋ロジックと stack マーカーに触れる項目は、変更後に `project_template/init.sh --print-rules` を `--type=internal-only` / `--type=client-delivery`、および `--stack=other` / `--stack=kintone-gas` の組み合わせで実行し、出力が変わっていないことを確認する（CLAUDE.md L39–50 の指示）。

| # | 対象ファイル | 修正内容 | 優先 | 検証方法 |
|---|---|---|---|---|
| F-1 | `skills/csv_handling/SKILL.md` | frontmatter（name/description）を追加し、本文 L3–5 のトリガーを description へ移す | 高 | `head -5` で frontmatter 確認 |
| F-2 | `skills/*/SKILL.md` 全15本 | description を明示トリガー形式で書き直し。8本から定型句「改修前には必ず…」を除去 | 高 | desc 文字数・トリガー語の有無を再実測 |
| F-3 | `requirements_evolve`, `logic_fidelity_verification`, 他 name にスペースのあるスキル | name をディレクトリ名と一致させる（参照元の CLAUDE.md/README.md のリンクも確認） | 高 | `grep -rn "name:" skills` |
| F-4 | クラスタA: `anti_regression_protocol`, `safe_development` | 統合するか、役割分担（Gitベースライン / スコープ制限）を description に明記。ARP L28 の「全返答末尾チェックリスト」の扱いを決定 | 高 | 重複行の消失確認 |
| F-5 | クラスタB: `kintone_ops/*`, `logic_fidelity_verification`, `implementation_fidelity` | 各 description に「使うとき／使わないとき」を追加し、使い分け表を `skills/README.md` に置く | 高 | 相互参照の整合 |
| F-6 | クラスタC: `diary_editing`, `sns_editorial` | description に「日記整形→diary_editing、既存ログからの投稿編集→sns_editorial」の境界を明記 | 高 | 同上 |
| F-7 | `CLAUDE.md`, `AGENTS.md` | 注意事項（L37–55）を片方に集約、スキル索引15行を `skills/README.md` 参照1行に置換、L51–53 削除 | 高/中 | `diff CLAUDE.md AGENTS.md` |
| F-8 | 10スキル | 「環境乖離・異常検知プロトコル」ブロックを削除し、「git_safety.md 2.8 に従う」の1行に置換 | 中 | `grep -rl "環境乖離" .` が git_safety.md のみ |
| F-9 | `rules/git_safety.md` | §4・§5 を別ファイル化する場合、client-delivery 配布時に全文が必要なため **init.sh の `cp`／update.sh の同期対象への影響を先に確認**。2.4 の type 解説圧縮。見出し `### 2.5` `### 2.9` `### 3.1` は変更しない | 中 | `init.sh --print-rules` を4組合せで前後比較 |
| F-10 | `rules/coding_standards.md` | §1 に `<!-- stack:kintone-gas:start/end -->` を付与（または `kintone_ops/` へ移設）。1.2 は削除候補 | 中 | `--stack=other` / `--stack=kintone-gas` の出力比較 |
| F-11 | `AGENTS.md` L66–79 | モデル選定ルールの置き場をユーザーと決定してから移設 | 中 | ユーザー確認 |
| F-12 | `rules/language.md`, `rules/output_style.md` | `claps` → `clasp`、L7 実況行・`file://` 規約の要否判断 | 低 | `grep -n claps rules` |
| F-13 | `implementation_fidelity/SKILL.md` | §5 とサンプルスクリプトを `references/` へ分離（任意）、`MD004` の例を除去 | 低 | 行数確認 |
| F-14 | `skills/diary_editing`, `skills/sns_editorial`, `scripts/deploy_skills.py.bak`, `skills/README.md` L41–44, `docs/skill_optimization_architecture.md` §6–8 | 個人用スキルの分離可否、`.bak` の `git rm`、陳腐化記述の整理 | 低 | `git status` |

### 実施時の注意（既存ルールとの関係）

- ステージングは個別パス指定。`git add .` / `git commit -am` は使わない。コミット直前に `git diff --cached --stat` を確認する。
- 変更が rules/ skills/ templates/ hooks/ scripts/ に及ぶ場合、完了報告に「対象プロジェクトへの反映（update.sh）が必要か」を明記する（CLAUDE.md L54–55）。
- 確認が必要な未決事項: ①AGENTS.md のモデル選定ルールの置き場（P-4）、②個人用スキル2本を本リポジトリに残すか（P-11）、③クラスタ A でスキルを統合するか分担に留めるか（F-4）。
