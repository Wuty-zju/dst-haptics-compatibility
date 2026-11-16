"""Disabled source must not be counted as an active literal reference."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave

spec = importlib.util.spec_from_file_location("audit_haptics", Path(__file__).resolve().parents[1] / "tools/audit_haptics.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class CommentEvidenceTests(unittest.TestCase):
    def test_comments_are_masked_without_moving_source_lines(self):
        text = '--[[\nPlaySound("inactive")\n]]\nPlaySound("active") -- inactive\n'
        masked = audit.strip_lua_comments(text)
        self.assertNotIn('"inactive"', masked)
        self.assertIn('PlaySound("active")', masked.splitlines()[3])
        self.assertEqual(text.count('\n'), masked.count('\n'))

    def test_long_comment_delimiters_and_strings(self):
        text = 'local a = "--[[ retained ]]"\n--[=[\n"inactive"\n]=]\nlocal b = [=[-- literal]=]\n'
        masked = audit.strip_lua_comments(text)
        self.assertIn('"--[[ retained ]]"', masked)
        self.assertIn('[=[-- literal]=]', masked)
        self.assertNotIn('"inactive"', masked)

    def test_escaped_quotes_do_not_start_a_comment(self):
        text = 'PlaySound("a\\\"--b") -- remove this\n'
        masked = audit.strip_lua_comments(text)
        self.assertIn('"a\\\"--b"', masked)
        self.assertNotIn('remove this', masked)

    def test_multiline_and_escaped_literal_values_keep_opening_line_numbers(self):
        text = '"before\\\n--inside"\n--[==[ "disabled" ]==]\n[=[\nevent/path]=]\n"event\\047path"\n'
        self.assertEqual(list(audit.lua_string_literals(text)), [
            ("before\n--inside", 1), ("event/path", 4), ("event/path", 6),
        ])


class AuditOutputTests(unittest.TestCase):
    def make_inputs(self, root):
        scripts, wavs = root / "scripts", root / "wavs"
        scripts.mkdir()
        wavs.mkdir()
        (scripts / "haptics.lua").write_text('''return {
{ event = "terraria1/eyeofterror/arrive", vibration = true },
{ event = "terraria1/eyeofterror/charge", vibration = true },
{ event = "test/event", vibration = true },
}''', encoding="utf-8")
        with wave.open(str(wavs / "test.wav"), "wb") as output:
            output.setparams((1, 2, 882, 0, "NONE", "not compressed"))
            output.writeframes(b"\0\0" * 44)
        return scripts, wavs

    def run_audit(self, scripts, wavs, out):
        with patch("sys.argv", ["audit_haptics.py", "--scripts", str(scripts),
                                "--wav-root", str(wavs), "--out", str(out)]):
            with contextlib.redirect_stdout(io.StringIO()):
                audit.main()

    def test_only_complete_lua_string_values_count_as_literal_references(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts, wavs = self.make_inputs(root)
            (scripts / "producer.lua").write_text('''PlaySound("terraria1/eyeofterror/arrive_portal")
PlaySound("terraria1/eyeofterror/charge_pre_sfx")
PlaySound('test/event')
PlaySound([=[test/event]=])
PlaySound([==[
test/event]==])
local documentation = [[PlaySound("test/event")]]
-- PlaySound("test/event")
--[=[PlaySound('test/event')]=]
PlaySound("test/event_extra")
PlaySound("prefix/test/event")
PlaySound("test/event\\\"suffix")
PlaySound("test\\047event")
''', encoding="utf-8")
            self.run_audit(scripts, wavs, root / "output")
            rows = {row["event"]: row for row in json.loads((root / "output/audit.json").read_text())}
            self.assertEqual(rows["terraria1/eyeofterror/arrive"]["reference_count"], 0)
            self.assertEqual(rows["terraria1/eyeofterror/charge"]["reference_count"], 0)
            self.assertEqual([ref["line"] for ref in rows["test/event"]["references"]], [3, 4, 5, 13])

    def test_existing_output_directory_is_never_modified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts, wavs = self.make_inputs(root)
            out = root / "evidence"
            out.mkdir()
            previous = out / "audit.json"
            previous.write_bytes(b"existing evidence")
            with self.assertRaisesRegex(SystemExit, "already exists"):
                self.run_audit(scripts, wavs, out)
            self.assertEqual(previous.read_bytes(), b"existing evidence")
            self.assertEqual(list(out.iterdir()), [previous])

    def test_empty_wav_directory_fails_without_creating_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts, wavs = self.make_inputs(root)
            (wavs / "test.wav").unlink()
            out = root / "evidence"
            with self.assertRaisesRegex(SystemExit, "WAV"):
                self.run_audit(scripts, wavs, out)
            self.assertFalse(out.exists())

    def test_unparsed_haptics_table_fails_without_creating_output(self):
        for text in ('--[[\n{ event = "test/event", vibration = true },\n]]\nreturn {}',
                     'return {{\nevent = "test/event",\nvibration = true\n}}'):
            with self.subTest(text=text), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                scripts, wavs = self.make_inputs(root)
                (scripts / "haptics.lua").write_text(text, encoding="utf-8")
                out = root / "evidence"
                with self.assertRaisesRegex(SystemExit, "No haptics definitions parsed"):
                    self.run_audit(scripts, wavs, out)
                self.assertFalse(out.exists())
