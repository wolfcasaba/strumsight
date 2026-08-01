import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "tools" / "model-router.py"
CONFIG = ROOT / ".ai" / "router.toml"


class RouterCliTest(unittest.TestCase):
    def test_help_and_empty_status_are_machine_readable(self) -> None:
        help_result = subprocess.run(
            ["python3", str(CLI), "--help"], text=True, capture_output=True, check=False
        )
        self.assertEqual(help_result.returncode, 0, help_result.stderr)

        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [
                    "python3",
                    str(CLI),
                    "--config",
                    str(CONFIG),
                    "--state-root",
                    directory,
                    "status",
                    "--task-id",
                    "E03-R01",
                    "--json",
                ],
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "NOT_STARTED")

    def test_smoke_uses_read_only_headless_codex(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "codex"
            args_file = root / "args.json"
            fake.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "open(os.environ['ARGS_FILE'], 'w').write(json.dumps(sys.argv[1:]))\n"
                "prompt=sys.stdin.read()\n"
                "token='M3_OK' if 'M3_OK' in prompt else 'TERRA_OK'\n"
                "print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':token}}))\n"
            )
            fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
            result = subprocess.run(
                [
                    "python3",
                    str(CLI),
                    "--config",
                    str(CONFIG),
                    "--state-root",
                    str(root / "state"),
                    "smoke",
                    "--profile",
                    "m3",
                    "--codex-bin",
                    str(fake),
                    "--worktree",
                    str(root),
                ],
                env={**os.environ, "ARGS_FILE": str(args_file)},
                text=True,
                capture_output=True,
                check=False,
            )

            args = json.loads(args_file.read_text())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "M3_OK")
        self.assertIn("read-only", args)
        self.assertIn("never", args)
        self.assertIn("--ephemeral", args)
        self.assertNotIn("M3_OK", " ".join(args))


if __name__ == "__main__":
    unittest.main()
