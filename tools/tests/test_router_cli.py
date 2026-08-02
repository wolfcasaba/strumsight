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

    def test_rebase_baseline_preserves_a_scoped_model_diff_after_preflight_commit(self) -> None:
        # E03-R08 H6: task state had baseline 8c084268 while the reused
        # worktree was at pre-flight f023b89.  The command must advance only
        # the committed baseline and leave the model's uncommitted allowed
        # change visible for the scope audit and later review.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "worktree"
            root.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "router@example.invalid"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Router Test"], cwd=root, check=True)
            (root / "lib").mkdir()
            (root / "lib" / "allowed.dart").write_text("baseline\n", encoding="utf-8")
            subprocess.run(["git", "add", "lib/allowed.dart"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
            baseline = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            (root / "tools").mkdir()
            (root / "tools" / "router.py").write_text("preflight\n", encoding="utf-8")
            (root / "docs" / "rounds").mkdir(parents=True)
            brief = root / "docs" / "rounds" / "e03-r08-rebase.md"
            brief.write_text(
                "# Task\n\n```ai-router\n"
                "schema_version = 1\nrisk = \"normal\"\n"
                "allowed_paths = [\"lib/allowed.dart\", \"docs/rounds/e03-r08-rebase.md\"]\n"
                "gate_tests = [\"test/example_test.dart\"]\n"
                "native_gate = false\n```\n",
                encoding="utf-8",
            )
            subprocess.run(
                ["git", "add", "tools/router.py", "docs/rounds/e03-r08-rebase.md"],
                cwd=root,
                check=True,
            )
            subprocess.run(["git", "commit", "-qm", "preflight"], cwd=root, check=True)
            preflight = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            (root / "lib" / "allowed.dart").write_text("model change\n", encoding="utf-8")
            state_root = Path(directory) / "state"
            task_dir = state_root / "tasks"
            task_dir.mkdir(parents=True)
            (task_dir / "E03-R08.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "task_id": "E03-R08",
                        "status": "BLOCKED",
                        "phase": "BLOCKED",
                        # This is a completed Terra terminal intent from the
                        # stale baseline decision.  A rebase must not replay
                        # it when the task is subsequently resumed.
                        "terra_calls": 1,
                        "terra_reservation": "finished-terra-review",
                        "terra_terminal_status": "BLOCKED",
                        "terra_terminal_reason": "stale baseline scope audit",
                        "baseline_manifest": {
                            "baseline_head": baseline,
                            "untracked_paths": [],
                            "ignored_paths": [],
                            "tracked_paths": [],
                        },
                    }
                ),
                encoding="utf-8",
            )

            command = [
                "python3",
                str(CLI),
                "--config",
                str(CONFIG),
                "--state-root",
                str(state_root),
                "rebase-baseline",
                "--task",
                str(brief),
                "--worktree",
                str(root),
            ]
            (root / "lib" / "forbidden.dart").write_text("must remain blocked\n", encoding="utf-8")
            rejected = subprocess.run(
                command,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(rejected.returncode, 50)
            self.assertEqual(
                json.loads((task_dir / "E03-R08.json").read_text(encoding="utf-8"))["status"],
                "BLOCKED",
            )
            (root / "lib" / "forbidden.dart").unlink()
            command[command.index("--task") + 1] = "E03-R08"
            result = subprocess.run(
                command,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "READY_FOR_REVIEW")
        self.assertEqual(payload["phase"], "BASELINE_REBASED")
        self.assertEqual(payload["baseline_manifest"]["baseline_head"], preflight)
        self.assertEqual(payload["changed_paths"], ["lib/allowed.dart"])
        self.assertEqual(payload["terra_reservation"], "finished-terra-review")
        self.assertNotIn("terra_terminal_status", payload)
        self.assertNotIn("terra_terminal_reason", payload)

    def _terra_status(
        self, state_root: Path, *, config: Path = CONFIG
    ) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["python3", str(CLI), "--config", str(config), "--state-root", str(state_root), "terra-status"],
            text=True,
            capture_output=True,
            check=False,
        )

    def _config_with_daily_limit(self, directory: Path, limit: int) -> Path:
        config = directory / "router.toml"
        source = CONFIG.read_text(encoding="utf-8")
        current = "max_automatic_terra_calls_per_utc_day = 0"
        self.assertIn(current, source)
        config.write_text(
            source.replace(
                current,
                f"max_automatic_terra_calls_per_utc_day = {limit}",
            ),
            encoding="utf-8",
        )
        return config

    def test_terra_status_reports_not_exhausted_with_finite_budget(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self._terra_status(
                root / "state", config=self._config_with_daily_limit(root, 3)
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["daily_count"], 0)
        self.assertEqual(payload["daily_limit"], 3)
        self.assertFalse(payload["unlimited"])
        self.assertFalse(payload["exhausted"])

    def test_terra_status_reports_unlimited_and_retains_the_audit_count(self) -> None:
        import datetime as _dt

        with tempfile.TemporaryDirectory() as directory:
            state_root = Path(directory) / "state"
            state_root.mkdir(parents=True)
            today = _dt.datetime.now(_dt.timezone.utc).date().isoformat()
            (state_root / "terra-ledger.json").write_text(
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

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["daily_limit"], 0)
        self.assertEqual(payload["daily_count"], 3)
        self.assertTrue(payload["unlimited"])
        self.assertFalse(payload["exhausted"])
        self.assertIsNone(payload["next_reset_utc"])
        self.assertIsNone(payload["next_reset_epoch"])

    def test_terra_status_exits_nonzero_and_reports_the_utc_midnight_reset_once_exhausted(self) -> None:
        # E03-R08 H6 self-heal (2026-08-02): the pipeline driver polls this
        # exit code to decide whether to hold off retrying a round blocked on
        # the shared daily Terra budget instead of busy-retrying every 5min.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_root = root / "state"
            config = self._config_with_daily_limit(root, 3)
            baseline = self._terra_status(state_root, config=config)
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

            result = self._terra_status(state_root, config=config)

        self.assertEqual(result.returncode, 1, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["daily_count"], 3)
        self.assertFalse(payload["unlimited"])
        self.assertTrue(payload["exhausted"])
        import datetime as _dt

        reset = _dt.datetime.fromisoformat(payload["next_reset_utc"])
        self.assertEqual((reset.date() - _dt.date.fromisoformat(today)).days, 1)
        self.assertEqual(payload["next_reset_epoch"], int(reset.timestamp()))


if __name__ == "__main__":
    unittest.main()
