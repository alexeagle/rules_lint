"""Run with python3 -m unittest discover -s .github/workflows -p 'test_*.py'."""

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import update_multitool as updater


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.binary = {
            "kind": "archive",
            "url": "https://github.com/owner/tool/releases/download/v1.0/tool-1.0.tar.gz",
            "file": "tool-1.0/tool",
            "os": "linux",
            "cpu": "arm64",
            "sha256": "old",
        }
        self.asset = {
            "name": "tool-2.0.tar.gz",
            "url": "https://api.github.com/repos/owner/tool/releases/assets/1",
            "browser_download_url": "https://github.com/owner/tool/releases/download/v2.0/tool-2.0.tar.gz",
        }
        self.release = {"tag_name": "v2.0", "assets": [self.asset]}
        self.lock = {"$schema": "schema", "tool": {"binaries": [self.binary]}}

    def test_update_preserves_metadata_and_caches_shared_assets(self):
        self.binary["headers"] = {"Example": "value"}
        self.lock["tool"]["binaries"].append(copy.deepcopy(self.binary))
        with patch.object(updater, "release_info", return_value=self.release) as lookup:
            with patch.object(updater, "checksum", return_value="new") as checksum:
                updater.update(self.lock, {}, {})
        lookup.assert_called_once_with("owner/tool")
        checksum.assert_called_once_with(self.asset)
        self.assertEqual(self.binary["url"], self.asset["browser_download_url"])
        self.assertEqual(self.binary["sha256"], "new")
        self.assertEqual(self.binary["file"], "tool-2.0/tool")
        self.assertEqual(self.binary["headers"], {"Example": "value"})

    def test_current_release_needs_no_download(self):
        self.release["tag_name"] = "v1.0"
        with patch.object(updater, "checksum") as checksum:
            updater.update(self.lock, {"owner/tool": self.release}, {})
        checksum.assert_not_called()
        self.assertEqual(self.binary["sha256"], "old")

    def test_missing_asset_fails_without_writing_any_lockfiles(self):
        self.release["assets"] = []
        with tempfile.TemporaryDirectory() as directory:
            first, second = [
                Path(directory) / name for name in ("first.json", "second.json")
            ]
            first.write_text('{"$schema":"unchanged"}')
            second.write_text(json.dumps(self.lock))
            originals = [p.read_text() for p in (first, second)]
            with patch.object(updater, "release_info", return_value=self.release):
                with self.assertRaisesRegex(ValueError, "has no asset"):
                    updater.main([first, second])
            self.assertEqual([p.read_text() for p in (first, second)], originals)

    def test_rate_limit_reports_gh_error(self):
        error = subprocess.CalledProcessError(
            1, ["gh", "api"], stderr="API rate limit exceeded"
        )
        with patch.object(updater.subprocess, "run", side_effect=error):
            with self.assertRaises(subprocess.CalledProcessError):
                updater.release_info("owner/tool")

    def test_malformed_release_has_actionable_error(self):
        result = subprocess.CompletedProcess([], 0, stdout='{"message":"no release"}')
        with patch.object(updater.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(
                ValueError, "owner/tool: latest release has no tag_name"
            ):
                updater.release_info("owner/tool")

    def test_checksum_verifies_download(self):
        def download(*args, stdout, **kwargs):
            stdout.write(b"archive")

        self.asset["digest"] = "sha256:wrong"
        with patch.object(updater.subprocess, "run", side_effect=download):
            with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
                updater.checksum(self.asset)


if __name__ == "__main__":
    unittest.main()
