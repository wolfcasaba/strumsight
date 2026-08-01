import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.config import load_config
from tools.ai_router.quota import QuotaStatus
from tools.ai_router.router import DevelopmentRouter, RouterStatus
from tools.ai_router.security import ScopeAudit
from tools.ai_router.state import StateStore
from tools.tests.test_router import FakeGate, FakeModel, FakeScope, codex_error, codex_ok, gate


class RouterResumeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.worktree = self.root / "worktree"
        self.worktree.mkdir()
        path = self.root / "e03-r01-resume.md"
        path.write_text(
            "# Task\n\n```ai-router\n"
            "schema_version = 1\nrisk = \"normal\"\n"
            "allowed_paths = [\"lib/example.dart\"]\n"
            "gate_tests = [\"test/example_test.dart\"]\n"
            "native_gate = false\n```\n"
        )
        self.brief = load_brief(path)
        self.config = load_config(Path(__file__).resolve().parents[2] / ".ai" / "router.toml")
        self.state = StateStore(self.root / "state")

    def make_router(self, models, gates, quotas, *, audits=None):
        model = FakeModel(models)
        gate_runner = FakeGate(gates)
        scope = FakeScope(audits)
        quota_values = iter(quotas)
        router = DevelopmentRouter(
            config=self.config,
            state=self.state,
            run_model=model,
            run_gate=gate_runner,
            check_quota=lambda: next(quota_values),
            capture_manifest=scope.capture,
            audit_scope=scope.audit,
        )
        return router, model

    def test_quota_deferred_precheck_can_resume_without_new_task_budget(self) -> None:
        router, model = self.make_router(
            [codex_ok()],
            [gate("pass"), gate("pass")],
            [
                QuotaStatus("quota_limited", True, True, remaining_percent=0),
                QuotaStatus("ok", True, True, remaining_percent=80),
            ],
        )

        first = router.run(self.brief, self.worktree)
        second = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(first.status, RouterStatus.DEFERRED)
        self.assertEqual(second.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3"])

    def test_provider_429_does_not_consume_an_m3_solution_attempt(self) -> None:
        empty = ScopeAudit(True, (), (), False, "sha256:empty")
        router, model = self.make_router(
            [codex_error("HTTP 429 quota"), codex_ok()],
            [gate("pass"), gate("pass")],
            [
                QuotaStatus("ok", True, True, remaining_percent=80),
                QuotaStatus("ok", True, True, remaining_percent=80),
            ],
            audits=[empty],
        )

        first = router.run(self.brief, self.worktree)
        self.assertEqual(self.state.load_task(self.brief.task_id)["m3_attempts"], 0)
        second = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(first.status, RouterStatus.DEFERRED)
        self.assertEqual(second.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "m3"])
        self.assertEqual(self.state.load_task(self.brief.task_id)["m3_attempts"], 1)


    def test_provider_failure_with_partial_diff_is_gated_before_retry(self) -> None:
        changed = ScopeAudit(
            True, ("lib/example.dart",), (), False, "sha256:partial"
        )
        router, model = self.make_router(
            [codex_error("HTTP 429 quota")],
            [gate("pass"), gate("pass")],
            [
                QuotaStatus("ok", True, True, remaining_percent=80),
                QuotaStatus("ok", True, True, remaining_percent=80),
            ],
            audits=[changed, changed],
        )

        first = router.run(self.brief, self.worktree)
        second = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(first.status, RouterStatus.DEFERRED)
        self.assertEqual(second.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3"])
        self.assertEqual(self.state.load_task(self.brief.task_id)["m3_attempts"], 1)


if __name__ == "__main__":
    unittest.main()
