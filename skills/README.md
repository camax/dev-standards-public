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
