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
        self.assertLess(args.index("--ask-for-approval"), args.index("exec"))
        self.assertEqual(args[args.index("--ask-for-approval") + 1], "never")
        self.assertIn("--ephemeral", args)
        self.assertNotIn("M3_OK", " ".join(args))

    def test_reset_clears_a_stuck_blocked_task_back_to_not_started(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_root = Path(directory) / "state"
            tasks_dir = state_root / "tasks"
            tasks_dir.mkdir(parents=True)
            (tasks_dir / "E02-R21.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "task_id": "E02-R21",
                        "status": "BLOCKED",
                        "phase": "BLOCKED",
                        "reason": "baseline has unsafe ignored files (root cause since fixed)",
                    }
                ),
                encoding="utf-8",
            )

            reset_result = subprocess.run(
                [
                    "python3",
                    str(CLI),
                    "--config",
                    str(CONFIG),
                    "--state-root",
                    str(state_root),
                    "reset",
                    "--task-id",
                    "E02-R21",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(reset_result.returncode, 0, reset_result.stderr)

            status_result = subprocess.run(
                [
                    "python3",
                    str(CLI),
                    "--config",
                    str(CONFIG),
                    "--state-root",
                    str(state_root),
                    "status",
                    "--task-id",
                    "E02-R21",
                    "--json",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(status_result.returncode, 0, status_result.stderr)
            self.assertEqual(json.loads(status_result.stdout)["status"], "NOT_STARTED")

    def _terra_status(self, state_root: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["python3", str(CLI), "--config", str(CONFIG), "--state-root", str(state_root), "terra-status"],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_terra_status_reports_not_exhausted_with_zero_reservations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self._terra_status(Path(directory) / "state")

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["daily_count"], 0)
        self.assertEqual(payload["daily_limit"], 3)
        self.assertFalse(payload["exhausted"])

    def test_terra_status_exits_nonzero_and_reports_the_utc_midnight_reset_once_exhausted(self) -> None:
        # E03-R08 H6 self-heal (2026-08-02): the pipeline driver polls this
        # exit code to decide whether to hold off retrying a round blocked on
        # the shared daily Terra budget instead of busy-retrying every 5min.
        with tempfile.TemporaryDirectory() as directory:
            state_root = Path(directory) / "state"
            baseline = self._terra_status(state_root)
            self.assertEqual(baseline.returncode, 0, baseline.stderr)
            today = json.loads(baseline.stdout)["utc_day"]

            ledger_path = state_root / "terra-ledger.json"
            ledger_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "reservations": [
                            {
                                "reservation_id": f"r{i}",
                                "task_id": f"E03-R0{i}",
                                "utc_day": today,
                                "status": "finished",
                            }
                            for i in range(1, 4)
                        ],
                    }
                ),
                encoding="utf-8",
            )

            result = self._terra_status(state_root)

        self.assertEqual(result.returncode, 1, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["daily_count"], 3)
        self.assertTrue(payload["exhausted"])
        import datetime as _dt

        reset = _dt.datetime.fromisoformat(payload["next_reset_utc"])
        self.assertEqual((reset.date() - _dt.date.fromisoformat(today)).days, 1)
        self.assertEqual(payload["next_reset_epoch"], int(reset.timestamp()))


if __name__ == "__main__":
    unittest.main()
