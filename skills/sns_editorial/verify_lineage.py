#!/usr/bin/env python3
"""
verify_lineage.py - Lineage JSONの出典追跡（source_path, source_line, source_quote）を機械的・決定論的に検証する。
"""

import os
import sys
import json
import argparse
from pathlib import Path

def resolve_source_path(source_path_str, vault_root):
    path = Path(source_path_str)
    if path.is_absolute():
        return path
    # 相対パスの場合、vault_root からの相対、またはカレントディレクトリからの相対
    if vault_root:
        candidate = Path(vault_root) / path
        if candidate.exists():
            return candidate
    candidate_cwd = Path.cwd() / path
    if candidate_cwd.exists():
        return candidate_cwd
    return Path(vault_root) / path if vault_root else candidate_cwd

def verify_lineage_data(data, vault_root=None):
    """
    Lineageデータ（dictまたはlist）を検証する。
    戻り値: (errors, total_checks)
    """
    errors = []
    total_checks = 0

    items = data if isinstance(data, list) else [data]

    for item_idx, item in enumerate(items):
        post_id = item.get("post_id", f"item_{item_idx}")
        lineage_entries = item.get("lineage", [])
        if not lineage_entries and "source_quote" in item:
            # 単一エントリ形式への対応
            lineage_entries = [item]

        for entry_idx, entry in enumerate(lineage_entries):
            total_checks += 1
            claim = entry.get("claim", "")
            source_path_str = entry.get("source_path", "")
            source_line = entry.get("source_line")
            source_quote = entry.get("source_quote", "").strip()

            if not source_path_str:
                errors.append(f"[{post_id}] エントリ#{entry_idx+1}: source_path が指定されていません。")
                continue

            resolved_path = resolve_source_path(source_path_str, vault_root)
            if not resolved_path.exists():
                errors.append(f"[{post_id}] ファイルが見つかりません: {source_path_str} (解決先: {resolved_path})")
                continue

            try:
                with open(resolved_path, "r", encoding="utf-8") as f:
                    lines = f.readlines()
            except Exception as e:
                errors.append(f"[{post_id}] ファイル読み込みエラー ({resolved_path}): {e}")
                continue

            if not source_quote:
                errors.append(f"[{post_id}] エントリ#{entry_idx+1}: source_quote が空です。")
                continue

            # 1. 完全一致照合
            file_text = "".join(lines)
            if source_quote not in file_text:
                errors.append(
                    f"[{post_id}] 引用不一致: '{source_quote}' がファイル内に存在しません ({resolved_path.name})"
                )
                continue

            # 2. 行番号の整合性チェック（指定されている場合）
            if source_line is not None:
                try:
                    line_no = int(source_line)
                    # 1-indexed行番号の前後2行以内のバッファで存在を確認
                    start_idx = max(0, line_no - 3)
                    end_idx = min(len(lines), line_no + 2)
                    context_text = "".join(lines[start_idx:end_idx])
                    if source_quote not in context_text:
                        errors.append(
                            f"[{post_id}] 行番号ズレ警告: '{source_quote}' は指定行 {line_no} 付近に見つかりません（ファイル内の別行に存在します: {resolved_path.name}）"
                        )
                except ValueError:
                    errors.append(f"[{post_id}] 不正な行番号形式: {source_line}")

    return errors, total_checks

def main():
    parser = argparse.ArgumentParser(description="Lineage JSON 出典照合スクリプト")
    parser.add_argument("json_file", nargs="?", help="検証対象のLineage JSONファイル（省略時は標準入力）")
    parser.add_argument("--vault-root", default=os.environ.get("OBSIDIAN_ROOT", os.path.expanduser("~/Obsidian")),
                        help="Obsidian Vaultのルートディレクトリパス")
    args = parser.parse_args()

    if args.json_file:
        with open(args.json_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = json.load(sys.stdin)

    errors, total = verify_lineage_data(data, args.vault_root)

    print(f"=== Lineage 検証結果 (検証数: {total}) ===")
    if not errors:
        print("OK: すべての一次情報・引用の完全一致と実在が確認されました。")
        sys.exit(0)
    else:
        print(f"FAILED: {len(errors)} 件のエラー・不整合が検出されました:")
        for err in errors:
            print(f"  ❌ {err}")
        sys.exit(1)

if __name__ == "__main__":
    main()
