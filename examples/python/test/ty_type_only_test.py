"""Check type-only diagnostics, runtime exclusion, and the ordinary example."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import unittest

_REPORTS = {Path(arg).suffix: Path(arg) for arg in sys.argv[1:]}


class TypeOnlyTest(unittest.TestCase):
    def test_negative_diagnostics(self):
        self.assertEqual(_REPORTS[".exit_code"].read_text().strip(), "1")
        report = _REPORTS[".out"].read_text()
        for diagnostic in ("invalid-argument-type", "invalid-assignment"):
            self.assertIn(f"error[{diagnostic}]", report)
        self.assertNotIn("error[unresolved-import]", report)

    def test_runtime_exclusion(self):
        # rules_python 1.8.1 includes pyi_deps sources at runtime.
        # Version 2.5.0-rc0 excludes them.
        expectation = os.environ.get("TY_EXPECT_LEGACY_PYI_SOURCES", "1")
        self.assertIn(expectation, ("0", "1"))
        runfiles = Path(os.environ["TEST_SRCDIR"])
        for module, included in (("stub", False), ("dependency", expectation == "1")):
            with self.subTest(module=module):
                self.assertEqual(importlib.util.find_spec(module) is not None, included)
                files = list(runfiles.glob(f"*/src/python_lib/{module}.*"))
                self.assertEqual(bool(files), included)


class RuntimeExampleTest(unittest.TestCase):
    def test_main(self):
        from src.uses_dependency_correctly import main

        with contextlib.redirect_stdout(io.StringIO()) as output:
            main()
        self.assertEqual(output.getvalue(), "Hello, World!\n")


if __name__ == "__main__":
    case = "RuntimeExampleTest" if sys.argv[1:] == ["runtime"] else "TypeOnlyTest"
    unittest.main(argv=[sys.argv[0], case])
