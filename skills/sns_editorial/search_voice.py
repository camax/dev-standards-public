#!/usr/bin/env python3
import os
import re
import sys

# [2026-10-09 CHANGE] Vaultの場所を環境変数かホーム相対パスから解決する。
OBSIDIAN_ROOT = os.path.expanduser(os.environ.get("OBSIDIAN_ROOT", "~/Obsidian"))

def search_in_file(file_path, keywords):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return []

    matches = []
    for i, line in enumerate(lines):
        for kw in keywords:
            if kw in line:
                start = max(0, i - 1)
                end = min(len(lines), i + 2)
                context = []
                for j in range(start, end):
                    prefix = "> " if j == i else "  "
                    context.append(f"{j+1}:{prefix}{lines[j].rstrip()}")
                matches.append((file_path, i+1, "\n".join(context)))
                break
    return matches

def main():
    if len(sys.argv) < 2:
        print("Usage: python search_voice.py <keyword1> [keyword2 ...]")
        sys.exit(1)
        
    keywords = sys.argv[1:]
    root_pattern = re.compile(r'^\d{8}\.md$')
    targets = []
    
    if os.path.isdir(OBSIDIAN_ROOT):
        # 1. Root files ^\d{8}\.md$
        for fname in os.listdir(OBSIDIAN_ROOT):
            if root_pattern.match(fname):
                targets.append(os.path.join(OBSIDIAN_ROOT, fname))
                
        # 2 & 3. 日記note/ and podcast/
        for sub in ["日記note", "podcast"]:
            sub_dir = os.path.join(OBSIDIAN_ROOT, sub)
            if os.path.isdir(sub_dir):
                for root_dir, _, files in os.walk(sub_dir):
                    for f in files:
                        if f.endswith(".md"):
                            targets.append(os.path.join(root_dir, f))
                            
    targets.sort()
    
    all_matches = []
    for t in targets:
        m = search_in_file(t, keywords)
        if m:
            all_matches.extend(m)
            
    if not all_matches:
        print("No matches found.")
    else:
        for filepath, line_no, context in all_matches:
            print(f"\n--- Match in {filepath} (Line {line_no}) ---")
            print(context)

if __name__ == "__main__":
    main()
