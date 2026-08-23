#!/usr/bin/env python3

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SETTINGS_DIR = Path(__file__).parent
MERGER = SETTINGS_DIR / "merge-tui-profile"
SOURCE = SETTINGS_DIR / "base.tui-profile.toml"
SYNC = SETTINGS_DIR / "sync.settings.sh"


class MergeTuiProfileTest(unittest.TestCase):
    def test_adds_status_line_without_changing_other_tui_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            target.write_text(
                'model = "gpt-5.4"\n\n'
                '[tui]\n'
                'animations = false\n\n'
                '[features]\n'
                'hooks = true\n'
            )

            result = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--apply"],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                target.read_text(),
                'model = "gpt-5.4"\n\n'
                '[tui]\n'
                'animations = false\n'
                '# >>> dotfiles-codex-status-line (managed by agents/codex/settings) >>>\n'
                'status_line = ["model-with-reasoning", "used-tokens", "five-hour-limit", "thread-title"]\n'
                '# <<< dotfiles-codex-status-line <<<\n\n'
                '[features]\n'
                'hooks = true\n',
            )

    def test_replaces_managed_value_and_becomes_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            target.write_text(
                '[tui]\n'
                '# >>> dotfiles-codex-status-line (managed by agents/codex/settings) >>>\n'
                'status_line = ["current-dir"]\n'
                '# <<< dotfiles-codex-status-line <<<\n'
            )

            applied = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--apply"],
                capture_output=True,
                text=True,
            )
            checked = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--check"],
                capture_output=True,
                text=True,
            )

            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            self.assertIn(
                'status_line = ["model-with-reasoning", "used-tokens", "five-hour-limit", "thread-title"]',
                target.read_text(),
            )

    def test_creates_tui_table_without_changing_other_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            target.write_text('[hooks.state]\ntrusted_hash = "keep-me"\n')

            result = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--apply"],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('trusted_hash = "keep-me"', target.read_text())
            self.assertIn(
                'status_line = ["model-with-reasoning", "used-tokens", "five-hour-limit", "thread-title"]',
                target.read_text(),
            )

    def test_replaces_unmanaged_multiline_status_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            target.write_text(
                '[tui]\n'
                'animations = true\n'
                'status_line = [\n'
                '  "current-dir",\n'
                '  "git-branch",\n'
                ']\n'
            )

            result = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--apply"],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("animations = true", target.read_text())
            self.assertNotIn('"current-dir"', target.read_text())
            self.assertIn(
                'status_line = ["model-with-reasoning", "used-tokens", "five-hour-limit", "thread-title"]',
                target.read_text(),
            )

    def test_sync_check_reports_status_line_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            codex_home = Path(tmp) / ".codex"
            codex_home.mkdir()
            (codex_home / "config.toml").write_text('[tui]\nanimations = false\n')

            result = subprocess.run(
                [SYNC, "--check"],
                env={**os.environ, "CODEX_HOME": str(codex_home)},
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("config.toml  status line DRIFT", result.stdout)


if __name__ == "__main__":
    unittest.main()
