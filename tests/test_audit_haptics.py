"""Disabled source must not be counted as an active literal reference."""
import importlib.util
from pathlib import Path
import unittest

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
