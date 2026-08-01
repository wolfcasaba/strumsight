import json
import stat
import tempfile
import tomllib
import unittest
from pathlib import Path

from tools.ai_router.install import InstallError, install_router


class InstallTest(unittest.TestCase):
    def make_source(self, root: Path) -> Path:
        source = root / "source.json"
        source.write_text(json.dumps({"api_key": "test-secret", "region": "global"}))
        source.chmod(0o600)
        return source

    def test_installs_profiles_helpers_and_preserves_global_default(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            codex = home / ".codex"
            codex.mkdir(parents=True)
            config = codex / "config.toml"
            config.write_text(
                'model = "gpt-existing"\nmodel_reasoning_effort = "ultra"\n\n'
                '[mcp_servers."openspace-vm"]\n'
                'command = "/opt/OpenSpace/venv/bin/openspace-mcp"\n'
                'args = []\n'
                'env = { OPENAI_API_KEY = "test-secret", SAFE = "yes" }\n'
            )
            source = self.make_source(root)
            repo_root = Path(__file__).resolve().parents[2]

            report = install_router(home=home, repo_root=repo_root, source_config=source)
            before_second = config.read_bytes()
            second = install_router(home=home, repo_root=repo_root, source_config=source)

            parsed = tomllib.loads(config.read_text())
            self.assertEqual(parsed["model"], "gpt-existing")
            self.assertEqual(parsed["model_reasoning_effort"], "ultra")
            provider = parsed["model_providers"]["minimax"]
            self.assertEqual(provider["base_url"], "https://api.minimax.io/v1")
            self.assertEqual(provider["wire_api"], "responses")
            self.assertNotIn("env_key", provider)
            self.assertEqual(provider["auth"]["refresh_interval_ms"], 0)
            self.assertEqual(config.read_bytes(), before_second)
            self.assertFalse(second.changed)
            self.assertTrue(report.changed)
            self.assertNotIn("test-secret", config.read_text())

            for profile in (codex / "m3.config.toml", codex / "terra.config.toml"):
                self.assertEqual(stat.S_IMODE(profile.stat().st_mode), 0o600)
            libexec = home / ".local" / "libexec" / "strumsight-ai"
            server = parsed["mcp_servers"]["openspace-vm"]
            self.assertEqual(server["command"], str(libexec / "openspace-vm"))
            self.assertEqual(server["env"], {"SAFE": "yes"})
            backup = codex / "config.toml.pre-minimax-router.bak"
            self.assertNotIn("test-secret", backup.read_text())
            for helper in (
                libexec / "minimax-credential",
                libexec / "minimax-quota",
                libexec / "openspace-vm",
            ):
                self.assertEqual(stat.S_IMODE(helper.stat().st_mode), 0o700)
            self.assertEqual(
                stat.S_IMODE((home / ".local" / "state" / "strumsight-ai-router").stat().st_mode),
                0o700,
            )

    def test_existing_unmanaged_minimax_provider_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            codex = home / ".codex"
            codex.mkdir(parents=True)
            (codex / "config.toml").write_text(
                '[model_providers.minimax]\nbase_url = "https://other.invalid"\n'
            )

            with self.assertRaises(InstallError):
                install_router(
                    home=home,
                    repo_root=Path(__file__).resolve().parents[2],
                    source_config=self.make_source(root),
                )


if __name__ == "__main__":
    unittest.main()
