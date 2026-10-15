"""verify_lineage.py の出典照合テスト"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "skills/sns_editorial/verify_lineage.py"

class VerifyLineageTests(unittest.TestCase):
    def test_verify_success(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            source_file = Path(tmpdir) / "20261016.md"
            source_file.write_text("1行目\n2行目：朝起きてコーヒーを淹れた。\n3行目\n", encoding="utf-8")

            lineage_data = {
                "post_id": "test_01",
                "lineage": [
                    {
                        "claim": "朝コーヒーを淹れた",
                        "source_path": str(source_file),
                        "source_line": 2,
                        "source_quote": "朝起きてコーヒーを淹れた。"
                    }
                ]
            }

            result = subprocess.run(
                [sys.executable, str(SCRIPT)],
                input=json.dumps(lineage_data),
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("OK", result.stdout)

    def test_verify_mismatch(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            source_file = Path(tmpdir) / "20261016.md"
            source_file.write_text("1行目\n2行目\n", encoding="utf-8")

            lineage_data = {
                "post_id": "test_02",
                "lineage": [
                    {
                        "claim": "存在しない引用",
                        "source_path": str(source_file),
                        "source_line": 2,
                        "source_quote": "存在しない文字列"
                    }
                ]
            }

            result = subprocess.run(
                [sys.executable, str(SCRIPT)],
                input=json.dumps(lineage_data),
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("FAILED", result.stdout)

if __name__ == "__main__":
    unittest.main()
