"""Regression checks for offline reports bound to a native Lua snapshot."""

import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / "tools" / "build_haptics_report.py"


class HapticsReportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.scripts = self.root / "Current scripts"
        self.scripts.mkdir()
        self.out = self.root / "report"
        self.audit = self.root / "audit.json"
        entries = [
            {"event": "dontstarve/AMB/rain", "vibration": True},
            {"event": "test/hud/freeze_click", "vibration": True, "audio": False},
            {"event": "dontstarve/wilson/hit", "vibration": True, "category": "DANGER"},
            {"event": "dontstarve/impacts/impact_flesh_med_dull", "vibration": True},
            {"event": "test/duplicate", "category": "PLAYER", "vibration": True},
            {"event": "test/duplicate", "category": "BOSS", "vibration": False},
        ]
        lines = ["return {"]
        rows = {}
        for line, fields in enumerate(entries, 2):
            literal = ", ".join(f"{key} = {json.dumps(value)}" for key, value in fields.items())
            lines.append("    { " + literal + " },")
            event = fields["event"]
            rows[event] = {
                **fields, "line": line,
                "definition_count": rows.get(event, {}).get("definition_count", 0) + 1,
                "reference_count": 1,
                "references": [{"file": "prefabs/example.lua", "line": 12, "text": "PRIVATE_SOURCE_SNIPPET"}],
            }
        native = self.scripts / "haptics.lua"
        native.write_text("\n".join([*lines, "}"]), encoding="utf-8")
        self.native_hash = hashlib.sha256(native.read_bytes()).hexdigest()
        self.rows = list(rows.values())
        self.write_audit()

    def write_audit(self):
        self.audit.write_text(json.dumps(self.rows), encoding="utf-8")

    def run_report(self, *args):
        return subprocess.run(
            [sys.executable, "-B", str(REPORT), "--scripts", str(self.scripts),
             "--audit", str(self.audit), "--out", str(self.out), *args],
            capture_output=True, text=True, encoding="utf-8", check=False,
        )

    def run_with_lua(self, *args):
        result = self.run_report(*args)
        if "No usable Lua 5.1 runtime" in result.stderr:
            self.skipTest("Lua 5.1 is unavailable")
        return result

    def test_reads_runtime_envelopes_and_drops_source_snippets(self):
        result = self.run_with_lua()
        self.assertEqual(result.returncode, 0, result.stderr)
        csv_path, = self.out.glob("*.csv")
        summary_path, = self.out.glob("*.md")
        self.assertEqual(csv_path.stem.removeprefix("DST-Haptics-Event-Audit-"),
                         self.mod_version())
        text = csv_path.read_text(encoding="utf-8-sig")
        self.assertNotIn("PRIVATE_SOURCE_SNIPPET", text)
        with csv_path.open(encoding="utf-8-sig", newline="") as handle:
            rows = {row["event"]: row for row in csv.DictReader(handle)}
        rain = rows["dontstarve/AMB/rain"]
        self.assertEqual(rain["loop_interval_s"], "0.085")
        self.assertEqual(rain["loop_pulse_s"], "0.1")
        self.assertEqual(rain["loop_listener_local"], "true")
        self.assertEqual(rain["anonymous_total_s"], "0.26")
        self.assertEqual(json.loads(rain["anonymous_pulses"])[0], [0, 0.1, 0.7])
        self.assertEqual(rain["reference_locations"], "prefabs/example.lua:12")
        ui = rows["test/hud/freeze_click"]
        self.assertEqual(ui["audio"], "false")
        self.assertEqual(ui["profile_asset_family"], "")
        self.assertEqual(json.loads(ui["pulses"]), [[0, 0.045, 0.56]])
        duplicate = rows["test/duplicate"]
        self.assertEqual(duplicate["category"], "BOSS")
        self.assertEqual(duplicate["vibration"], "false")
        self.assertEqual(duplicate["definition_count"], "2")
        self.assertEqual(duplicate["haptics_line"], "7")
        hit = rows["dontstarve/wilson/hit"]
        self.assertIn("performaction", hit["strict_route"])
        self.assertIn("hurt_fallback=ON", hit["optional_approximation"])
        impact = rows["dontstarve/impacts/impact_flesh_med_dull"]
        self.assertIn("combat_fallback=ON", impact["optional_approximation"])
        summary = summary_path.read_text(encoding="utf-8")
        self.assertIn(self.native_hash, summary)
        self.assertIn("| 原版定义 | 6 |", summary)
        self.assertIn("`hurt_fallback` 默认 OFF", summary)
        self.assertIn("`combat_fallback` 默认 OFF", summary)

    def mod_version(self):
        for line in (ROOT / "modinfo.lua").read_text(encoding="utf-8").splitlines():
            if line.startswith("version = "):
                return json.loads(line.removeprefix("version = "))
        self.fail("modinfo.lua has no version")

    def test_existing_output_is_preserved_before_reading_inputs(self):
        self.out.mkdir()
        result_file = self.out / "DST-Haptics-Event-Audit-1.2.3.csv"
        result_file.write_text("historical report", encoding="utf-8")
        result = self.run_report("--version", "1.2.3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(result_file.read_text(encoding="utf-8"), "historical report")

    def test_rejects_input_from_another_snapshot(self):
        summary = self.audit.with_name("summary.json")
        summary.write_text(json.dumps({"haptics_sha256": "0" * 64}), encoding="utf-8")
        result = self.run_report()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hash does not match", result.stderr)
        self.assertFalse(self.out.exists())
        summary.unlink()
        self.rows[0]["event"] = "test/other_event"
        self.write_audit()
        result = self.run_with_lua()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("event sets differ", result.stderr)
        self.assertFalse(self.out.exists())
        self.rows[0]["event"] = "dontstarve/AMB/rain"
        self.rows[0]["vibration"] = 1
        self.write_audit()
        result = self.run_with_lua()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native field vibration", result.stderr)
        self.assertFalse(self.out.exists())

    def test_version_override_controls_filenames(self):
        result = self.run_with_lua("--version", "1.2.3-rc1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.out / "DST-Haptics-Event-Audit-1.2.3-rc1.csv").is_file())
