import json
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.config import load_config
from tools.ai_router.packet import build_escalation_packet
from tools.ai_router.quota import QuotaStatus
from tools.ai_router.router import DevelopmentRouter, RouterStatus
from tools.ai_router.security import ScopeAudit, WorkspaceManifest
from tools.ai_router.state import StateStore
from tools.tests.test_router import FakeGate, FakeModel, FakeScope, codex_ok, gate


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

    def router(self, models, gates, *, audits=None, manifest=None):
        model = FakeModel(models)
        gate_runner = FakeGate(gates)
        scope = FakeScope(audits)
        if manifest is not None:
            scope.manifest = manifest
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

    def test_successful_m3_without_scoped_changes_gets_repair_not_ready(self) -> None:
        empty = ScopeAudit(True, (), (), False, "sha256:empty")
        router, model = self.router(
            [codex_ok(), codex_ok()],
            [gate("pass"), gate("pass"), gate("pass")],
            audits=[empty],
        )

        result = router.run(self.brief, self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "m3"])

    def test_m3_repair_prompt_tells_model_to_finish_untouched_allowed_paths(self) -> None:
        # Mért gyökérok (E02-R21 H4, docs/LESSONS.md): a `_repair_prompt` "do
        # not perform adjacent refactors" fogalmazása a modellt arra
        # kényszerítette, hogy a 2. próbán is csak a bukott gate-lépést
        # javítsa, és SOHA ne nyúljon a brief `allowed_paths` listájának a
        # 1. próba által érintetlenül hagyott fájljaihoz — így a brief tényleges
        # magja (a meglévő fájlok szerkesztése) sosem valósult meg, csak az ÚJ
        # fájlok, hiába volt 2/2 M3 + 1/1 Terra próba.
        self.brief_path.write_text(
            "# Task\n\n```ai-router\n"
            "schema_version = 1\nrisk = \"normal\"\n"
            'allowed_paths = ["lib/a.dart", "lib/b.dart", "lib/c.dart"]\n'
            "gate_tests = [\"test/example_test.dart\"]\n"
            "native_gate = false\n```\n"
        )
        self.brief = load_brief(self.brief_path)
        only_a = ScopeAudit(True, ("lib/a.dart",), (), False, "sha256:diff")
        router, model = self.router(
            [codex_ok(), codex_ok()],
            [gate("pass"), gate("code_failure", "sha256:one"), gate("pass")],
            audits=[only_a, only_a],
        )

        result = router.run(self.brief, self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(len(model.prompts), 2)
        repair_prompt = model.prompts[1]
        self.assertIn("lib/b.dart", repair_prompt)
        self.assertIn("lib/c.dart", repair_prompt)
        self.assertIn("not scope creep", repair_prompt)

    def test_resume_from_precheck_repeats_baseline_before_model(self) -> None:
        self.state.save_task(
            self.brief.task_id,
            {
                "schema_version": 1,
                "task_id": self.brief.task_id,
                "brief_hash": self.brief.metadata_hash,
                "phase": "PRECHECK",
                "status": "RUNNING",
                "m3_attempts": 0,
                "terra_calls": 0,
                "gate_history": [],
            },
        )
        router, model = self.router(
            [codex_ok()], [gate("pass"), gate("pass")]
        )

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3"])

    def test_recovered_environment_gate_blocks_before_another_model(self) -> None:
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
        router, model = self.router([], [gate("environment_failure")])

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.BLOCKED)
        self.assertEqual(model.profiles, [])

    def test_recovered_terra_diff_is_scope_audited_before_final_gate(self) -> None:
        reservation = self.state.reserve_terra(
            self.brief.task_id, daily_limit=3, task_limit=1
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
                "m3_attempts": 2,
                "terra_calls": 1,
                "terra_reservation": reservation.reservation_id,
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                },
                "gate_history": [],
            },
        )
        violation = ScopeAudit(
            False,
            ("forbidden.txt",),
            ("path outside allowed scope: forbidden.txt",),
            False,
            "sha256:bad",
        )
        router, model = self.router([], [gate("pass")], audits=[violation])

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.BLOCKED)
        self.assertEqual(model.profiles, [])
        ledger = json.loads((self.state.root / "terra-ledger.json").read_text())
        self.assertEqual(ledger["reservations"][0]["status"], "finished")
        self.assertEqual(ledger["reservations"][0]["outcome"], "BLOCKED")

    def test_recovered_terra_finishes_ledger_before_terminal_task_state(self) -> None:
        reservation = self.state.reserve_terra(
            self.brief.task_id, daily_limit=3, task_limit=1
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
                "m3_attempts": 2,
                "terra_calls": 1,
                "terra_reservation": reservation.reservation_id,
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                },
                "gate_history": [],
            },
        )
        events = []
        original_finish = self.state.mark_terra_finished
        original_save = self.state.save_task

        def record_finish(reservation_id, outcome):
            events.append(("ledger", outcome))
            return original_finish(reservation_id, outcome)

        def record_save(task_id, state):
            if state.get("status") != "RUNNING":
                events.append(("task", state.get("status")))
            return original_save(task_id, state)

        self.state.mark_terra_finished = record_finish
        self.state.save_task = record_save
        router, _ = self.router([], [gate("pass")])

        result = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(
            events,
            [("ledger", "READY_FOR_REVIEW"), ("task", "READY_FOR_REVIEW")],
        )

    def test_terra_terminal_intent_recovers_after_cross_file_crash(self) -> None:
        reservation = self.state.reserve_terra(
            self.brief.task_id, daily_limit=3, task_limit=1
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
                "m3_attempts": 2,
                "terra_calls": 1,
                "terra_reservation": reservation.reservation_id,
                "baseline_manifest": {
                    "baseline_head": "baseline",
                    "untracked_paths": [],
                    "ignored_paths": [],
                },
                "gate_history": [],
            },
        )
        original_save = self.state.save_task
        crash_on_terminal_save = True

        def crash_once(task_id, state):
            nonlocal crash_on_terminal_save
            if crash_on_terminal_save and state.get("status") == "READY_FOR_REVIEW":
                crash_on_terminal_save = False
                raise OSError("simulated task-state crash")
            return original_save(task_id, state)

        self.state.save_task = crash_once
        router, model = self.router([], [gate("pass")])

        with self.assertRaises(OSError):
            router.run(self.brief, self.worktree, resume=True)

        saved = self.state.load_task(self.brief.task_id)
        self.assertEqual(saved["status"], "RUNNING")
        self.assertEqual(saved["terra_terminal_status"], "READY_FOR_REVIEW")
        recovered = router.run(self.brief, self.worktree, resume=True)

        self.assertEqual(recovered.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, [])
        self.assertEqual(router.run_gate.calls, 1)

    def test_dirty_untracked_baseline_blocks_before_gate_or_model(self) -> None:
        manifest = WorkspaceManifest(
            "baseline", frozenset({"scratch.txt"}), frozenset()
        )
        router, model = self.router([], [], manifest=manifest)

        result = router.run(self.brief, self.worktree)

        self.assertEqual(result.status, RouterStatus.BLOCKED)
        self.assertEqual(model.profiles, [])

    def test_native_gate_uses_the_repository_flutter_build_contract(self) -> None:
        self.assertEqual(
            self.config.security.native_gate_command,
            ("flutter", "build", "apk", "--debug"),
        )


if __name__ == "__main__":
    unittest.main()
