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

    def test_queue_runs_the_whole_epic3_on_auto_including_the_closure_round(self) -> None:
        # A user 2026-08-01-i döntése: az Epic 3 MIND a 22 sora fut az auto
        # routeren, folyamatosan. (A korábbi `prepared` + kézi zárókör
        # elvárását ez a döntés váltotta le — ADR 0087 §7, ADR 0112 §6.)
        queue = (ROOT / "docs" / "execution" / "pipeline-queue.tsv").read_text()
        self.assertIn("auto | minimax | codex", queue)
        rows = [line.split("\t") for line in queue.splitlines() if line and not line.startswith("#")]
        self.assertTrue(all(row[2] in {"auto", "minimax", "codex"} for row in rows))
        epic3 = [row for row in rows if row[0].startswith("E03-")]
        self.assertEqual([row[0] for row in epic3], [f"E03-R{i:02d}" for i in range(1, 23)])
        self.assertTrue(all(row[2] == "auto" for row in epic3))
        self.assertTrue(all(row[4] in {"pending", "running", "done"} for row in epic3))

    def test_prompt_has_one_initial_auto_dispatch_and_budget_preserving_resume(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text()
        self.assertEqual(prompt.count("ai-router-round.sh run"), 1)
        self.assertIn("ai-router-round.sh resume", prompt)
        self.assertIn("READY_FOR_REVIEW", prompt)
        self.assertIn("független", prompt.lower())
        self.assertIn("review + CI", prompt)
        self.assertIn("örökölt", prompt.lower())

    def test_selfheal_prompt_defines_the_three_outcomes_and_the_gate_boundary(self) -> None:
        prompt = (ROOT / "docs" / "execution" / "pipeline-selfheal-prompt.md").read_text()
        for placeholder in ("{{ROUND}}", "{{HALT_CODE}}", "{{ATTEMPT}}", "{{HEAL_STATUS_FILE}}"):
            self.assertIn(placeholder, prompt)
        for outcome in ("outcome=fixed", "`retry`", "`escalate`"):
            self.assertIn(outcome, prompt)
        # A mérce-határ nem opcionális része a promptnak (ADR 0112 §3).
        self.assertIn("round-gate.sh", prompt)
        self.assertIn(".github/workflows/", prompt)
        self.assertIn("regressziós teszt", prompt)

    def test_halted_chain_starts_selfheal_unless_it_is_switched_off(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_SELFHEAL="0")

            switched_off = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(switched_off.returncode, 3)
            self.assertIn("önjavítás kikapcsolva", switched_off.stderr)
            self.assertTrue((state / "HALTED").exists())

    def test_selfheal_gives_up_after_the_configured_attempt_budget(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")
            (state / "selfheal.count").write_text("E09-R01|H6|2\n")
            env = dict(os.environ)
            env.update(PIPELINE_STATE_DIR=str(state), PIPELINE_SELFHEAL_MAX="2")

            exhausted = self.run_command(["bash", str(script)], env=env)

            self.assertEqual(exhausted.returncode, 3)
            self.assertIn("KIMERÜLT", exhausted.stderr)
            # A kimerült keret nem indíthat újabb sessiont, és nem old fel.
            self.assertNotIn("ÖNJAVÍTÓ KÖR indul", exhausted.stderr)
            self.assertTrue((state / "HALTED").exists())

    def test_selfheal_attempt_counter_is_scoped_to_round_and_halt_code(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            state = Path(directory_name)
            (state / "selfheal.count").write_text("E09-R01|H6|2\n")
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)

            same = self.run_command(["bash", str(script), "--heal-attempts", "E09-R01", "H6"], env=env)
            other_code = self.run_command(["bash", str(script), "--heal-attempts", "E09-R01", "H5"], env=env)
            other_round = self.run_command(["bash", str(script), "--heal-attempts", "E09-R02", "H6"], env=env)

            self.assertEqual(same.stdout.strip(), "2")
            self.assertEqual(other_code.stdout.strip(), "0")
            self.assertEqual(other_round.stdout.strip(), "0")

    def test_gate_fingerprint_covers_the_test_count_and_the_gate_artifacts(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        fingerprint = self.run_command(["bash", str(script), "--gate-fingerprint"])

        self.assertEqual(fingerprint.returncode, 0, fingerprint.stderr)
        count = int(fingerprint.stdout.split("tests=", 1)[1].split()[0])
        self.assertGreater(count, 100)
        for artifact in (
            "tools/round-gate.sh",
            ".github/workflows/build-apk.yml",
            ".github/workflows/router-ci.yml",
        ):
            self.assertIn(f"{artifact}:", fingerprint.stdout)
            self.assertNotIn(f"{artifact}:hiányzik", fingerprint.stdout)

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
