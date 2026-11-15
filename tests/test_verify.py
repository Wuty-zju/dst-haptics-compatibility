"""Regression checks for evidence preservation and validation boundaries."""

import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("verify", ROOT / "tools" / "verify.py")
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


class VerifyTests(unittest.TestCase):
    def test_existing_report_is_never_overwritten_or_verified(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "evidence.json"
            report.write_text("existing evidence", encoding="utf-8")
            with patch.object(verify, "collect_report") as collect:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(verify.main(["--report", str(report)]), 2)
                collect.assert_not_called()
            self.assertEqual(report.read_text(encoding="utf-8"), "existing evidence")

    def test_missing_runtime_is_a_failure(self):
        with patch.object(verify.shutil, "which", return_value=None):
            with patch.object(Path, "is_file", return_value=False):
                runtime, checks = verify.select_runtime(None, None, ROOT)
        self.assertIsNone(runtime)
        self.assertEqual(checks[-1]["status"], "FAIL")

    def test_explicit_wrong_lua_version_does_not_fall_back(self):
        probe = {"status": "PASS", "stdout": "Lua 5.4", "exit_code": 0}
        with patch.object(verify, "run_command", return_value=probe) as run:
            runtime, checks = verify.select_runtime("custom-lua", None, ROOT)
        self.assertIsNone(runtime)
        self.assertEqual(checks[0]["status"], "FAIL")
        self.assertEqual(run.call_count, 1)

    def test_dll_test_commands_always_pass_dependency_directory(self):
        runtime = {"kind": "dll", "deps": "C:/Lua dependencies"}
        for test in (*verify.PORTABLE_TESTS, "test_original_haptics.lua"):
            original = Path("current-game/scripts") if test == "test_original_haptics.lua" else None
            command = verify.lua_test_command(runtime, ROOT, test, original)
            self.assertEqual(command[command.index("--lua-deps") + 1], runtime["deps"])
            self.assertEqual(command[command.index("--mod-root") + 1], str(ROOT))
            self.assertEqual("--original-scripts" in command, original is not None)

    def test_markdown_code_and_remote_links_are_not_local_targets(self):
        markdown = '''[real](docs/guide.md#test)
`[inline](missing.md)`
```
[fenced](missing.md)
```
~~~text
[also fenced](missing.md)
~~~
[web](https://example.com/no.md)
[anchor](#details)
![asset](<assets/icon%20one.svg>)
[ref]: docs/another.md "Title"
'''
        self.assertEqual(list(verify.markdown_targets(markdown)), [
            (1, "docs/guide.md"), (11, "assets/icon one.svg"), (12, "docs/another.md"),
        ])

    def test_lua_scope_excludes_old_work_and_nested_test_snapshots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("scripts/sub/active.lua", "tests/test_active.lua", "work/old.lua", "tests/snapshot/old.lua"):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("", encoding="utf-8")
            self.assertEqual([path.relative_to(root).as_posix() for path in verify.lua_sources(root)], [
                "modinfo.lua", "modmain.lua", "scripts/sub/active.lua", "tests/test_active.lua",
            ])

    def test_old_native_snapshot_does_not_turn_missing_input_into_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = root / "work" / "original_scripts" / "scripts" / "haptics.lua"
            old.parent.mkdir(parents=True)
            old.write_text("return {}", encoding="utf-8")
            with patch.object(verify, "run_command") as run:
                checks, original = verify.check_lua(root, None, None)
                run.assert_not_called()
            self.assertIsNone(original)
            self.assertEqual(checks[-1]["name"], "test_original_haptics.lua")
            self.assertEqual(checks[-1]["status"], "SKIP")


if __name__ == "__main__":
    unittest.main()
