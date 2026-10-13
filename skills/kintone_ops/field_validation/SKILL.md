---
name: kintone_field_validation
description: "Kintone JSのフィールドコード参照を追加・変更した後、デプロイ前に、コード内のフィールドマッピングを実アプリのスキーマ（*_fields.json）と突合し、存在しないフィールドコードの参照を検出するスキル。ユーザーが「フィールドコードを確認」「Field not found」「デプロイ前にフィールド検証」と言及したら必ず使用すること。スキーマ資料の生成はkintone_app_analysis、新旧フィールドコードの対応比較はlogic_fidelity_verification、要件のgrep確認はimplementation_fidelityを使う。"
---

# Kintone Field Validation Protocol

## 目的
正しくない、または存在しないフィールドコードを参照しているKintoneスクリプトのデプロイを防ぐこと（デグレード防止）。

## 前提条件
- `validate_field_mapping.js` が `<project_root>/Kintoneアプリ/` ルートに存在すること。
- `update_analysis.py` が `<project_root>/Kintoneアプリ/` ルートに存在すること。
- 上記2つのスクリプトは本リポジトリには同梱していません。各プロジェクト側で別途用意する前提です。
- Node.js と Python 3 がインストールされていること。

## ワークフロー

### 1. スキーマ解析の更新
バリデーション（手順2）を実行する前に、ローカルの解析ファイル（`*_fields.json`）が実際のKintoneアプリと同期しているか確認します。

```bash
cd <project_root>/Kintoneアプリ
python3 update_analysis.py
```
*注意: 特定のアプリのみを更新する場合は `--id <APP_ID>` を付けて実行してください。*

### 2. バリデーションスクリプトの実行
Kintoneスクリプト（特にフィールドマッピング）を修正した後は、ターゲットファイルに対してバリデーターを実行します。

```bash
cd <project_root>/Kintoneアプリ
node validate_field_mapping.js <TARGET_SCRIPT_RELATIVE_PATH>
```

**例:**
```bash
node validate_field_mapping.js <APP_ID>_<アプリ名>/<スクリプト名>.js
```

### 3. 結果の解釈

- **✅ 検証成功 (SUCCESS)**: マッピングされたすべてのフィールドがアプリ内に存在します。続行可能です。
- **❌ 検証失敗 (FAILED)**: 
  - `[ERROR] Field "XXX" not found`: スクリプトが参照しているフィールドコード "XXX" が、対象アプリのスキーマ内に存在しません。
  - **アクション**: 手順1で更新した `Kintoneアプリ/<APP_ID>_.../*_fields.json` を確認し、正しいフィールドコードを見つけてスクリプトを更新してください。表形式で確認する場合は `kintone_app_analysis` の成果物 `Kintoneアプリ/<APP_ID>_.../APP_REPORT.md` を参照する（古い場合は再生成する）。

## 重要なルール
- **絶対に**バリデーションエラーを無視しないでください。バリデーターが警告を出す場合、コードが間違っているか、スキーマが古いかのどちらかです。
- ローカルの定義が古い疑いがある場合は、**必ず**スキーマを更新（`python3 update_analysis.py`）してください。

---

環境乖離・異常検知時は `rules/git_safety.md` 2.8「環境乖離・異常検知時の停止義務」に従う。
