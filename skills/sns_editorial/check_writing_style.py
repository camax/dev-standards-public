#!/usr/bin/env python3
"""
check_writing_style.py - 文体ルール・文字数・禁止タグ・AI構文を機械的・決定論的に監査するLintツール
"""

import re
import sys
import argparse
from pathlib import Path

# 禁止タグ
BANNED_TAGS = ["#note", "#日記", "#日常"]

# AI特有のクリシェ構文
AI_CLICHE_PATTERNS = [
    (re.compile(r"ではないだろうか"), "AI特有の曖昧な問題提起（『〜ではないだろうか』）"),
    (re.compile(r"と言えるだろう"), "AI特有の推測結び（『〜と言えるだろう』）"),
    (re.compile(r"が重要だ"), "AI特有の説教調・一般論化（『〜が重要だ』）"),
    (re.compile(r"に違いない"), "AI特有の決めつけ（『〜に違いない』）"),
    (re.compile(r"思いがけない昔話を聞く時間になった"), "AI特有の安易な綺麗まとめ"),
    (re.compile(r"ぜひ立ち寄りたい"), "広告・観光メディア調コピー"),
]

# 敬体（です・ます調）の検知パターン
POLITE_STYLE_PATTERN = re.compile(
    r"(です|ます|でした|ました|でしょう|ですね|ますね|ですよね|でしょうか)[。！？\?\!\s]*$"
)

# 許容外の一人称（基本は「俺」）
NON_STANDARD_FIRST_PERSON = [
    (re.compile(r"自分は"), "一人称ブレ（『自分は』→『俺は』推奨）"),
    (re.compile(r"(^|[^\w])私([^\w]|$)"), "一人称ブレ（『私』→『俺』推奨）"),
    (re.compile(r"(^|[^\w])僕([^\w]|$)"), "一人称ブレ（『僕』→『俺』推奨）"),
]

def check_writing_style(text, platform="common"):
    """
    テキストの文体・文字数・タグを検証する。
    戻り値: (violations, stats)
    """
    violations = []
    lines = text.splitlines()

    # 1. 禁止タグのチェック
    for i, line in enumerate(lines, 1):
        for banned in BANNED_TAGS:
            if banned in line:
                violations.append({
                    "line": i,
                    "rule": "禁止タグ",
                    "detail": f"禁止されているタグ '{banned}' が含まれています。",
                    "snippet": line.strip()
                })

    # 2. 敬体（です・ます）チェック（常体ルールのプラットフォーム）
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("-") or stripped.startswith(">"):
            continue
        # 各文ごとに分割してチェック（句点区切り）
        sentences = re.split(r"[。！？\n]", stripped)
        for s in sentences:
            s = s.strip()
            if not s:
                continue
            if POLITE_STYLE_PATTERN.search(s):
                violations.append({
                    "line": i,
                    "rule": "敬体排除（常体徹底）",
                    "detail": f"です・ます調（敬体）が検出されました: '{s}'",
                    "snippet": s
                })

    # 3. AI特有構文チェック
    for i, line in enumerate(lines, 1):
        for pattern, desc in AI_CLICHE_PATTERNS:
            if pattern.search(line):
                violations.append({
                    "line": i,
                    "rule": "AI構文排除",
                    "detail": desc,
                    "snippet": line.strip()
                })

    # 4. 一人称ブレチェック（日記・個人アカウント時）
    if platform in ("common", "x_personal", "diary"):
        for i, line in enumerate(lines, 1):
            for pattern, desc in NON_STANDARD_FIRST_PERSON:
                if pattern.search(line):
                    violations.append({
                        "line": i,
                        "rule": "一人称統一",
                        "detail": desc,
                        "snippet": line.strip()
                    })

    # 5. プラットフォーム固有の文字数チェック
    url_pattern = re.compile(r"https?://\S+")
    urls = url_pattern.findall(text)
    # X上ではURLは一律23文字換算
    text_without_urls = url_pattern.sub("", text).strip()
    char_count_body = len(text_without_urls)
    # Xの全角文字数換算（概算: ASCII文字は0.5、全角は1）
    weighted_length = sum(0.5 if ord(c) < 128 else 1 for c in text_without_urls) + (len(urls) * 11.5)

    stats = {
        "lines": len(lines),
        "chars_body": char_count_body,
        "weighted_x_chars": int(weighted_length),
        "url_count": len(urls)
    }

    if platform in ("x_personal", "x_business"):
        # 本文全角100文字前後/以内
        if char_count_body > 115:
            violations.append({
                "line": "-",
                "rule": "X文字数超過（本文目安オーバー）",
                "detail": f"本文文字数が {char_count_body} 字です（全角100文字前後・目安以内推奨）。",
                "snippet": ""
            })
        if weighted_length > 140:
            violations.append({
                "line": "-",
                "rule": "X投稿制限超過（ハードリミット）",
                "detail": f"全角換算で {weighted_length:.1f} 字（最大140字）を超過しています。",
                "snippet": ""
            })

    return violations, stats

def main():
    parser = argparse.ArgumentParser(description="文体ルール・文字数・禁止タグLintスクリプト")
    parser.add_argument("file", nargs="?", help="検査対象テキストファイル（省略時は標準入力）")
    parser.add_argument("--platform", default="common",
                        choices=["common", "x_personal", "x_business", "threads", "note", "diary"],
                        help="対象プラットフォーム")
    args = parser.parse_args()

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    violations, stats = check_writing_style(content, args.platform)

    print(f"=== 文体Lint結果 (Platform: {args.platform}) ===")
    print(f"統計: 本文文字数={stats['chars_body']}字 / X換算長={stats['weighted_x_chars']} / 行数={stats['lines']}")

    if not violations:
        print("OK: 文体ルール・禁止タグ・文字数制限すべてに合格しました。")
        sys.exit(0)
    else:
        print(f"FAILED: {len(violations)} 件のルール違反が検出されました:")
        for v in violations:
            loc = f"L{v['line']}" if v['line'] != "-" else "全般"
            print(f"  ❌ [{loc}] {v['rule']}: {v['detail']}")
            if v['snippet']:
                print(f"     > {v['snippet']}")
        sys.exit(1)

if __name__ == "__main__":
    main()
