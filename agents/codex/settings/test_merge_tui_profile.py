#!/usr/bin/env python3

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SETTINGS_DIR = Path(__file__).resolve().parent
CODEX_DIR = SETTINGS_DIR.parent
REPO = CODEX_DIR.parent.parent
MERGER = SETTINGS_DIR / "merge-tui-profile"
SOURCE = SETTINGS_DIR / "base.tui-profile.toml"


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

    def test_stays_byte_identical_when_a_table_follows_tui(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            target.write_text(
                '[tui]\n'
                '# >>> dotfiles-codex-status-line (managed by agents/codex/settings) >>>\n'
                'status_line = ["current-dir"]\n'
                '# <<< dotfiles-codex-status-line <<<\n\n'
                '[marketplaces.example]\n'
                'source_type = "local"\n'
            )

            first = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--apply"],
                capture_output=True,
                text=True,
            )
            after_first = target.read_text()
            second = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--apply"],
                capture_output=True,
                text=True,
            )
            checked = subprocess.run(
                [MERGER, "--source", SOURCE, "--target", target, "--check"],
                capture_output=True,
                text=True,
            )

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(target.read_text(), after_first)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            self.assertEqual(
                after_first,
                '[tui]\n'
                '# >>> dotfiles-codex-status-line (managed by agents/codex/settings) >>>\n'
                'status_line = ["model-with-reasoning", "used-tokens", "five-hour-limit", "thread-title"]\n'
                '# <<< dotfiles-codex-status-line <<<\n\n'
                '[marketplaces.example]\n'
                'source_type = "local"\n',
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
            probe_home = Path(tmp) / "home"
            codex_home = probe_home / ".codex-cockpit"
            codex_home.mkdir(parents=True)
            (codex_home / "config.toml").write_text('[tui]\nanimations = false\n')

            agents_shared = Path(tmp) / "agents-shared"
            agents_shared.mkdir()
            shutil.copy(REPO / "agents/shared/prompts.sh", agents_shared / "prompts.sh")

            result = subprocess.run(
                [CODEX_DIR / "sync.sh", "settings", "--check"],
                env={
                    "PATH": os.environ["PATH"],
                    "HOME": str(probe_home),
                    "AGENTS_SHARED_DIR": str(agents_shared),
                },
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("config.toml  status line DRIFT", result.stdout)

    def test_worker_run_outside_the_orchestrator_is_refused(self):
        result = subprocess.run(
            ["bash", SETTINGS_DIR / "sync.settings.sh", "--check"],
            env={"PATH": os.environ["PATH"], "HOME": "/nonexistent"},
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sync.sh", result.stderr)


if __name__ == "__main__":
    unittest.main()
