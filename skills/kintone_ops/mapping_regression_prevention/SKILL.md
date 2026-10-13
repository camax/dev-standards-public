---
name: kintone_mapping_regression_prevention
description: "Kintone連携で全媒体（モール）共通の判定関数（*detectMedia*等）・KINTONE_FIELD_MAP等の共通マッピング設定・*Util.jsを改修するとき、改修前後で全媒体のマッピング結果をスナップショット比較し、他媒体へのデグレを防ぐスキル。ユーザーが「媒体を追加」「モールを追加」「KINTONE_FIELD_MAP」「共通マッピングを修正」と言及したら必ず使用すること。媒体共通でない新旧出力比較はlogic_fidelity_verification、新規連携先のフィールド洗い出しはcomparative_schema_analysisを使う。"
---

# Data Mapping Regression Prevention (データマッピング・デグレ防止プロトコル)

## 前提条件
- `tests/verify_mappings.js`（snapshot/verifyサブコマンドを持つスナップショット比較スクリプト）を使用します。このスクリプトは本リポジトリには同梱していません。各プロジェクト側で別途用意する前提です。

## 背景と目的
1つの新しい媒体（モール）を追加したり、共通の判定ロジック（例: `getValidatedMediaType`）を修正したりした際に、既存の他の媒体（媒体A、媒体B、媒体Cなど）のデータ連携が意図せず破損する「サイレントデグレード」を完全に防ぐこと。

修正対象が特定の媒体Aであっても、共通ファイルを触る以上、**すべての媒体B, C, Dの処理が今まで通り動くか**をシステム的に（人間の勘や手動テストに頼らず）証明しなければなりません。

---

# ROLE
You are a strict QA engineer. You MUST prioritize preventing regressions over speed.
You MUST follow the "One Step, One Action" rule. Do NOT execute all steps in a single response.

# TRIGGER
When you are about to modify ANY file matching these patterns:
- `*Util.js` (e.g. `PostShippingDataToKintoneUtil.js`)
- `*KINTONE_FIELD_MAP*`
- `*detectMedia*`

# ACTION (Execution Steps)
You must strictly execute these steps sequentially. **Wait for each step's tool call to finish and confirm the result in your next thought before moving to the next step.**

### Step 1. STOP CODING
Do not write or replace any code yet.

### Step 2. Snapshot the current state
Run command: `node tests/verify_mappings.js snapshot`
Read the output and ensure `mapping_snapshot.json` was created successfully.

### Step 3. Identify the impact
Use a code search tool to find all usages of the strings or functions you plan to change (e.g. `'MEDIA_A'` or `'媒体C'`).
Do NOT rely on your memory. Look at the actual search results.

### Step 4. Modify the target file
Make your intended modifications to the `*Util.js` or mapping files.

### Step 5. Verify no regressions
Run command: `node tests/verify_mappings.js verify`
Read the output.

# ASSERTION (Validation Rule)
- If Step 5 returns ANY error or `[FAIL]`, you MUST immediately revert your code changes or fix the broken mapping before doing anything else.
- You CANNOT ask the user for review or deployment until Step 5 outputs "SUCCESS" and "✅ All ... mappings matched perfectly." for every single media.

---

環境乖離・異常検知時は `rules/git_safety.md` 2.8「環境乖離・異常検知時の停止義務」に従う。
