import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class PipelineIntegrationTest(unittest.TestCase):
    def run_command(self, argv, *, cwd=ROOT, env=None):
        return subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_engine_enum_accepts_auto_and_keeps_legacy_overrides(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        for engine in ("auto", "minimax", "codex"):
            with self.subTest(engine=engine):
                result = self.run_command(["bash", str(script), "--validate-engine", engine])
                self.assertEqual(result.returncode, 0, result.stderr)
        rejected = self.run_command(["bash", str(script), "--validate-engine", "surprise"])
        self.assertEqual(rejected.returncode, 2)

    def test_queue_prepares_epic3_with_auto_but_keeps_closure_manual(self) -> None:
        queue = (ROOT / "docs" / "execution" / "pipeline-queue.tsv").read_text()
        self.assertIn("auto | minimax | codex", queue)
        rows = [line.split("\t") for line in queue.splitlines() if line and not line.startswith("#")]
        self.assertTrue(all(row[2] in {"auto", "minimax", "codex"} for row in rows))
        epic3 = [row for row in rows if row[0].startswith("E03-")]
        self.assertEqual([row[0] for row in epic3], [f"E03-R{i:02d}" for i in range(1, 22)])
        self.assertTrue(all(row[2] == "auto" and row[4] == "prepared" for row in epic3))
        self.assertIn("E03-R22", queue)
        self.assertNotIn("E03-R22\tdocs/", queue)

    def test_prompt_has_one_initial_auto_dispatch_and_budget_preserving_resume(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        self.assertEqual(prompt.count("ai-router-round.sh run"), 1)
        self.assertIn("ai-router-round.sh resume", prompt)
        self.assertIn("READY_FOR_REVIEW", prompt)
        self.assertIn("független", prompt.lower())
        self.assertIn("review + CI", prompt)
        self.assertIn("örökölt", prompt.lower())

    def make_fake_worktree(self, directory: Path) -> tuple[Path, Path, Path]:
        worktree = directory / "worktree"
        (worktree / "tools").mkdir(parents=True)
        (worktree / "docs" / "rounds").mkdir(parents=True)
        shutil.copy2(ROOT / "tools" / "ai-router-round.sh", worktree / "tools" / "ai-router-round.sh")
        shutil.copy2(ROOT / "tools" / "codex-signal.sh", worktree / "tools" / "codex-signal.sh")
        brief = worktree / "docs" / "rounds" / "e03-r01-fake.md"
        brief.write_text("# Fake task\n")
        fake_router = worktree / "tools" / "model-router.py"
        fake_router.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "counter = Path(os.environ[\"FAKE_ROUTER_COUNT\"])\n"
            "count = int(counter.read_text()) if counter.exists() else 0\n"
            "counter.write_text(str(count + 1))\n"
            "result = Path(sys.argv[sys.argv.index(\"--result-json\") + 1])\n"
            "status = os.environ.get(\"FAKE_ROUTER_STATUS\", \"READY_FOR_REVIEW\")\n"
            "reason = os.environ.get(\"FAKE_ROUTER_REASON\", \"fake result\")\n"
            "codes = {\"READY_FOR_REVIEW\": 0, \"STOPPED\": 20, \"DEFERRED\": 30, \"BLOCKED\": 40, \"INTERNAL_ERROR\": 50}\n"
            "result.parent.mkdir(parents=True, exist_ok=True)\n"
            "result.write_text(json.dumps({\"schema_version\": 1, \"status\": status, \"reason\": reason}))\n"
            "raise SystemExit(codes[status])\n"
        )
        fake_router.chmod(0o755)
        subprocess.run(["git", "init", "-q"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.email", "pipeline@example.invalid"], cwd=worktree, check=True)
        subprocess.run(["git", "config", "user.name", "Pipeline Test"], cwd=worktree, check=True)
        subprocess.run(["git", "add", "."], cwd=worktree, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=worktree, check=True)
        return worktree, brief, fake_router

    def test_auto_adapter_dispatches_fake_router_once_and_redacts_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, brief, _ = self.make_fake_worktree(directory)
            counter = directory / "count"
            result_json = worktree / ".ai" / "runs" / "E03-R01" / "router-result.json"
            mirror = directory / "router-status"
            env = dict(os.environ)
            env.update(
                FAKE_ROUTER_COUNT=str(counter),
                FAKE_ROUTER_STATUS="READY_FOR_REVIEW",
                FAKE_ROUTER_REASON="Authorization: Bearer top-secret " + "x" * 800,
                PIPELINE_ROUTER_STATUS_FILE=str(mirror),
            )

            completed = self.run_command(
                [
                    "bash",
                    str(worktree / "tools" / "ai-router-round.sh"),
                    "run",
                    str(worktree),
                    str(brief.relative_to(worktree)),
                    str(result_json),
                ],
                cwd=worktree,
                env=env,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(counter.read_text(), "1")
            signal = (worktree / ".codex-round-status").read_text()
            self.assertIn("status=progress", signal)
            self.assertIn("router_status=READY_FOR_REVIEW", signal)
            self.assertNotIn("top-secret", signal)
            self.assertLess(len(signal), 1200)
            self.assertEqual(mirror.read_text(), signal)

    def test_router_status_mapping_is_stable(self) -> None:
        expected = {
            "READY_FOR_REVIEW": "progress",
            "STOPPED": "stopped",
            "DEFERRED": "blocked",
            "BLOCKED": "blocked",
            "INTERNAL_ERROR": "blocked",
        }
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            worktree, _, _ = self.make_fake_worktree(directory)
            script = worktree / "tools" / "codex-signal.sh"
            for router_status, signal_status in expected.items():
                with self.subTest(router_status=router_status):
                    completed = self.run_command(
                        ["bash", str(script), router_status, "safe summary"], cwd=worktree
                    )
                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    signal = (worktree / ".codex-round-status").read_text()
                    self.assertIn(f"status={signal_status}", signal)
                    self.assertIn(f"router_status={router_status}", signal)

    def test_pipeline_status_only_prints_sanitized_router_signal(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            state = directory / "state"
            state.mkdir()
            (state / "router-status").write_text(
                "status=progress\nrouter_status=READY_FOR_REVIEW\nsummary=redacted safe\n"
                "unexpected_prompt=do not print me\n"
            )
            queue = directory / "queue.tsv"
            queue.write_text("E03-R01\tdocs/brief.md\tauto\t0089\tpending\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_QUEUE_FILE=str(queue))

            completed = self.run_command(
                ["bash", str(ROOT / "tools" / "pipeline-status.sh")], env=env
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("READY_FOR_REVIEW", completed.stdout)
            self.assertNotIn("do not print me", completed.stdout)


if __name__ == "__main__":
    unittest.main()
