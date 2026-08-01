import tempfile
import unittest
from pathlib import Path

from tools.ai_router.config import ConfigError, load_config


VALID = """schema_version = 1

[routing]
default_engine = "auto"
default_provider = "minimax"
default_model = "MiniMax-M3"

[limits]
max_m3_attempts_per_task = 2
max_terra_calls_per_task = 1
max_automatic_terra_calls_per_utc_day = 3
terra_reasoning = "medium"
terra_packet_target_tokens = 40000
terra_packet_max_bytes = 81920

[runtime]
state_dir = "~/.local/state/strumsight-ai-router"
quota_helper = "~/.local/libexec/strumsight-ai/minimax-quota"
gate_script = "tools/round-gate.sh"
codex_bin = "codex"
m3_profile = "m3"
terra_profile = "terra"
model_timeout_seconds = 7200
gate_timeout_seconds = 3600

[security]
protected_paths = [".git", ".ai/router.toml", "docs/execution/pipeline-queue.tsv"]
high_risk_path_fragments = ["migration", "auth", "credential", "payment", "encryption"]
native_gate_command = ["./gradlew", "test"]
"""


class RouterConfigTest(unittest.TestCase):
    def load(self, content: str):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "router.toml"
            path.write_text(content)
            return load_config(path)

    def test_loads_complete_config(self) -> None:
        config = self.load(VALID)

        self.assertEqual(config.routing.default_engine, "auto")
        self.assertEqual(config.limits.max_m3_attempts_per_task, 2)
        self.assertEqual(config.runtime.m3_profile, "m3")
        self.assertIn(".git", config.security.protected_paths)

    def test_rejects_unknown_key(self) -> None:
        with self.assertRaisesRegex(ConfigError, "unknown"):
            self.load(VALID.replace('default_engine = "auto"', 'default_engine = "auto"\nextra = true'))

    def test_rejects_missing_required_section(self) -> None:
        with self.assertRaises(ConfigError):
            self.load(VALID.split("[security]")[0])

    def test_rejects_invalid_limits(self) -> None:
        with self.assertRaises(ConfigError):
            self.load(VALID.replace("max_m3_attempts_per_task = 2", "max_m3_attempts_per_task = 3"))

    def test_rejects_unsupported_engine_or_schema(self) -> None:
        with self.assertRaises(ConfigError):
            self.load(VALID.replace('default_engine = "auto"', 'default_engine = "random"'))
        with self.assertRaises(ConfigError):
            self.load(VALID.replace("schema_version = 1", "schema_version = 2"))


if __name__ == "__main__":
    unittest.main()
