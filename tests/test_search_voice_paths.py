"""search_voice.py のVaultパス選択を検証する。"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "skills/sns_editorial/search_voice.py"


class SearchVoicePathTests(unittest.TestCase):
    # [2026-10-10 ADD] ユーザーごとのVault配置でも検索できることを実行経路で確認する。
    def test_environment_variable_selects_vault_with_spaces(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory) / "Vault With Spaces"
            vault.mkdir()
            note = vault / "20261010.md"
            note.write_text("phase1_env_path_token\n", encoding="utf-8")

            env = os.environ.copy()
            env["OBSIDIAN_ROOT"] = str(vault)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "phase1_env_path_token"],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(str(note), result.stdout)
            self.assertIn("phase1_env_path_token", result.stdout)

    def test_default_uses_current_home(self):
        with tempfile.TemporaryDirectory() as directory:
            vault = Path(directory) / "Obsidian"
            vault.mkdir()
            note = vault / "20261010.md"
            note.write_text("phase1_home_path_token\n", encoding="utf-8")

            env = os.environ.copy()
            env.pop("OBSIDIAN_ROOT", None)
            env["HOME"] = directory
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "phase1_home_path_token"],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(str(note), result.stdout)
            self.assertIn("phase1_home_path_token", result.stdout)


if __name__ == "__main__":
    unittest.main()
