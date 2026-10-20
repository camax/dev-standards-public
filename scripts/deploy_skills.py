#!/usr/bin/env python3
"""
deploy_skills.py
----------------
dev-standards/skills (SSOT正本) から
各AI環境へ安全にスキルを配備・同期し、全エージェントで重複ゼロ（各Skill 1回）を保証する決定論的スクリプト。

【対応環境とSkill Root】
  - Gemini (Antigravity): ~/.gemini/config/skills/ (Global root)
  - Claude Code: ~/.claude/skills/ (Global root)
  - Codex CLI: ~/.codex/skills/ (r0 root)
  ※ Codex は ~/.agents/skills (r1) も自動スキャンするため、重複防止として
    ~/.agents/skills 内の SSOT 管理対象スキルは ~/.agents/.backups/ へ安全退避する。

【安全原則】
  - バックアップは skills/ ディレクトリ内ではなく、親ディレクトリの .backups/ に配置する
    （skills/ 内に .bak があると、Gemini や Claude がサブディレクトリとして誤認・二重登録するため）
  - 削除は行わず、すべてタイムスタンプ付きで .backups/ へ退避 (shutil.move) する
  - dry-run で事前確認してから --link/--copy を実行可能
"""

import os
import sys
import shutil
import argparse
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
SOURCE_SKILLS_DIR = REPO_ROOT / "skills"

# 各AIツールの正規 Skill Root
TARGET_DIRS = [
    ("Gemini", Path(os.path.expanduser("~/.gemini/config/skills"))),
    ("Claude", Path(os.path.expanduser("~/.claude/skills"))),
    ("Codex", Path(os.path.expanduser("~/.codex/skills"))),
]

# Codex等の第2探索ルートなど、重複注入を引き起こす競合ディレクトリ
CONFLICT_CHECK_DIRS = [
    ("Agents (~/.agents/skills)", Path(os.path.expanduser("~/.agents/skills"))),
]

SKILLS_TO_DEPLOY = []


def get_status():
    print("=== Skill Deployment & Duplication Status ===")
    print(f"Source (SSOT): {SOURCE_SKILLS_DIR}\n")

    for name, target_dir in TARGET_DIRS:
        print(f"[{name}] Target: {target_dir}")
        if not target_dir.exists():
            print("  ❌ Target directory does not exist")
            continue

        # 誤検出を引き起こす skills/ 直下の .bak ディレクトリ検知
        stray_baks = list(target_dir.glob("*.pre_deploy.bak*"))
        if stray_baks:
            for sb in stray_baks:
                print(f"  🚨 STRAY BACKUP INSIDE SKILLS DIR: {sb.name} (May cause false discovery!)")

        for skill in SKILLS_TO_DEPLOY:
            p = target_dir / skill
            if not p.exists() and not p.is_symlink():
                print(f"  ⚪ {skill:<16}: NOT DEPLOYED")
            elif p.is_symlink():
                dest = p.resolve()
                is_correct = (dest == (SOURCE_SKILLS_DIR / skill).resolve())
                status = "🟢 SYMLINK (OK)" if is_correct else f"🚨 SYMLINK (MISMATCH -> {dest})"
                print(f"  {status:<24} {skill}")
            else:
                print(f"  🟡 DIRECTORY (Copy)     {skill}")
        print()

    print("--- Conflict / Secondary Scan Roots (Duplication Check) ---")
    for name, conflict_dir in CONFLICT_CHECK_DIRS:
        print(f"[{name}]: {conflict_dir}")
        if not conflict_dir.exists():
            print("  ⚪ Directory does not exist (OK)")
            continue
        for skill in SKILLS_TO_DEPLOY:
            p = conflict_dir / skill
            if p.exists() or p.is_symlink():
                print(f"  🚨 DUPLICATION RISK: {skill} exists here! (Codex will see duplicate skill)")
            else:
                print(f"  🟢 Clean (No conflict for {skill})")
        print()


def dry_run():
    print("=== DRY RUN (No changes will be made) ===")
    print(f"Source (SSOT): {SOURCE_SKILLS_DIR}\n")

    for name, target_dir in TARGET_DIRS:
        backup_root = target_dir.parent / ".backups"
        print(f"[{name}] Target: {target_dir}")
        print(f"  Backup Root: {backup_root}")

        # stray bak の退避プレビュー
        if target_dir.exists():
            for sb in target_dir.glob("*.pre_deploy.bak*"):
                print(f"  📦 Would move stray backup {sb.name} -> {backup_root}/")

        for skill in SKILLS_TO_DEPLOY:
            src = SOURCE_SKILLS_DIR / skill
            dst = target_dir / skill

            if not src.exists():
                print(f"  ❌ Source {src} not found — SKIP")
                continue

            if dst.is_symlink():
                dest = dst.resolve()
                if dest == src.resolve():
                    print(f"  ✨ Already correctly linked: {skill} -> {src}")
                else:
                    print(f"  🔄 Would update symlink: {skill} -> {src}")
            elif dst.exists():
                print(f"  📦 Would backup existing directory {skill} -> {backup_root}/, then create symlink")
            else:
                print(f"  🔗 Would create new symlink: {skill} -> {src}")
        print()

    print("--- Conflict Resolution (Preventing Duplication in Codex) ---")
    for name, conflict_dir in CONFLICT_CHECK_DIRS:
        backup_root = conflict_dir.parent / ".backups"
        print(f"[{name}]: {conflict_dir}")
        for skill in SKILLS_TO_DEPLOY:
            p = conflict_dir / skill
            if p.exists() or p.is_symlink():
                print(f"  📦 Would safely move {p} -> {backup_root}/ to ELIMINATE duplication in Codex")
            else:
                print(f"  🟢 Already clean for {skill}")
        print()


def deploy(use_symlink=True):
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    # 1. 競合ディレクトリ（~/.agents/skills）の重複解消（退避）
    print("=== 1. Conflict Cleanup (Eliminating Duplicates) ===")
    for name, conflict_dir in CONFLICT_CHECK_DIRS:
        if not conflict_dir.exists():
            continue
        backup_root = conflict_dir.parent / ".backups"
        for skill in SKILLS_TO_DEPLOY:
            p = conflict_dir / skill
            if p.exists() or p.is_symlink():
                backup_root.mkdir(parents=True, exist_ok=True)
                dest_backup = backup_root / f"{skill}_{ts}"
                shutil.move(str(p), str(dest_backup))
                print(f"  📦 Evacuated {name} {skill} -> {dest_backup}")

    # 2. 各正規ターゲットへの配備
    print("\n=== 2. Deploying Skills to Primary Roots ===")
    for name, target_dir in TARGET_DIRS:
        target_dir.mkdir(parents=True, exist_ok=True)
        backup_root = target_dir.parent / ".backups"
        backup_root.mkdir(parents=True, exist_ok=True)
        print(f"\n[{name}] ({target_dir})...")

        # stray backup の退避（skills/ 直下から .backups/ へ移動）
        for sb in target_dir.glob("*.pre_deploy.bak*"):
            dest_sb = backup_root / f"{sb.name}_{ts}"
            shutil.move(str(sb), str(dest_sb))
            print(f"  📦 Moved stray backup: {sb.name} -> {dest_sb}")

        for skill in SKILLS_TO_DEPLOY:
            src = SOURCE_SKILLS_DIR / skill
            dst = target_dir / skill

            if not src.exists():
                print(f"  ❌ Source {src} not found, skipping.")
                continue

            if dst.is_symlink():
                if dst.resolve() == src.resolve():
                    print(f"  🟢 Symlink already up to date: {skill}")
                    continue
                dst.unlink()
            elif dst.exists():
                # 実体ディレクトリがある場合はバックアップ退避
                dest_backup = backup_root / f"{skill}_{ts}"
                shutil.move(str(dst), str(dest_backup))
                print(f"  📦 Backed up existing {skill} to {dest_backup}")

            if use_symlink:
                dst.symlink_to(src)
                print(f"  🔗 Created symlink: {skill} -> {src}")
            else:
                shutil.copytree(src, dst)
                print(f"  📋 Copied directory: {skill} -> {dst}")

    print("\n✅ Deployment complete. Running status verification...\n")
    get_status()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Deploy skills from SSOT (dev-standards)")
    parser.add_argument('--status', action='store_true', help='Show current deployment status')
    parser.add_argument('--dry-run', action='store_true', help='Preview changes without modifying')
    parser.add_argument('--link', action='store_true', help='Deploy as symlinks (recommended)')
    parser.add_argument('--copy', action='store_true', help='Deploy as copies')

    args = parser.parse_args()
    if args.dry_run:
        dry_run()
    elif args.link:
        deploy(use_symlink=True)
    elif args.copy:
        deploy(use_symlink=False)
    else:
        get_status()
