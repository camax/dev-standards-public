# AIスキル・アーキテクチャ最適化ナレッジ (SSOT)

本ドキュメントは、MacBook AirおよびMac mini環境におけるAIスキル・自動化基盤のSSOT（Single Source of Truth）、トークン最適化、およびデグレ防止設計を記録する正本ナレッジです。

---

## 1. 基本設計原則

1. **YAGNI / KISS の徹底**:
   - 新しいリポジトリや過剰な抽象化レイヤーを無駄に乱立させない。既存の `dev-standards` を唯一の正本（SSOT）リポジトリとして集約・管理する。
2. **決定論的処理とLLM推論の厳格な分離**:
   - 文字数カウント、文長チェック、一人称・常体の正規表現チェック、引用元（一次情報）の実在性照合は、Pythonスクリプト（`check_writing_style.py`, `verify_lineage.py`）により0トークン・ミリ秒単位で決定論的に実行する。
   - LLMには「長文の自己採点レポート」を書かせず、意味判断・構成・表現の推論のみに集中させる。
3. **コンテキストのモジュール化（動的ロード）**:
   - 巨大な単一 `SKILL.md`（28KB）を常時全量注入せず、薄いRouter（エントリポイント）と媒体別・工程別モジュールに分割し、リクエストに応じて必要なファイルのみを動的に読み込む。

---

## 2. スキルSSOTと配布アーキテクチャ

### 配置構成
```text
[SSOT正本 (Git管理)]
<repo_root>/skills/
├── sns_editorial/
│   ├── SKILL.md                 # ルーター (約700 tokens)
│   ├── core.md                  # 全媒体共通方針 (約1,500 tokens)
│   ├── channels/                # 各媒体固有ルール (各400〜1,700 tokens)
│   │   ├── x_personal.md
│   │   ├── threads.md
│   │   ├── instagram.md
│   │   └── x_business.md
│   ├── workflows/               # 業務フロー (draft, lineage, stock)
│   └── references/              # Few-shot実例 (通常は未ロード)
└── diary_editing/
    ├── SKILL.md                 # ルーター (約500 tokens)
    ├── core/                    # note生成・検証
    ├── workflows/               # アバター画像、SNS告知
    └── references/              # 学習ルール

[エージェント実行環境 (シンボリックリンク / 決定論的同期)]
~/.gemini/config/skills/  ──[symlink]──> dev-standards/skills/
~/.claude/skills/         ──[symlink]──> dev-standards/skills/
```

### 同期スクリプト
- `dev-standards/scripts/deploy_skills.py`
  - `--status`: 配備状況とリンク先の整合性を監査
  - `--link`: 正本から各エージェントディレクトリへ安全にシンボリックリンクを作成
  - `--copy`: オフライン用の実体コピーモード

---

## 3. トークン削減実績

| 実行タスク | 従来 (Before) | 最適化後 (After) | 削減率 |
| :--- | :--- | :--- | :--- |
| **X本アカウント作成** | 12,415 tokens | **6,746 tokens** | **-45.7% (▼ 5,669 tok)** |
| **Threads作成** | 12,415 tokens | **5,288 tokens** | **-57.4% (▼ 7,127 tok)** |
| **Instagram作成** | 12,415 tokens | **7,327 tokens** | **-41.0% (▼ 5,088 tok)** |
| **Xビジネス作成** | 12,415 tokens | **6,366 tokens** | **-48.7% (▼ 6,049 tok)** |
| **note記事生成 (Step 1)** | 12,017 tokens | **4,254 tokens** | **-64.6% (▼ 7,763 tok)** |
| **SNS告知文生成 (Step 4)** | 12,017 tokens | **2,401 tokens** | **-80.0% (▼ 9,616 tok)** |

---

## 4. 過去の事故と恒久防止策

- **`setup_macbook.sh` 逆上書き事故**:
  - iCloud側に古い `SKILL.md`（18KB）があり、ローカルに最新のルール（28KB）がある状態で単方向コピーを実行すると、最新ルールが上書き破壊される致命的構造が存在した。
  - **防止策**: `setup_macbook.sh` を即座に停止・バックアップ化。スキルの正本をGitリポジトリ（`dev-standards`）へ完全集約し、iCloudからのスクリプト上書きを廃止した。

---

## 5. エージェント別 Skill 参照状況（2026-09-16 確定）

| エージェント | Skillディレクトリ | SSOT連携 | 備考 |
|:---|:---|:---|:---|
| Antigravity IDE (Gemini) | `~/.gemini/config/skills/` | ✅ symlink済み | 主要AI実行環境 |
| Claude Code | `~/.claude/skills/` | ✅ symlink済み | |
| Codex CLI | `~/.codex/skills/` | ❌ 旧版実体コピー | 形式互換性確認未了。対応保留 |
| Antigravity CLI (`~/.agents/`) | `~/.agents/skills/` | ❌ 旧版実体コピー | skills.jsonは.claude/skillsを参照。diary_editingのみ存在 |

---

## 6. MacBook Air / Mac mini 役割分担（確定）

- **Obsidian Vault**: Markdown / Knowledge / Index のみ（runtime data, venv を置かない）
- **コードは Git で管理**（dev-standards。Mac miniにclone/pullして実行）
- **Mac mini**: 大容量 DB, CSV, ログ, venv（実行環境ごとに再構築）

---

## 7. 大容量データ移行原則（COPY → VERIFY → SWITCH → DELETE）

move 禁止。必ず下記順序で実施：
1. COPY: rsync --checksum で Mac mini にコピー
2. VERIFY: SHA-256 比較 + サイズ確認
3. TEST: 新パスで実際にスクリプト動作確認
4. SWITCH: .env で KABU_DATA_DIR 等を新パスに切り替え
5. HOLD: 最低2週間は旧データ維持
6. DELETE: ユーザー承認後のみ削除

iCloud はバックアップではない（30日バージョン履歴のみ）。

---

## 8. .pre_deploy.bak の管理方針

以下がすべて揃うまで削除しない：
1. Skill モジュール化の Git コミット
2. Gemini 実利用確認
3. Claude Code 実利用確認
4. Codex 対応確認（または対象外確定）

条件が揃ったら REMOVE_SAFE と再判定。永久にbakを増やす運用にしない。
