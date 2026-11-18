"""Project delegation accepts live model versions and user-selected effort."""

from pathlib import Path
import tomllib
import unittest

from tools.agent_models import latest_model


class AgentModelTests(unittest.TestCase):
    def test_numeric_versions_and_exact_family(self):
        available = ["gpt-6.9-sol", "gpt-6.10-sol", "gpt-7-astra",
                     "gpt-6-astra", "gpt-7-sol-preview"]
        self.assertEqual(latest_model("sol", available), "gpt-6.10-sol")
        self.assertEqual(latest_model("astra", available), "gpt-7-astra")

    def test_missing_family(self):
        self.assertIsNone(latest_model("astra", ["gpt-6.2-sol"]))

    def test_role_files_allow_the_dispatcher_to_select_model_and_effort(self):
        project = Path(__file__).resolve().parents[1] / ".codex"
        config = tomllib.loads((project / "config.toml").read_text(encoding="utf-8"))
        self.assertNotIn("default_subagent_model", config["agents"])
        for file in [project / "config.toml", *sorted((project / "agents").glob("*.toml"))]:
            with self.subTest(file=file.name):
                keys = tomllib.loads(file.read_text(encoding="utf-8"))
                self.assertTrue({"model", "model_reasoning_effort", "service_tier"}.isdisjoint(keys))
