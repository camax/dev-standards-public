---
name: sns_editorial
description: "Obsidianの日記・過去ログを横断検索し、本人の一次情報と発言だけを根拠にX本アカウント・Xビジネス・Threads・Instagram向け投稿を企画・執筆・監査するスキル。search_voice.pyによる一次情報の引き当て、文体監査・事実照合、見送り候補のストック管理を含む。ユーザーが「SNS投稿を作って」「過去ログから投稿ネタ」「テーマ別に投稿」「Xビジネス」「投稿ストック」と言及したら必ず使用すること。日記を書いた直後の投稿化はdiary_editing、過去ログを横断・テーマ別に掘り出す投稿化は本スキルを使う。当日の日記の整形やnote記事化には本スキルを使わない。"
---

# SNS Editorial Skill (`sns_editorial`)

Obsidianの日記（一次情報）を起点とし、過去の生の声・実績を横断して、
**「AIは新しい意見を作らず、本人の実体験と本人の発言を編集する」**
という鉄則に従ってSNS投稿を企画・執筆・画像制作・監査するスキルです。

---


> [!TIP]
> **ファイルの読み込み方**: 本スキルの追加モジュールは、本 SKILL.md が配置されているディレクトリ（<skill_root>）からの相対パスで記載されています。view_file 等のツールで読み込む際は、本 SKILL.md の親ディレクトリパス（`<skill_root>`）を起点として絶対パスを指定してください。

## 個人設定の読み込み

実行前にリポジトリルートの `config/user_profile.yaml` を YAML として読み込む。別の場所に置く場合は `DEV_STANDARDS_PROFILE` に絶対パスを設定する。未作成なら `config/user_profile.yaml.example` をコピーして編集し、設定できるまで個人向け出力を始めない。設定ファイルと参照画像は Git に含めない。
本文中の `{key}` と `{parent.child}` は、読み込んだ YAML の値への参照を示す**エージェント向け記法**であり、Markdown の自動展開機能ではない。出力前にエージェントが辞書をキーごとにたどり、文字列値へ置換する。例: `{podcast_urls.youtube}` は `profile["podcast_urls"]["youtube"]`、`{editing_log_dir}` は `profile["editing_log_dir"]`。キー欠落・空文字なら推測で補わず設定を確認する。置換前の `{...}` を記事や投稿に残さない。
`vault_path` を Vault の場所として使い、検索スクリプトを呼ぶときは `OBSIDIAN_ROOT` に設定する。`editing_log_dir` は Vault からの相対パス。

## 🧭 動的モジュール・ロード表（トークン最適化ルール）

本スキルはトークン消費を最小化するため、**依頼内容に応じて必要なモジュールのみを読み込んで実行**します。全ファイルを一度に読み込まないでください。

| 実行タスク | 必須読み込みファイル | 任意参照（必要時のみ） |
| :--- | :--- | :--- |
| **X本アカウント投稿作成** | `core.md` + `channels/x_personal.md` + `workflows/draft.md` | — |
| **Threads投稿作成** | `core.md` + `channels/threads.md` + `workflows/draft.md` | — |
| **Instagram投稿作成** | `core.md` + `channels/instagram.md` + `workflows/draft.md` | — |
| **Xビジネス投稿作成** | `core.md` + `channels/x_business.md` + `workflows/draft.md` | 迷った時のみ: `references/approved_cases.md` |
| **全媒体一括候補選定** | `core.md` + `channels/*.md` + `workflows/draft.md` | — |
| **Phase 1 自動パイプライン** | 上記一括 + `workflows/lineage_tracking.md` | — |

---

## 🚦 基本実行ステップ

1. **対象媒体の特定**: ユーザーの依頼から生成対象の媒体を特定する。
2. **モジュールの動的ロード**: 上記ロード表に従い、必要なモジュールのみを読み込む（関係ない他媒体のファイルは読まない）。
3. **一次情報の検索・引き当て**: 必須スクリプト `search_voice.py` を呼び出し、対象テーマの一次情報原文を特定する。（※注意: 一次情報の検索は必ずこのスクリプトを使うこと。`grep`や`find`による全体検索は、外部情報の混入を防ぐため絶対禁止）
4. **ドラフト生成**: 読み込んだ媒体ルールに従って投稿案を作成する。
5. **機械的監査**: `check_writing_style.py`（文体）および `verify_lineage.py`（事実照合）を適用する。
6. **出力**: `workflows/draft.md` のフォーマットに従って出力する。見送り候補があれば `workflows/stock_management.md` の分類に従って記録する。

## 📌 新規ノート作成時のフロントマター規約（ObsidianVault/AGENTS.md準拠）

本スキルが`SNS運用/投稿候補`等にVault内の**新規ファイル**を作成する場合は、
ObsidianVaultルートの`AGENTS.md`に従い、以下の最小フロントマターを付与する。
**既存の日記・ログファイルへの遡及付与は行わない。**

```yaml
---
tags: [sns-draft, <媒体名。例: x, threads, instagram>]
status: draft
source: "[[一次情報として引用した日記/ポッドキャストノートへのWikilink]]"
---
```

