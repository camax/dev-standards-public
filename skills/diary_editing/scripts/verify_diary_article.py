#!/usr/bin/env python3
"""
verify_diary_article.py - note用整形記事と原文の定量的・機械的整合性を検証する決定論的監査ツール

検査項目:
1. 日付整合性（ファイル名のYYYYMMDDとH1見出しの日付一致）
2. 実測文字数比率（保持率 >= 95% の機械的計算）
3. 原文未収録語彙・表現の検出（カタカナ・漢字複合語の新出チェック）
4. 構成フォーマット検査（タイトル、あらすじ、フッターPodcast等の必須要素）
"""

import os
import re
import sys
import argparse
from pathlib import Path

def extract_date_from_filename(filename):
    """ファイル名からYYYYMMDDを抽出"""
    m = re.search(r"(\d{4})(\d{2})(\d{2})", filename)
    if m:
        return f"{m.group(1)}年{int(m.group(2))}月{int(m.group(3))}日", f"{m.group(1)}{m.group(2)}{m.group(3)}"
    return None, None

def extract_date_from_h1(text):
    """H1見出しから日付表現を抽出"""
    for line in text.splitlines():
        if line.startswith("# "):
            m = re.search(r"(\d{4})年(\d{1,2})月(\d{1,2})日", line)
            if m:
                return f"{m.group(1)}年{int(m.group(2))}月{int(m.group(3))}日", f"{m.group(1)}{int(m.group(2)):02d}{int(m.group(3)):02d}"
            m2 = re.search(r"(\d{4})[-/](\d{1,2})[-/](\d{1,2})", line)
            if m2:
                return f"{m2.group(1)}年{int(m2.group(2))}月{int(m2.group(3))}日", f"{m2.group(1)}{int(m2.group(2)):02d}{int(m2.group(3)):02d}"
    return None, None

def clean_text_for_counting(text):
    """文字数カウント用にマークダウン装飾・空白・改行を除外"""
    # 見出し記号、水平線、箇条書き記号を除去
    t = re.sub(r"^#+\s*", "", text, flags=re.MULTILINE)
    t = re.sub(r"^---+\s*$", "", t, flags=re.MULTILINE)
    t = re.sub(r"^[-*]\s*", "", t, flags=re.MULTILINE)
    # 空白文字を除去
    t = re.sub(r"\s+", "", t)
    return t

def extract_body_content(edited_text):
    """あらすじ・フッターを除いた純粋な本文テキストを抽出"""
    lines = edited_text.splitlines()
    body_lines = []
    in_synopsis = False
    in_footer = False

    for line in lines:
        stripped = line.strip()
        if "あらすじ" in stripped:
            in_synopsis = True
            continue
        if in_synopsis:
            if stripped.startswith("---") or stripped.startswith("### "):
                in_synopsis = False
            else:
                continue

        if "Podcast" in stripped or "▼ Podcast" in stripped or "### タグ" in stripped:
            in_footer = True
            continue
        if in_footer:
            continue

        body_lines.append(line)

    return "\n".join(body_lines)

def extract_vocab_tokens(text):
    """カタカナ語、漢字熟語（2文字以上）、英単語を抽出"""
    tokens = set()
    # カタカナ語（2文字以上）
    for m in re.finditer(r"[ァ-ヴー]{2,}", text):
        tokens.add(m.group(0))
    # 漢字熟語（2文字以上）
    for m in re.finditer(r"[\u4e00-\u9faf]{2,}", text):
        tokens.add(m.group(0))
    # 英字単語（3文字以上）
    for m in re.finditer(r"[A-Za-z0-9_]{3,}", text):
        tokens.add(m.group(0))
    return tokens

def verify_diary_article(original_text, edited_text, filename=""):
    results = {
        "passed": True,
        "date_check": {"status": "PASS", "detail": ""},
        "retention_check": {"status": "PASS", "detail": ""},
        "vocab_check": {"status": "PASS", "detail": "", "unrecorded_tokens": []},
        "format_check": {"status": "PASS", "detail": ""}
    }

    # 1. 日付整合性チェック
    fn_display, fn_compact = extract_date_from_filename(filename)
    h1_display, h1_compact = extract_date_from_h1(edited_text)

    if fn_compact and h1_compact:
        if fn_compact != h1_compact:
            results["passed"] = False
            results["date_check"] = {
                "status": "FAIL",
                "detail": f"日付不一致: ファイル名={fn_display} vs H1見出し={h1_display}"
            }
        else:
            results["date_check"]["detail"] = f"一致確認: {fn_display}"
    elif not h1_compact:
        results["date_check"] = {
            "status": "WARN",
            "detail": "H1見出しに日付表記が見つかりませんでした。"
        }
    else:
        results["date_check"]["detail"] = f"ファイル名から日付が判定不能（H1: {h1_display}）"

    # 2. 実測文字数比率チェック（保持率 >= 95%）
    orig_clean = clean_text_for_counting(original_text)
    body_text = extract_body_content(edited_text)
    body_clean = clean_text_for_counting(body_text)

    orig_len = len(orig_clean)
    body_len = len(body_clean)
    retention_rate = (body_len / orig_len * 100) if orig_len > 0 else 0

    results["retention_check"]["orig_len"] = orig_len
    results["retention_check"]["body_len"] = body_len
    results["retention_check"]["rate"] = retention_rate

    if retention_rate < 95.0:
        results["passed"] = False
        results["retention_check"]["status"] = "FAIL"
        results["retention_check"]["detail"] = f"保持率 {retention_rate:.1f}% (< 95.0% 基準未達・要約検出)"
    else:
        results["retention_check"]["detail"] = f"保持率 {retention_rate:.1f}% (>= 95.0% 基準達成)"

    # 3. 原文未収録語彙チェック
    orig_tokens = extract_vocab_tokens(original_text)
    edited_tokens = extract_vocab_tokens(body_text)
    unrecorded = sorted(list(edited_tokens - orig_tokens))

    # 一般的なフォーマット語彙・マークダウン語彙を除外
    common_ignore = {"今日", "昨日", "明日", "時間", "自分", "開発", "作業", "写真", "記録", "振り返り"}
    filtered_unrecorded = [t for t in unrecorded if t not in common_ignore and len(t) >= 2]

    results["vocab_check"]["unrecorded_tokens"] = filtered_unrecorded
    if filtered_unrecorded:
        results["vocab_check"]["status"] = "WARN"
        results["vocab_check"]["detail"] = f"{len(filtered_unrecorded)} 個の原文未収録語彙を検出（捏造・勝手な言い換えの確認要）"
    else:
        results["vocab_check"]["detail"] = "新出の不審な語彙は検出されませんでした。"

    # 4. 構成フォーマット検査
    format_issues = []
    if not re.search(r"^#\s+", edited_text, re.MULTILINE):
        format_issues.append("H1見出しタグ（# ）がありません。")
    if "あらすじ" not in edited_text:
        format_issues.append("あらすじセクションがありません。")
    if "###" not in body_text:
        format_issues.append("本文ブロック見出し（###）がありません。")
    if "#" not in edited_text.splitlines()[-1] and "タグ" not in edited_text:
        format_issues.append("末尾ハッシュタグ行が確認できません。")

    if format_issues:
        results["passed"] = False
        results["format_check"]["status"] = "FAIL"
        results["format_check"]["detail"] = "; ".join(format_issues)
    else:
        results["format_check"]["detail"] = "タイトル・あらすじ・見出し・タグ構成正常"

    return results

def main():
    parser = argparse.ArgumentParser(description="note用記事の定量的・機械的整合性検証ツール")
    parser.add_argument("--original", "-o", required=True, help="原文テキストファイルパス")
    parser.add_argument("--edited", "-e", required=True, help="整形後テキストファイルパス")
    args = parser.parse_args()

    with open(args.original, "r", encoding="utf-8") as f:
        orig_text = f.read()

    with open(args.edited, "r", encoding="utf-8") as f:
        edited_text = f.read()

    filename = Path(args.original).name
    res = verify_diary_article(orig_text, edited_text, filename)

    print("=== note記事 決定論的検証レポート ===")
    print(f"1. 日付整合性: [{res['date_check']['status']}] {res['date_check']['detail']}")
    ret = res["retention_check"]
    print(f"2. 文字数比率: [{ret['status']}] 原文={ret.get('orig_len',0)}字 / 出力={ret.get('body_len',0)}字 -> {ret['detail']}")
    voc = res["vocab_check"]
    print(f"3. 原文未収録語彙: [{voc['status']}] {voc['detail']}")
    if voc["unrecorded_tokens"]:
        print(f"   未収録候補: {', '.join(voc['unrecorded_tokens'][:15])}{'...' if len(voc['unrecorded_tokens']) > 15 else ''}")
    fmt = res["format_check"]
    print(f"4. 構成フォーマット: [{fmt['status']}] {fmt['detail']}")

    if res["passed"]:
        print("\n総合判定: PASS (合格)")
        sys.exit(0)
    else:
        print("\n総合判定: FAILED (不合格 - 要修正)")
        sys.exit(1)

if __name__ == "__main__":
    main()
