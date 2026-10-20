# goal_loop.sh 試験用計画（2026-10-06）

`scripts/goal_loop.sh plans/PLAN_goal_loop_trial.md` で上から順に実行する。
対象はバックログの低優先度項目2件。各項目の書式は `scripts/goal_loop.sh --help` を参照。

## 項目

- [x] update.sh を stack 対応にする（案B）
  背景: `init.sh` は client-delivery の `rules/git_safety.md` と `rules/coding_standards.md` を `strip_stack()` で加工して配布し、`.agent/project_type.conf` に `TYPE` / `STACK` を記録する。一方 `project_template/update.sh` は両ファイルを加工せず原本のまま同期するため、update.sh を実行すると stack=other のプロジェクトにも Kintone / GAS 固有の記述とマーカーが戻ってしまう。
  やること:
  - `update.sh` で `.agent/project_type.conf` の `STACK` を読み、`rules/git_safety.md` と `rules/coding_standards.md` を `init.sh` の `strip_stack()` と同じ規則で加工してから同期する（other: マーカーで囲まれたブロックを削除、kintone-gas: マーカー行だけ削除）。
  - 同期前に表示する diff も加工後の内容と比較する。加工済みの配布先に2回目の update.sh を実行したら「差分なし」になること。
  - `project_type.conf` が無い場合は WARNING を出し、従来どおり加工せずに同期する。`STACK` が kintone-gas / other 以外なら ERROR で中断する。
  - 既存の `DIST_EXCLUDE` の挙動（配布対象外ファイルの除外・除去）は変えない。
  - `tests/test_init_sh.sh` に上記のテストを追加する（グローバル pre-commit は .sh の変更にテストの変更を求める）。
  - 実態と合わなくなる記述を直す: `update.sh` 冒頭のコメント、`AGENTS.md` の「`update.sh` はどちらのファイルも strip せず丸ごと同期する」、`init.sh` が project_type.conf に書くコメント（「update.sh は現時点でこの値を参照しない」）。
  範囲外: TYPE（internal-only）への対応。`init.sh` はコメント以外変更しない（`--print-rules` の出力を変えない）。`rules/` は変更しない。
  <!-- verify: bash tests/goal_loop/verify_update_stack.sh && bash tests/test_init_sh.sh -->
  <!-- commit: feat: strip stack blocks in update.sh based on project_type.conf -->
  <!-- files: project_template/update.sh project_template/init.sh tests/test_init_sh.sh AGENTS.md -->

- [x] CLAUDE.md と AGENTS.md の「必要時に参照」節の重複を解消する
  背景: `CLAUDE.md` は末尾で `@AGENTS.md` を import しているのに、templates/ の参照行を含む「## 必要時に参照（自動読込しない）」節を AGENTS.md と同じ内容で持っている。Claude Code では同じ節が2回読み込まれ、片方だけ更新されるとずれる。`scripts/repo_checkup.sh --dup-files 2` で検知される。
  やること:
  - 正は `AGENTS.md`（Codex / Antigravity と共用で、import 構文が無いので削れない）とし、`CLAUDE.md` 側の節を削除して、AGENTS.md の同名節を参照する旨の短い記述に置き換える。
  - `CLAUDE.md` の `@rules/*.md` と `@AGENTS.md` の import はそのまま残す。`AGENTS.md` は変更しない。
  <!-- verify: bash tests/goal_loop/verify_claude_agents_dedup.sh -->
  <!-- commit: docs: remove duplicated reference list from CLAUDE.md -->
  <!-- files: CLAUDE.md -->
