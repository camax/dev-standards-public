"""verify_diary_article.py の決定論的監査機能テスト"""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "skills/diary_editing/scripts/verify_diary_article.py"

class VerifyDiaryArticleTests(unittest.TestCase):
    def test_verify_success(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            orig_file = Path(tmpdir) / "20261016.md"
            orig_content = "朝起きてコーヒーを淹れた。外は良い天気だった。開発作業を続けた。"
            orig_file.write_text(orig_content, encoding="utf-8")

            edited_file = Path(tmpdir) / "edited.md"
            edited_content = """# 2026年10月16日_開発作業とコーヒー

### 📝 あらすじ
朝のコーヒーと開発の進展について。

---

### 朝のルーティン

朝起きてコーヒーを淹れた。
外は良い天気だった。
開発作業を続けた。

---

### ▼ Podcastはこちら
- **YouTube:** <url>

### タグ
#今日の振り返り #開発 #コーヒー
"""
            edited_file.write_text(edited_content, encoding="utf-8")

            res = subprocess.run(
                [sys.executable, str(SCRIPT), "--original", str(orig_file), "--edited", str(edited_file)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertIn("PASS", res.stdout)
            self.assertIn("一致確認", res.stdout)

    def test_verify_date_mismatch(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            orig_file = Path(tmpdir) / "20261016.md"
            orig_file.write_text("テキスト", encoding="utf-8")

            edited_file = Path(tmpdir) / "edited.md"
            # 日付が2026年10月15日で不一致
            edited_content = """# 2026年10月15日_昨日のタイトル
### 📝 あらすじ
あらすじ
### 本文
テキスト
### タグ
#タグ
"""
            edited_file.write_text(edited_content, encoding="utf-8")

            res = subprocess.run(
                [sys.executable, str(SCRIPT), "--original", str(orig_file), "--edited", str(edited_file)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(res.returncode, 1)
            self.assertIn("日付不一致", res.stdout)

    def test_verify_low_retention(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            orig_file = Path(tmpdir) / "20261016.md"
            # 長い原文
            orig_file.write_text("とても長い原文テキストがここにたくさん書かれています。" * 20, encoding="utf-8")

            edited_file = Path(tmpdir) / "edited.md"
            # 短く要約してしまった出力
            edited_content = """# 2026年10月16日_タイトル
### 📝 あらすじ
あらすじ
### 本文
短縮されたテキスト。
### タグ
#タグ
"""
            edited_file.write_text(edited_content, encoding="utf-8")

            res = subprocess.run(
                [sys.executable, str(SCRIPT), "--original", str(orig_file), "--edited", str(edited_file)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(res.returncode, 1)
            self.assertIn("要約検出", res.stdout)

if __name__ == "__main__":
    unittest.main()
