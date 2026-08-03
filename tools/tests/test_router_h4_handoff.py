import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief


ROOT = Path(__file__).resolve().parents[2]


class RouterH4HandoffTest(unittest.TestCase):
    def test_exhausted_task_budget_marks_h4_before_stopped_signal(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree = directory / "worktree"
            (worktree / "tools").mkdir(parents=True)
            (worktree / ".ai").mkdir()
            (worktree / "docs" / "rounds").mkdir(parents=True)
            for script in ("ai-router-round.sh", "codex-signal.sh", "model-router.py", "pipeline-status.sh"):
                shutil.copy2(ROOT / "tools" / script, worktree / "tools" / script)
            shutil.copytree(ROOT / "tools" / "ai_router", worktree / "tools" / "ai_router")
            state_root = directory / "router-state"
            (worktree / ".ai" / "router.toml").write_text(
                (ROOT / ".ai" / "router.toml")
                .read_text(encoding="utf-8")
                .replace("~/.local/state/strumsight-ai-router", str(state_root)),
                encoding="utf-8",
            )
            brief_path = worktree / "docs" / "rounds" / "e03-r11.md"
            brief_path.write_text(
                "# E03-R11\n\n"
                "```ai-router\n"
                "schema_version = 1\n"
                'risk = "normal"\n'
                'allowed_paths = ["lib/example.dart"]\n'
                'gate_tests = ["test/example_test.dart"]\n'
                "native_gate = false\n"
                "```\n",
                encoding="utf-8",
            )
            subprocess.run(["git", "init", "-q"], cwd=worktree, check=True)
            subprocess.run(["git", "config", "user.email", "router@example.invalid"], cwd=worktree, check=True)
            subprocess.run(["git", "config", "user.name", "Router Test"], cwd=worktree, check=True)
            subprocess.run(["git", "add", "."], cwd=worktree, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=worktree, check=True)

            brief = load_brief(brief_path)
            (state_root / "tasks").mkdir(parents=True)
            (state_root / "tasks" / "E03-R11.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "task_id": "E03-R11",
                        "brief_hash": brief.metadata_hash,
                        "status": "STOPPED",
                        "phase": "STOPPED",
                        "reason": "task Terra budget is exhausted",
                        "m3_attempts": 2,
                        "terra_calls": 1,
                        "gate_history": [],
                    }
                ),
                encoding="utf-8",
            )
            pipeline_state = directory / "pipeline"
            result_path = worktree / ".ai" / "runs" / "E03-R11" / "router-result.json"
            completed = subprocess.run(
                [
                    "bash",
                    str(worktree / "tools" / "ai-router-round.sh"),
                    "run",
                    str(worktree),
                    "docs/rounds/e03-r11.md",
                    str(result_path),
                ],
                cwd=worktree,
                env={
                    **os.environ,
                    "PIPELINE_STATE_DIR": str(pipeline_state),
                    "PIPELINE_ROUTER_STATUS_FILE": str(pipeline_state / "router-status"),
                },
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 20, completed.stdout + completed.stderr)
            self.assertEqual(json.loads(result_path.read_text(encoding="utf-8"))["status"], "STOPPED")
            for path in (pipeline_state / "router-halt", pipeline_state / "HALTED"):
                self.assertTrue(path.exists(), f"missing H4 handoff: {path}")
                contents = path.read_text(encoding="utf-8")
                self.assertIn("round=E03-R11", contents)
                self.assertIn("halt=H4", contents)
                self.assertIn("summary=task Terra budget is exhausted", contents)
            round_status = (pipeline_state / "round-status").read_text(encoding="utf-8")
            self.assertIn("outcome=halted", round_status)
            self.assertIn("halt=H4", round_status)
            router_signal = (pipeline_state / "router-status").read_text(encoding="utf-8")
            self.assertIn("router_status=STOPPED", router_signal)
            self.assertLessEqual(
                (pipeline_state / "router-halt").stat().st_mtime_ns,
                (pipeline_state / "router-status").stat().st_mtime_ns,
                "the H4 handoff must exist before the STOPPED router signal",
            )
