# dev-standards 開発ルール（本リポジトリ自身の編集ルール／Codex・Antigravity共通）

本リポジトリは全プロジェクト共通の開発ルール・スキル・テンプレートを配布する
**Single Source of Truth** である。ここを編集した内容は `project_template/init.sh`
（新規導入）・`project_template/update.sh`（既存プロジェクト同期）を通じて
各プロジェクトの `.agent/` 配下へ配布される。

このファイルは「dev-standards リポジトリ自身」を Codex または Antigravity で
編集するときに読み込まれる（Antigravity は `GEMINI.md` の代わりにこの
`AGENTS.md` をネイティブに読み込む設定を想定）。他プロジェクトへ配布される
雛形は `project_template/CLAUDE.md` であり、そちらは `.agent/rules/*.md` を
参照する別ファイルなので混同しないこと。

## 常時適用ルール（起動時に自動読込されるものとして扱う）

以下は全て本リポジトリ内のファイルであり、作業開始前に必ず目を通すこと。
（Codex/Antigravity は `CLAUDE.md` のような `@import` 構文を持たないため、
このセクション自体を都度読み込む前提とする。）

- rules/language.md — 出力言語ポリシー（日本語固定）
- rules/coding_standards.md — コーディング規約
- rules/git_safety.md — Git安全運用・QC監査・クライアントリポジトリ運用
- rules/output_style.md — 出力・レポートスタイル
- rules/antigravity_qc_checklist.md — コミット前QC監査観点
- rules/model_selection.md — モデル選定・エスカレーション

## 必要時に参照（自動読込しない）

- スキル: skills/README.md の一覧から該当する SKILL.md を辿る
- 完了報告: templates/completion_report.md の形式
- 障害報告: templates/incident_report.md の形式
- クライアントMR作成: templates/mr_template.md の形式
- 新規プロジェクトへの導入手順: project_template/init.sh、docs/APPLYING_TO_EXISTING_PROJECT.md
- 既存プロジェクトの `.agent/` 更新: project_template/update.sh
- skills/ や rules/ を変更した作業の完了報告前: scripts/repo_checkup.sh を実行し、検知結果を報告に含める（検知のみで修正はしない。出力はリポジトリ外に置く: `--output`）

## このリポジトリ固有の注意事項

- **rules/ を編集したら配布ロジックとの整合を確認する。**
  `project_template/init.sh` の `build_git_safety()` / `build_qc_checklist()` は
  `rules/git_safety.md` / `rules/antigravity_qc_checklist.md` の見出し
  （`### 2.5` `### 2.9` `### 3.1` `## 観点C` `## 出力形式` など）を
  正規表現で抜粋して internal-only プロファイル用に配布している。
  見出し番号や `### n.n` の形式を変更する場合は、`init.sh --print-rules` を
  `--type=internal-only` と `--type=client-delivery` の両方で実行し、
  抜粋結果が壊れていないか確認すること。
- **`<!-- stack:kintone-gas:start/end -->` マーカーを保持する。**
  `rules/git_safety.md` 3.1 内のこのマーカーは `init.sh` の `strip_stack()` が
  参照する。マーカーを移動・削除する場合は `--stack=other` / `--stack=kintone-gas`
  両方の `--print-rules` 出力を比較し、意図しない欠落がないか確認する。
  `rules/coding_standards.md` §1 にも同じマーカーがあり、client-delivery の
  `init.sh` は同じく `strip_stack()` を通して配布する（`--print-rules` にも出力される）。
  `update.sh` も `.agent/project_type.conf` の `STACK` を読み、どちらのファイルも
  `init.sh` と同じ規則で strip してから同期する（`update.sh` 内に同じ `strip_stack()` を持つため、
  規則を変える場合は両方を揃える。conf が無いプロジェクトは WARNING を出して原本のまま同期する）。
- 既存プロジェクトへの反映が必要な変更（rules/ skills/ templates/ hooks/ scripts/ の変更）を
  行った場合は、完了報告に「対象プロジェクトへの反映（update.sh）が必要か」を明記する。
