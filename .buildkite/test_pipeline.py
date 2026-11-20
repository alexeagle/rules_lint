"""Run with python3 -m unittest discover -s .buildkite -p 'test_*.py'."""

import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import pipeline


# Real subprocesses exercise cloning, fixture resets, and nested tool wrappers.
TOOL = '''#!/usr/bin/env python3
import json, os, pathlib, sys
fixture = pathlib.Path('fixture')
assert fixture.read_text() == 'original', 'fixtures were not restored'
fixture.write_text('modified')
assert 'ASPECT_API_TOKEN' not in os.environ
assert 'ASPECT_WORKFLOWS_REMOTE_CACHE' not in os.environ
if '--bats-probe' in sys.argv:
    try:
        os.fstat(3)
    except OSError:
        pass
    else:
        raise AssertionError('tool inherited Bats TAP descriptor')
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps([sys.argv[1:], os.environ.get('USE_BAZEL_VERSION')]) + '\\n')
sys.exit(1 if '--output_groups=rules_lint_human' in sys.argv else 0)
'''


class PipelineTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "repo"
        self.root.mkdir()
        self.tools = Path(temporary.name) / "bin"
        self.tools.mkdir()
        self.log = Path(temporary.name) / "calls.jsonl"
        contexts = contextlib.ExitStack()
        self.addCleanup(contexts.close)
        contexts.enter_context(patch.dict(os.environ, {
            "PATH": str(self.tools) + os.pathsep + os.environ["PATH"],
            "CALLS": str(self.log), "FD3_PROBE": str(self.log.parent / "tap"),
            "ASPECT_API_TOKEN": "test-token", "ASPECT_WORKFLOWS_REMOTE_CACHE": "test-endpoint",
            "USE_BAZEL_VERSION": "7.x",
        }))
        contexts.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def write(self, path, content="", executable=False):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        if executable:
            path.chmod(0o755)

    def commit(self):
        for args in (
            ["init", "--quiet"], ["add", "."],
            ["-c", "user.name=Test", "-c", "user.email=test@example.com",
             "commit", "--quiet", "-m", "fixture"],
        ):
            subprocess.run(["git", *args], cwd=self.root, check=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_discovery_unions_checks_and_preserves_exclusions(self):
        for path in (
            "examples/ruby/tools/format/BUILD", "examples/ruby/tools/lint/BUILD",
            "examples/ruby/test/nested/lint.bats", "examples/python/test/lint.bats",
            "examples/new-language/tools/lint/BUILD",
        ):
            self.write(self.root / path)
        self.assertEqual(pipeline.discover(self.root), {
            "examples/ruby": ["format", "lint", "integration"],
            "examples/new-language": ["lint"],
            "format": ["integration"],
        })

    def test_runner_restores_fixtures_and_continues_after_failure(self):
        folder = self.root / "examples/nodejs"
        self.write(folder / "fixture", "original")
        for path in ("test/lint.bats", "tools/format/BUILD", "tools/lint/BUILD"):
            self.write(folder / path)
        self.commit()
        for tool in ("bazel", "aspect"):
            self.write(self.tools / tool, TOOL, executable=True)
        # Simulate Bats opening its TAP descriptor after the runner starts it.
        self.write(self.tools / "bats",
                   "#!/usr/bin/env bash\nexec bazel build --bats-probe 3>\"$FD3_PROBE\"\n",
                   executable=True)
        self.assertEqual(pipeline.run(self.root, "examples/nodejs", ["format", "lint", "integration"]), 1)
        calls = self.calls()
        self.assertEqual(len(calls), 7)  # Includes checks after the seeded failure.
        self.assertTrue(all(version == "8.x" for _, version in calls))
        self.assertEqual((folder / "fixture").read_text(), "original")

    def test_root_tests_use_bazel_and_the_requested_version(self):
        self.write(self.root / "fixture", "original")
        self.commit()
        self.write(self.tools / "bazel", TOOL, executable=True)
        original_which = shutil.which
        # Root tests must work without Aspect or Bats installed.
        with patch("shutil.which", side_effect=lambda tool:
                   None if tool in ("aspect", "bats") else original_which(tool)):
            for version in ("7.x", "8.x", "9.x"):
                with patch.dict(os.environ, {"USE_BAZEL_VERSION": version}):
                    self.assertEqual(pipeline.run(self.root, ".", ["test"]), 0)
        self.assertEqual([version for _, version in self.calls()], ["7.x", "8.x", "9.x"])
        for args, _ in self.calls():
            self.assertNotIn("--build_tests_only", args)
        self.assertEqual((self.root / "fixture").read_text(), "original")


if __name__ == "__main__":
    unittest.main()
