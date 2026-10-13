# dev-standards

全プロジェクト共通の開発ルール・スキル・レポートテンプレートを管理するリポジトリ。

## 目的

HC_Project で確立した開発ルールのうち汎用部分を抽出したもの。
新規プロジェクトを開始する際、Claude Code / Antigravity が同じルールセットで
動作する体制を提供する。

## 構成

```
rules/                      常時適用する開発ルール
  language.md               言語ポリシー（日本語）
  coding_standards.md       コーディング規約
  git_safety.md             Git 安全運用ルール（納品リポジトリ運用の4章を含む）
  output_style.md           出力・レポートスタイル
  antigravity_qc_checklist.md  コミット前QC監査の観点（仕様/セキュリティ/単純化）
skills/
  csv_handling/SKILL.md     CSV を扱うタスク用スキル
templates/
  incident_report.md        障害報告テンプレート
  completion_report.md      完了報告テンプレート
  mr_template.md            クライアント納品リポジトリ向けMR説明文テンプレート
hooks/
  pre-push                  クライアント宛push停止ガード（.agent/delivery.conf 参照）
scripts/
  sync_to_delivery.sh       許可リスト方式の納品同期（.agent/delivery_allowlist.txt 参照）
project_template/
  CLAUDE.md                 新プロジェクト用 CLAUDE.md 雛形
  project.md                プロジェクト固有設定の雛形（.agent/project.md へ）
  delivery.conf             納品先設定の雛形（.agent/delivery.conf へ）
  delivery_allowlist.txt    納品許可リストの雛形（.agent/delivery_allowlist.txt へ）
  init.sh                   新プロジェクトへの導入スクリプト（--print-rules で抜粋のみ出力も可）
  update.sh                 既存プロジェクトの .agent/ 更新スクリプト
docs/
  APPLYING_TO_EXISTING_PROJECT.md  dev-standards由来でない.agentと共存させる手順
```

## 新プロジェクトへの導入手順

1. 新プロジェクトのルートディレクトリで以下を実行する:

   ```bash
   ~/dev-standards/project_template/init.sh
   ```

   これにより `rules/` `skills/` `templates/` が `.agent/` 配下にコピーされ、
   `CLAUDE.md`（`project_template/CLAUDE.md` の雛形）が配置される。

2. Claude Code でそのプロジェクトを開き、`/memory` で `@.agent/rules/*.md` が
   インポートされていることを確認する。

3. Antigravity で使う場合は、そのプロジェクトをワークスペースとして開けば
   `.agent/rules` が自動読込される。

## 運用ルール（シングルソース原則）

- **ルールの実体はこのリポジトリが唯一の正（Single Source of Truth）である。**
- 各プロジェクトの `.agent/` 配下はコピーではなく「参照・同期」として扱うこと。
  ルールを修正したい場合は必ずこのリポジトリで編集・コミットし、
  既存プロジェクトへは `project_template/update.sh` で同期する（新規導入は `init.sh`）。
- 各プロジェクト側で `.agent/` の rules/ templates/ hooks/ scripts/ を直接編集してはならない。
  プロジェクト固有の値は `.agent/project.md` / `.agent/delivery.conf` /
  `.agent/delivery_allowlist.txt` に書く（これらは update.sh で上書きされない）。
