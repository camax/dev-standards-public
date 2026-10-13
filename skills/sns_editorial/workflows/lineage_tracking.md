# 出典追跡（Lineage JSON）と多段階Fact Check仕様（Phase 1）

自動パイプライン実行時（または構造化出力要求時）は、テキスト出力に加えて以下のLineage JSONを出力し、機械的検証（`verify_lineage.py`）およびSQLite（`sns_operations.db`）へ永続化する：

```json
{
  "post_id": "x_personal_20260915_01",
  "platform": "x_personal",
  "content_text": "投稿本文...",
  "theme": "テーマ名",
  "angle": "切り口",
  "hook_pattern": "冒頭パターン",
  "lineage": [
    {
      "claim": "主張や文",
      "source_type": "note",
      "source_id": "note_xxx",
      "source_path": "Obsidian/20260915.md",
      "source_line": 34,
      "source_quote": "一次情報の完全一致引用",
      "layer": "A_fact" // A_fact | B_explicit_thought | C_latent_issue
    }
  ]
}
```
