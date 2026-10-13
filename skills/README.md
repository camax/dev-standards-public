# skills/ 一覧

このディレクトリは、複数プロジェクトで有用な「エージェント向けスキル」を集約したもの。
各スキルは自動読込されない。スキル索引の正はこのファイルで、`CLAUDE.md` / `AGENTS.md` の「必要時に参照」はここを指す1行のみ。スキルを追加・改名・削除したら下表を更新すること。
タスクの性質に応じて該当する `SKILL.md` を読み込んで適用すること。

## 汎用スキル

| スキル | 一行説明 |
|---|---|
| [csv_handling](./csv_handling/SKILL.md) | CSVファイルを扱う際のエンコーディング・区切り文字などの標準手順 |
| [requirements_evolve](./requirements_evolve/SKILL.md) | 開発中に決定した要件・仕様変更を `requirements.md` 等へ即時記録し、エージェント間で共有する |
| [anti_regression_protocol](./anti_regression_protocol/SKILL.md) | 修正前にGitベースラインを確保し、スコープを限定して実装、diff監査・ビルド検証まで行うデグレ防止の統合フロー（旧 safe_development を統合） |
| [git_safe_renaming](./git_safe_renaming/SKILL.md) | `git mv` を用いてGit履歴を維持したままファイル名変更（日付サフィックス除去等）を行う手順 |
| [implementation_fidelity](./implementation_fidelity/SKILL.md) | デプロイ・タスク完了前に、解析/要件定義の内容が実装コードに正しく反映されているかをgrep等で検証する |
| [comparative_schema_analysis](./comparative_schema_analysis/SKILL.md) | 新しい連携先を追加する際、既存の類似モデルと比較してフィールド・仕様の漏れを防ぐ |
| [proactive_communication](./proactive_communication/SKILL.md) | 確認待ち・検証待ちの際に「次のアクション」まで予告し、停滞と手戻りを防ぐ報告スタイル |
| [logic_fidelity_verification](./logic_fidelity_verification/SKILL.md) | 重要ロジックのリファクタリング・移行時に、新旧の出力データを比較して論理の欠落やデグレを防ぐ |

## Kintone案件固有スキル（`kintone_ops/`）

Kintoneを使う案件に強く依存した手順のため、汎用スキルとは別ディレクトリに隔離している。
他スタックの案件では読み込む必要はない。

| スキル | 一行説明 |
|---|---|
| [kintone_ops/app_analysis](./kintone_ops/app_analysis/SKILL.md) | KintoneアプリIDからフィールド・一覧・JS依存関係のレポートを自動生成する |
| [kintone_ops/field_validation](./kintone_ops/field_validation/SKILL.md) | Kintoneスクリプトのフィールドマッピングと実際のアプリスキーマを突合検証する |
| [kintone_ops/mapping_regression_prevention](./kintone_ops/mapping_regression_prevention/SKILL.md) | 全媒体共通のマッピング設定を改修する際、スナップショット比較で他媒体への影響がないことを証明する |
| [kintone_ops/legacy_js_analysis](./kintone_ops/legacy_js_analysis/SKILL.md) | 既存Kintone JSのリファクタリング時に4フェーズ（棚卸し・解析・検証・疑義抽出）で漏れを防ぐ |

### Kintone関連スキルの使い分け（`kintone_ops/` 4本 + `logic_fidelity_verification`）

`kintone_ops/` 配下の name は `kintone_` + ディレクトリ名とする。参照の向きは kintone 側から汎用側に限り、`logic_fidelity_verification` には Kintone 固有の手順を書かない。

| スキル（name） | 使うとき | 主な成果物 | 使わないとき（代わりに使うスキル） |
|---|---|---|---|
| `kintone_app_analysis` | 既存アプリのIDからフィールド・一覧・JS/CSSを把握するとき（要件定義・改修の調査段階） | `APP_REPORT.md`（スキーマ資料の正本） | JSロジックの解析 → `kintone_legacy_js_analysis`／コードとスキーマの突合 → `kintone_field_validation`／アプリIDのない設計段階のレビュー → 該当スキルなし |
| `kintone_field_validation` | Kintone JSのフィールドコード参照を追加・変更した後、デプロイ前 | バリデーター出力（SUCCESS / FAILED） | 新旧フィールドコードの対応比較 → `logic_fidelity_verification`／要件のgrep確認 → `implementation_fidelity` |
| `kintone_legacy_js_analysis` | 既存Kintone JSのリファクタリング・大幅な書き換え | `analysis_report_<filename>.md` | 1〜数行の単発修正 → `anti_regression_protocol`／出力データの新旧比較 → `logic_fidelity_verification` |
| `kintone_mapping_regression_prevention` | 全媒体共通の判定関数・`KINTONE_FIELD_MAP`・`*Util.js` の改修 | `mapping_snapshot.json` と verify 結果 | 媒体共通でない新旧出力比較 → `logic_fidelity_verification`／新規連携先のフィールド洗い出し → `comparative_schema_analysis` |
| `logic_fidelity_verification`（汎用） | 価格・税・在庫等の重要ロジックやデータマッピングのリファクタリング・移行（Kintone以外も対象） | `logic_comparison_table.md`、`field_mapping_audit.md` | 単発修正のdiff監査 → `anti_regression_protocol`／要件のgrep確認 → `implementation_fidelity`／Kintoneの全媒体共通マッピング → `kintone_mapping_regression_prevention` |

## 日記・SNS編集スキル

開発ルールとは独立した、日記・SNS投稿の編集用スキル。`config/user_profile.yaml.example` をコピーして `config/user_profile.yaml` を作り、自分の値を設定する。個人設定とアバター参照画像は追跡対象外。学習ファイルはルール0件と架空のダミー事例1件から始める。

| スキル | 一行説明 |
|---|---|
| [diary_editing](./diary_editing/SKILL.md) | 音声入力の日記テキストを note・SNS 向けに編集する |
| [sns_editorial](./sns_editorial/SKILL.md) | 日記や過去ログから、一次情報に基づくSNS投稿を編集する |
