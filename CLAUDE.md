# dev-standards 開発ルール（本リポジトリ自身の編集ルール）

本リポジトリは全プロジェクト共通の開発ルール・スキル・テンプレートを配布する
**Single Source of Truth** である。ここを編集した内容は `project_template/init.sh`
（新規導入）・`project_template/update.sh`（既存プロジェクト同期）を通じて
各プロジェクトの `.agent/` 配下へ配布される。

このファイルは「dev-standards リポジトリ自身」を編集するときに読み込まれる。
他プロジェクトへ配布される雛形は `project_template/CLAUDE.md` であり、
そちらは `.agent/rules/*.md` を参照する別ファイルなので混同しないこと。

## 常時適用ルール（起動時に自動読込）
@rules/language.md
@rules/coding_standards.md
@rules/git_safety.md
@rules/output_style.md
@rules/antigravity_qc_checklist.md
@rules/model_selection.md

## 必要時に参照（自動読込しない）

正は `AGENTS.md` の「必要時に参照（自動読込しない）」節（Codex / Antigravity と共用）。
CLAUDE.md 側には複製せず、末尾の `@AGENTS.md` の import で読み込む。編集は AGENTS.md 側のみで行うこと。

## このリポジトリ固有の注意事項

正は `AGENTS.md` の「このリポジトリ固有の注意事項」節（Codex / Antigravity と共用）。
CLAUDE.md 側には複製せず、以下の import で読み込む。編集は AGENTS.md 側のみで行うこと。

@AGENTS.md
