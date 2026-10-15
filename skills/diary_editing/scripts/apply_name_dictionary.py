#!/usr/bin/env python3
"""
apply_name_dictionary.py - 固有名詞・表記ゆれ辞書をテキストに適用する決定論的ツール
"""

import os
import sys
import json
import argparse
from pathlib import Path

DEFAULT_DICT_PATH = Path(__file__).resolve().parent.parent / "references" / "name_dictionary.json"

def load_dictionary(dict_path):
    if not os.path.exists(dict_path):
        raise FileNotFoundError(f"Dictionary file not found: {dict_path}")
    with open(dict_path, "r", encoding="utf-8") as f:
        return json.load(f)

def apply_replacements(text, mapping):
    """
    辞書に従って置換を実行し、置換後テキストと置換ログを返す。
    キー長の降順で置換することで部分一致の誤爆を防ぐ。
    """
    sorted_keys = sorted(mapping.keys(), key=lambda k: len(k), reverse=True)
    logs = []
    result = text
    for key in sorted_keys:
        target = mapping[key]
        if key == target:
            continue
        count = result.count(key)
        if count > 0:
            result = result.replace(key, target)
            logs.append({"before": key, "after": target, "count": count})
    return result, logs

def main():
    parser = argparse.ArgumentParser(description="固有名詞・表記統一辞書の一括適用スクリプト")
    parser.add_argument("file", nargs="?", help="対象テキストファイルパス（省略時は標準入力）")
    parser.add_argument("--dict", default=str(DEFAULT_DICT_PATH), help="辞書JSONのパス")
    parser.add_argument("--inplace", "-i", action="store_true", help="ファイルを直接上書きする")
    parser.add_argument("--check", "-c", action="store_true", help="置換を実行せず、該当箇所のみ報告する")
    args = parser.parse_args()

    mapping = load_dictionary(args.dict)

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    new_content, logs = apply_replacements(content, mapping)

    if args.check:
        if not logs:
            print("OK: 表記ゆれ・辞書対象語句は見つかりませんでした。")
            sys.exit(0)
        else:
            print(f"WARN: {len(logs)} 件の表記統一候補が見つかりました:")
            for log in logs:
                print(f"  - '{log['before']}' -> '{log['after']}' ({log['count']} 箇所)")
            sys.exit(1)

    if args.inplace and args.file:
        with open(args.file, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"Applied {len(logs)} replacements to {args.file}")
    else:
        sys.stdout.write(new_content)

if __name__ == "__main__":
    main()
