from dataclasses import replace
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

    def test_resume_after_interrupted_m3_call_retries_without_consuming_the_attempt(
        self,
    ) -> None:
        # Mért reprodukció (E02-R21, H6, docs/LESSONS.md L42): a Bash-eszköz
        # 600s-es kemény plafonja megölte a TELJES router-folyamatot, mielőtt
        # a `run_model()` hívás visszatérhetett -- a resume-ág ezt tévesen
        # úgy kezelte, mintha a hívás lezajlott és üres diffet adott volna,
        # elfogyasztva az egyetlen M3-kísérletet. `M3_CALL_N` csak közvetlenül
        # a `run_model()` hívás ELŐTT perzisztálódik, ezért ez a fázis
        # resume-on sosem jelentheti, hogy a hívás lezajlott -- a kísérletet
        # vissza kell adni és újra kell próbálni, nem elfogyasztani.
        no_scoped_change = ScopeAudit(
            ok=True,
            changed_paths=(),
            violations=(),
            high_risk=False,
            diff_hash="sha256:empty-m3-call-resume-diff",
            scoped_changed_paths=(),
        )
        changed = ScopeAudit(True, ("lib/example.dart",), (), False, "sha256:retry-diff")
        router, model = self.make_router(
            [codex_ok()],
            [gate("pass")],
            [],
            audits=[no_scoped_change, changed],
        )
        self.state.save_task(
            self.brief.task_id,
            {
                "schema_version": 1,
                "task_id": self.brief.task_id,
                "brief_hash": self.brief.metadata_hash,
                "phase": "M3_CALL_1",
                "status": "RUNNING",
                "reason": "",
                "m3_attempts": 1,
                "terra_calls": 0,
                "gate_history": [],
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                    "tracked_paths": [],
                },
            },
        )

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3"])
        self.assertEqual(self.state.load_task(self.brief.task_id)["m3_attempts"], 1)

    def test_resumed_terra_review_or_fix_with_no_scoped_changes_is_not_ready_for_review(
        self,
    ) -> None:
        # Mért reprodukció (E02-R21, H4 halt): a `TERRA_REVIEW_OR_FIX` resume-ág
        # (`DevelopmentRouter.run()`, router.py) ugyanazt a hibát ismétli, mint
        # a friss `_terra()` hívás -- a final_gate "pass"-t önmagában elégnek
        # vette, `audit.scoped_changed_paths`-t nem ellenőrizte a
        # READY_FOR_REVIEW visszaadása előtt.
        no_scoped_change = ScopeAudit(
            ok=True,
            changed_paths=(),
            violations=(),
            high_risk=False,
            diff_hash="sha256:empty-terra-resume-diff",
            scoped_changed_paths=(),
        )
        router, model = self.make_router(
            [], [gate("pass")], [], audits=[no_scoped_change]
        )
        reservation = self.state.reserve_terra(
            self.brief.task_id,
            daily_limit=self.config.limits.max_automatic_terra_calls_per_utc_day,
            task_limit=self.config.limits.max_terra_calls_per_task,
        )
        self.state.mark_terra_started(reservation.reservation_id)
        self.state.save_task(
            self.brief.task_id,
            {
                "schema_version": 1,
                "task_id": self.brief.task_id,
                "brief_hash": self.brief.metadata_hash,
                "phase": "TERRA_REVIEW_OR_FIX",
                "status": "RUNNING",
                "reason": "",
                "m3_attempts": 2,
                "terra_calls": 1,
                "gate_history": [],
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                    "tracked_paths": [],
                },
                "terra_reservation": reservation.reservation_id,
            },
        )

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertNotEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, [])

    def test_review_findings_get_one_bounded_terra_repair_after_initial_escalation(
        self,
    ) -> None:
        """A real post-review repair cannot be mistaken for a fresh task run.

        E03-R12 consumed two M3 attempts and its initial Terra escalation before
        the independent review found concrete MAJOR findings.  The repair must
        receive exactly one additional, review-gated Terra call; a plain run
        still cannot reopen READY_FOR_REVIEW work without findings.
        """
        self.config = replace(
            self.config,
            limits=replace(self.config.limits, max_terra_calls_per_task=2),
        )
        changed = ScopeAudit(
            True,
            ("lib/example.dart",),
            (),
            False,
            "sha256:review-repair-diff",
        )
        router, model = self.make_router(
            [codex_ok()],
            [gate("pass")],
            [QuotaStatus("ok", True, True, remaining_percent=80)],
            audits=[changed],
        )
        first = self.state.reserve_terra(
            self.brief.task_id,
            daily_limit=self.config.limits.max_automatic_terra_calls_per_utc_day,
            task_limit=self.config.limits.max_terra_calls_per_task,
        )
        self.state.mark_terra_started(first.reservation_id)
        self.state.mark_terra_finished(first.reservation_id, "READY_FOR_REVIEW")
        self.state.save_task(
            self.brief.task_id,
            {
                "schema_version": 1,
                "task_id": self.brief.task_id,
                "brief_hash": self.brief.metadata_hash,
                "phase": "FINAL_GATE",
                "status": "READY_FOR_REVIEW",
                "reason": "final gate passed",
                "m3_attempts": 2,
                "terra_calls": 1,
                "gate_history": [],
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                    "tracked_paths": [],
                },
                "terra_reservation": first.reservation_id,
                # A Terra ledger has already been finalized, but a crash
                # before the outer task terminal state was persisted leaves
                # this intent behind. Review findings must supersede that
                # stale completion and reach the bounded repair call.
                "terra_terminal_status": "READY_FOR_REVIEW",
                "terra_terminal_reason": "final gate passed",
            },
        )

        result = router.run(
            self.brief,
            self.worktree,
            resume=True,
            review_findings="F1 — MAJOR — deterministic parser repair required",
        )

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["terra"])
        self.assertEqual(self.state.load_task(self.brief.task_id)["terra_calls"], 2)


if __name__ == "__main__":
    unittest.main()
