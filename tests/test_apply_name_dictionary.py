"""apply_name_dictionary.py の決定論的置換と検知を検証する。"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "skills/diary_editing/scripts/apply_name_dictionary.py"

class ApplyNameDictionaryTests(unittest.TestCase):
    def test_apply_replacements(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dict_file = Path(tmpdir) / "dict.json"
            dict_file.write_text(json.dumps({"サンプル人名": "SampleName", "誤表記ツール": "ToolName"}), encoding="utf-8")

            input_text = "今日はサンプル人名と誤表記ツールの話をした。"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--dict", str(dict_file)],
                input=input_text,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "今日はSampleNameとToolNameの話をした。")

    def test_check_flag(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dict_file = Path(tmpdir) / "dict.json"
            dict_file.write_text(json.dumps({"サンプル人名": "SampleName"}), encoding="utf-8")

            # 警告が出るケース
            warn_res = subprocess.run(
                [sys.executable, str(SCRIPT), "--dict", str(dict_file), "--check"],
                input="サンプル人名について",
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(warn_res.returncode, 1)
            self.assertIn("WARN", warn_res.stdout)

            # 問題ないケース
            ok_res = subprocess.run(
                [sys.executable, str(SCRIPT), "--dict", str(dict_file), "--check"],
                input="SampleNameについて",
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(ok_res.returncode, 0)
            self.assertIn("OK", ok_res.stdout)

    def test_default_dictionary_load(self):
        # デフォルト辞書（references/name_dictionary.json）が正常に読み込めること
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--check"],
            input="表記ゆれAのテスト",
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("統一表記A", result.stdout)

if __name__ == "__main__":
    unittest.main()
