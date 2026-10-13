---
name: kintone_app_analysis
description: "既存KintoneアプリのIDを起点に、フィールド（ラベル・フィールドコード・型）・一覧・JS/CSSを取得し、技術仕様レポートAPP_REPORT.mdを生成するスキル。生成物はkintone系スキルが参照するスキーマ資料の正本になる。ユーザーが「アプリ解析」「APP_REPORT」「アプリのフィールド一覧を出して」「Kintoneアプリの仕様を調べて」と言及したら必ず使用すること。JSロジックの解析はkintone_legacy_js_analysis、コードとスキーマの突合はkintone_field_validationを使う。アプリIDのない設計段階のレビューには使わない。"
---
# Kintone App Analysis Skill

## 目的
Kintoneアプリの設定（スキーマ、一覧、プロセス管理）の抽出を自動化し、標準化されたレポート（`APP_REPORT.md` 等）を生成します。
これにより、「分散ドキュメント化」ポリシーをサポートします。

## 前提条件
- `analyze_kintone_app.js` は本リポジトリには同梱していません。各プロジェクト側で別途用意する前提です。

## 使用方法

### 1. 解析スクリプトの実行
Node.jsスクリプトを実行します。

```bash
node .agent/skills/kintone_ops/app_analysis/analyze_kintone_app.js --app <APP_ID> --output <OUTPUT_PATH>
```

**引数:**
- `--app`: 解析対象のアプリID。
- `--output`: (任意) JSON/Markdownレポートを保存するパス。デフォルトは `<project_root>/Kintoneアプリ/{AppID}_*/APP_REPORT.md`。

### 2. 出力内容
スクリプトは以下の内容を含むMarkdownレポートを生成します：
- **基本情報**: アプリ名、説明、ID。
- **フィールド**: フィールド名、型、フィールドコードのリスト（ソート済み）。
- **一覧**: 一覧名とそのIDのリスト。
- **JavaScript**: 適用されているJS/CSSファイルのリスト。

## 依存関係
- `@kintone/rest-api-client`
- `dotenv` (任意、KINTONE_API_TOKEN用)

---

環境乖離・異常検知時は `rules/git_safety.md` 2.8「環境乖離・異常検知時の停止義務」に従う。
