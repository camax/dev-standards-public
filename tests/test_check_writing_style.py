"""check_writing_style.py の文体・禁止タグ・文字数Lintテスト"""

from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "skills/sns_editorial/check_writing_style.py"

class CheckWritingStyleTests(unittest.TestCase):
    def test_polite_style_detection(self):
        # です・ます調の検知
        res = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input="今日は良い天気でした。",
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("敬体排除", res.stdout)

    def test_banned_tag_detection(self):
        # #note タグの検知
        res = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input="今日の出来事 #note #日々の記録",
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("禁止タグ", res.stdout)

    def test_clean_input_passes(self):
        # 正常な常体・ルール適合文
        res = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input="朝起きてすぐに作業を開始した。\n途中で雨が降ってきたが問題なかった。",
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("OK", res.stdout)

    def test_x_length_limit(self):
        # X文字数オーバー
        long_text = "あ" * 125
        res = subprocess.run(
            [sys.executable, str(SCRIPT), "--platform", "x_personal"],
            input=long_text,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("X文字数超過", res.stdout)

if __name__ == "__main__":
    unittest.main()
