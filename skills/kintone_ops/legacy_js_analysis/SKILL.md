---
name: kintone_legacy_js_analysis
description: "既存のKintoneカスタマイズJSをリファクタリング・大幅に書き換えるとき、静的解析による棚卸し→関数ごとのロジック・副作用・例外の解析→修正後コードからの仕様逆生成と比較→疑義リストでのユーザー確認の4フェーズで、ロジック漏れと副作用を防ぐスキル。ユーザーが「既存JSをリファクタリング」「Kintone JSを整理」「既存JSを解析」「既存JSを書き換え」と言及したら必ず使用すること。1〜数行の単発修正はanti_regression_protocol、価格・税等の出力データの新旧比較はlogic_fidelity_verificationを使う。"
---

# 既存JS解析スペック（Kintoneカスタマイズ向け）

## Overview

JSファイル修正・リファクタリング時の厳格な検証プロセスです。
AIの目視漏れを防ぎ、ロジックの完全性を担保するために、以下の4フェーズを**必ず**実行してください。

## Prerequisites

- `.agent/skills/kintone_ops/legacy_js_analysis/scripts/static_parser.py` を使用します。このスクリプトは本リポジトリには同梱していません。各プロジェクト側で別途用意する前提です。

## Process

### Phase 1: Inventory (リスト作成)

まず、対象ファイルの物理的な構造（関数、変数、イベントハンドラ）を完全に洗い出します。AIの「なんとなく」の理解ではなく、機械的なリストを作成します。

1. **Run Static Parser**:
   以下のコマンドを実行し、対象ファイルの構造情報をJSONとして取得・保存します。

   ```bash
   python .agent/skills/kintone_ops/legacy_js_analysis/scripts/static_parser.py <path_to_js_file> > inventory.json
   ```

2. **Manual Inventory Check**:
   パーサーで抽出できなかった動的な定義や、イベントリスナー（`kintone.events.on` 等）を目視で確認し、リストに追加します。

### Phase 2: Analysis (解析)

リストアップされた各アイテム（関数・処理ブロック）について、以下の観点で解析を行い、マークダウンにまとめます。

- **Logic**: 何をする処理か？（入力 -> 処理 -> 出力）
- **Side Effects**: 外部への影響はあるか？（DOM操作、APIコール、Global変数変更）
- **Exceptions**: エラーハンドリングはされているか？異常系はどう振る舞うか？

**Output Example**:

```markdown
## Function: `calculatePrice`
- **Logic**: Takes `basePrice` and `tax`, returns total.
- **Side Effects**: None.
- **Exceptions**: Returns -1 if inputs are invalid.
```

### Phase 3: Verification (バックトランスレーション検証 & データ検証)

修正案（またはリファクタリング後のコード）を作成した後、その新しいコードから「逆に仕様を読み解く」ことで、元の意図が保たれているか検証します。また、実データの整合性も確認します。

1. **仕様の逆生成 (Reverse Spec Generation)**: 新しいコードを見て、「何をするコードか」を言語化する。
2. **比較 (Comparison)**: Phase 2で作った解析結果（元の仕様）と、1で生成した仕様を突き合わせる。
   - 機能が落ちていないか？
   - 意図しない副作用が増えていないか？
   - エラー処理が消えていないか？
3. **データ検証 (Data Verification)**:
   - 新しい修正が入る時は、そのデータの確認も含めて行うこと。
   - 実際に生成されるデータ形式、値、ログ出力が要件を満たしているか確認手順を策定・実行する。

### Phase 4: Doubt List (疑義抽出)

解析プロセス中に少しでも「不明瞭」「リスクがある」「仕様が変」と感じた点は、全て **Doubt List** として記録し、ユーザーに確認を求めます。
勝手に推測して実装を進めることは禁止です。

---

## Output Artifact

このプロセスを実行した結果は、必ずアーティファクト（Markdownファイル）として残してください。
**格納場所**: 対象のJSファイルが格納されているフォルダ
例: `<js_file_directory>/analysis_report_<filename>.md`

---

環境乖離・異常検知時は `rules/git_safety.md` 2.8「環境乖離・異常検知時の停止義務」に従う。
