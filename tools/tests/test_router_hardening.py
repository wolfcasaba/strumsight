import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.config import load_config
from tools.ai_router.packet import build_escalation_packet
from tools.ai_router.quota import QuotaStatus
from tools.ai_router.router import DevelopmentRouter, RouterStatus
from tools.ai_router.state import StateStore
from tools.tests.test_router import FakeGate, FakeModel, FakeScope, gate


class RouterHardeningTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.worktree = self.root / "worktree"
        self.worktree.mkdir()
        self.brief_path = self.root / "e03-r01-hardening.md"
        self.brief_path.write_text(
            "# Task\n\n```ai-router\n"
            "schema_version = 1\nrisk = \"normal\"\n"
            "allowed_paths = [\"lib/example.dart\"]\n"
            "gate_tests = [\"test/example_test.dart\"]\n"
            "native_gate = false\n```\n"
        )
        self.brief = load_brief(self.brief_path)
        self.config = load_config(Path(__file__).resolve().parents[2] / ".ai" / "router.toml")
        self.state = StateStore(self.root / "state")

    def router(self, models, gates):
        model = FakeModel(models)
        gate_runner = FakeGate(gates)
        scope = FakeScope()
        router = DevelopmentRouter(
            config=self.config,
            state=self.state,
            run_model=model,
            run_gate=gate_runner,
            check_quota=lambda: QuotaStatus("ok", True, True, remaining_percent=80),
            capture_manifest=scope.capture,
            audit_scope=scope.audit,
        )
        return router, model

    def test_model_prompts_leave_commits_to_the_orchestrator(self) -> None:
        router, _ = self.router([], [])
        initial = router._initial_prompt(self.brief)
        repair = router._repair_prompt(self.brief, gate("code_failure"))
        packet = build_escalation_packet(
            task_text=self.brief.text,
            acceptance=(),
            failed_command="test",
            error_log="failed",
            attempts=(),
            diff_stat="",
            diff_text="",
            relevant_files=(),
        )

        for prompt in (initial, repair, packet):
            self.assertIn("Do not commit", prompt)
            self.assertIn("Do not run tools/codex-signal.sh", prompt)

    def test_interrupted_m3_call_is_audited_and_gated_before_another_model(self) -> None:
        self.state.save_task(
            self.brief.task_id,
            {
                "schema_version": 1,
                "task_id": self.brief.task_id,
                "brief_hash": self.brief.metadata_hash,
                "phase": "M3_CALL_1",
                "status": "RUNNING",
                "m3_attempts": 1,
                "terra_calls": 0,
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                },
                "gate_history": [],
            },
        )
        router, model = self.router([], [gate("pass")])

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, [])

    def test_native_gate_uses_the_repository_flutter_build_contract(self) -> None:
        self.assertEqual(
            self.config.security.native_gate_command,
            ("flutter", "build", "apk", "--debug"),
        )


if __name__ == "__main__":
    unittest.main()
