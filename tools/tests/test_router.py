import json
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.config import load_config
from tools.ai_router.execution import CodexResult
from tools.ai_router.quota import QuotaStatus
from tools.ai_router.router import DevelopmentRouter, GateRun, RouterStatus
from tools.ai_router.security import ScopeAudit, WorkspaceManifest
from tools.ai_router.state import StateStore


def codex_ok(message: str = "OK") -> CodexResult:
    return CodexResult(0, (), (message,), "")


def codex_error(stderr: str) -> CodexResult:
    return CodexResult(1, (), (), stderr)


def codex_stopped(stdout: str) -> CodexResult:
    # No known failure pattern (quota/429/timeout/network/credential/env) in
    # events or stderr -> classify_provider_failure falls through to STOPPED.
    return CodexResult(1, (), (), "", stdout=stdout)


def gate(outcome: str, fingerprint: str = "sha256:error") -> GateRun:
    return GateRun(
        outcome=outcome,
        failed_step=None if outcome == "pass" else "test example",
        command_exit_code=0 if outcome == "pass" else 1,
        error_hash=None if outcome == "pass" else fingerprint,
        log="" if outcome == "pass" else "example failure",
    )


class FakeModel:
    def __init__(self, outcomes: list[CodexResult]):
        self.outcomes = outcomes
        self.profiles: list[str] = []
        self.prompts: list[str] = []

    def __call__(self, profile: str, worktree: Path, prompt: str) -> CodexResult:
        self.profiles.append(profile)
        self.prompts.append(prompt)
        return self.outcomes.pop(0)


class FakeGate:
    def __init__(self, outcomes: list[GateRun]):
        self.outcomes = outcomes
        self.calls = 0

    def __call__(self, worktree: Path, tests: tuple[str, ...], native: bool) -> GateRun:
        self.calls += 1
        return self.outcomes.pop(0)


class FakeScope:
    def __init__(self, audits: list[ScopeAudit] | None = None):
        self.manifest = WorkspaceManifest("baseline", frozenset(), frozenset())
        self.audits = audits or []

    def capture(self, worktree: Path) -> WorkspaceManifest:
        return self.manifest

    def audit(self, worktree: Path, metadata: object, baseline: WorkspaceManifest) -> ScopeAudit:
        if self.audits:
            return self.audits.pop(0)
        return ScopeAudit(True, ("lib/example.dart",), (), False, "sha256:diff")


class RouterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.worktree = self.root / "worktree"
        self.worktree.mkdir()
        self.config = load_config(Path(__file__).resolve().parents[2] / ".ai" / "router.toml")
        self.state = StateStore(
            self.root / "state", id_factory=lambda: "terra-reservation"
        )

    def brief(self, risk: str = "normal"):
        path = self.root / "e03-r01-example.md"
        path.write_text(
            "# Task\n\n"
            "```ai-router\n"
            "schema_version = 1\n"
            f'risk = "{risk}"\n'
            'allowed_paths = ["lib/example.dart"]\n'
            'gate_tests = ["test/example_test.dart"]\n'
            "native_gate = false\n"
            "```\n\n"
            "## 6. Acceptance criteria\n- [ ] Works\n"
        )
        return load_brief(path)

    def router(
        self,
        models: list[CodexResult],
        gates: list[GateRun],
        *,
        quota: QuotaStatus | None = None,
        audits: list[ScopeAudit] | None = None,
    ) -> tuple[DevelopmentRouter, FakeModel, FakeGate]:
        model = FakeModel(models)
        gate_runner = FakeGate(gates)
        scope = FakeScope(audits)
        router = DevelopmentRouter(
            config=self.config,
            state=self.state,
            run_model=model,
            run_gate=gate_runner,
            check_quota=lambda: quota or QuotaStatus("ok", True, True, remaining_percent=80),
            capture_manifest=scope.capture,
            audit_scope=scope.audit,
        )
        return router, model, gate_runner

    def test_m3_success_returns_ready_for_review_not_done(self) -> None:
        router, model, _ = self.router([codex_ok()], [gate("pass"), gate("pass")])

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3"])
        self.assertEqual(self.state.load_task("E03-R01")["m3_attempts"], 1)

    def test_first_code_failure_gets_one_m3_repair(self) -> None:
        router, model, _ = self.router(
            [codex_ok(), codex_ok()],
            [gate("pass"), gate("code_failure", "sha256:one"), gate("pass")],
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "m3"])
        self.assertIn("example failure", model.prompts[1])

    def test_gate_history_persists_the_full_gate_log_for_diagnosis(self) -> None:
        # Mért gyökérok (E02-R21, H4 halt, Update 5/6, L?): a router
        # gate_history-ja csak outcome/failed_step/error_hash-t tárolt a
        # perzisztens task-state-ben, a tényleges round-gate.sh
        # format/analyze/test kimenetét (GateRun.log) csak a repair/
        # escalation promptba illesztette, majd eldobta. Két egymást követő
        # tartalmi gate-kudarcnál (2 M3 + 1 Terra, mind STOPPED) ez azt
        # jelentette, hogy SEMMILYEN diagnosztikai adat nem maradt a
        # `python3 tools/model-router.py status --task-id <ID> --json`
        # (a felülvizsgálatok saját, dokumentált reprodukciós parancsa)
        # kimenetében arról, MIÉRT bukott a format/analyze/test lépés — csak
        # egy hash, ami semmit nem árul el. A fix a teljes (redaktált) logot
        # is elteszi minden gate_history bejegyzésben.
        router, model, _ = self.router(
            [codex_ok(), codex_ok()],
            [gate("pass"), gate("code_failure", "sha256:one"), gate("pass")],
        )

        router.run(self.brief(), self.worktree)

        state = self.state.load_task("E03-R01")
        failed_entry = next(
            entry for entry in state["gate_history"] if entry.get("outcome") == "code_failure"
        )
        self.assertEqual(failed_entry["log"], "example failure")

    def test_two_code_failures_escalate_once_to_terra(self) -> None:
        router, model, _ = self.router(
            [codex_ok(), codex_ok(), codex_ok()],
            [
                gate("pass"),
                gate("code_failure", "sha256:same"),
                gate("code_failure", "sha256:same"),
                gate("pass"),
            ],
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "m3", "terra"])
        state = self.state.load_task("E03-R01")
        self.assertEqual(state["terra_calls"], 1)

    def test_build_cache_churn_alone_does_not_count_as_scoped_change(self) -> None:
        # Mért reprodukció (E02-R21, H6 halt, 3. eset, L38): a BASELINE_GATE
        # a PRECHECK-ben lefuttatja a teszteket, ami elsőként hozza létre a
        # .dart_tool/build fákat egy friss munkapéldányban. Az M3-hívás UTÁNI
        # audit ezt a saját melléktermékét "M3 diffnek" nézte, és
        # READY_FOR_REVIEW-t jelzett úgy, hogy egyetlen lib/ vagy test/ fájl
        # sem változott. A fix előtt ez a teszt az 1. próbálkozás után
        # READY_FOR_REVIEW-t adott volna vissza (m3_attempts=1); a fix után a
        # scoped_changed_paths üres, tehát a router egy újabb M3-próbálkozást
        # indít, és csak a VALÓDI lib/ diff után zár READY_FOR_REVIEW-val.
        no_scoped_change = ScopeAudit(
            ok=True,
            changed_paths=(".dart_tool/flutter_build/dart_plugin_registrant.dart",),
            violations=(),
            high_risk=False,
            diff_hash="sha256:build-cache-only",
            scoped_changed_paths=(),
        )
        real_change = ScopeAudit(
            ok=True,
            changed_paths=("lib/example.dart",),
            violations=(),
            high_risk=False,
            diff_hash="sha256:real-change",
        )
        router, model, _ = self.router(
            [codex_ok(), codex_ok()],
            [gate("pass"), gate("pass"), gate("pass")],
            audits=[no_scoped_change, real_change],
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "m3"])
        state = self.state.load_task("E03-R01")
        self.assertEqual(state["m3_attempts"], 2)
        phases = [entry.get("phase") for entry in state["gate_history"]]
        self.assertIn("NO_CHANGE_1", phases)
        self.assertEqual(state["changed_paths"], ["lib/example.dart"])

    def test_m3_quota_or_service_failure_never_starts_terra(self) -> None:
        router, model, _ = self.router(
            [codex_error("HTTP 429 quota")], [gate("pass")]
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.DEFERRED)
        self.assertEqual(model.profiles, ["m3"])

    def test_provider_call_history_persists_raw_stdout_for_stopped_diagnosis(self) -> None:
        # Measured (E03-R08 H6 self-heal, 2026-08-02): a real M3 call
        # returned nonzero with zero JSON events and no pattern stderr, so
        # classify_provider_failure() fell through to the STOPPED catch-all
        # (classification.py:58). The router persisted nothing beyond that
        # catch-all string in state["reason"] — the CLI's own raw stdout
        # (where the actual self-halt message would live, see
        # execution.py's CodexResult.stdout) was discarded the moment
        # run_codex() returned. Mirrors the gate_history precedent
        # (test_gate_history_persists_the_full_gate_log_for_diagnosis): the
        # fix keeps a provider_calls history in task state with the raw
        # stdout/stderr of every M3/Terra call, not just its classification.
        router, model, _ = self.router(
            [codex_stopped("fatal: MiniMax CLI self-halted before producing a diff")],
            [gate("pass")],
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.STOPPED)
        state = self.state.load_task("E03-R01")
        calls = state["provider_calls"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["failure"], "stopped")
        self.assertIn(
            "fatal: MiniMax CLI self-halted before producing a diff", calls[0]["stdout"]
        )

    def test_quota_precheck_defers_before_any_model(self) -> None:
        router, model, gate_runner = self.router(
            [], [], quota=QuotaStatus("quota_limited", True, True, remaining_percent=0)
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.DEFERRED)
        self.assertEqual(model.profiles, [])
        self.assertEqual(gate_runner.calls, 0)

    def test_baseline_failure_blocks_without_model(self) -> None:
        router, model, _ = self.router([], [gate("code_failure")])

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.BLOCKED)
        self.assertEqual(model.profiles, [])

    def test_scope_violation_blocks_before_post_model_gate(self) -> None:
        violation = ScopeAudit(
            False,
            ("forbidden.txt",),
            ("path outside allowed scope: forbidden.txt",),
            False,
            "sha256:bad",
        )
        router, model, gate_runner = self.router(
            [codex_ok()], [gate("pass")], audits=[violation]
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.BLOCKED)
        self.assertEqual(gate_runner.calls, 1)
        self.assertEqual(model.profiles, ["m3"])

    def test_high_risk_green_diff_gets_targeted_terra_review(self) -> None:
        router, model, _ = self.router(
            [codex_ok(), codex_ok()], [gate("pass"), gate("pass"), gate("pass")]
        )

        result = router.run(self.brief("high"), self.worktree)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "terra"])
        self.assertIn("quality gate passed", model.prompts[1])

    def test_terra_failure_stops_without_another_model(self) -> None:
        router, model, _ = self.router(
            [codex_ok(), codex_ok(), codex_error("unknown Terra failure")],
            [gate("pass"), gate("code_failure"), gate("code_failure")],
        )

        result = router.run(self.brief(), self.worktree)

        self.assertEqual(result.status, RouterStatus.STOPPED)
        self.assertEqual(model.profiles, ["m3", "m3", "terra"])

    def test_terra_final_gate_pass_with_no_scoped_changes_is_not_ready_for_review(self) -> None:
        # Mért reprodukció (E02-R21, H4 halt): a Terra-ág FINAL_GATE lépése
        # (`_terra()`, router.py) a final_gate "pass" eredményét önmagában
        # elégnek vette a READY_FOR_REVIEW-hoz, anélkül hogy ellenőrizte
        # volna audit.scoped_changed_paths-t -- szemben az M3-hurok
        # NO_CHANGE_* őrével (lásd fent,
        # test_build_cache_churn_alone_does_not_count_as_scoped_change).
        # A teljes M3+Terra keret kimerült valós diff nélkül
        # (changed_paths=[]), a router mégis READY_FOR_REVIEW-t jelzett.
        no_scoped_change = ScopeAudit(
            ok=True,
            changed_paths=(),
            violations=(),
            high_risk=False,
            diff_hash="sha256:empty-terra-diff",
            scoped_changed_paths=(),
        )
        router, model, _ = self.router(
            [codex_ok(), codex_ok(), codex_ok()],
            [
                gate("pass"),
                gate("code_failure", "sha256:same"),
                gate("code_failure", "sha256:same"),
                gate("pass"),
            ],
            audits=[
                ScopeAudit(True, ("lib/example.dart",), (), False, "sha256:m3-1"),
                ScopeAudit(True, ("lib/example.dart",), (), False, "sha256:m3-2"),
                no_scoped_change,
            ],
        )

        result = router.run(self.brief(), self.worktree)

        self.assertNotEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, ["m3", "m3", "terra"])

    def test_terminal_state_run_always_writes_result_path(self) -> None:
        brief = self.brief()
        self.state.save_task(
            brief.task_id,
            {
                "schema_version": 1,
                "task_id": brief.task_id,
                "brief_hash": brief.metadata_hash,
                "phase": "BLOCKED",
                "status": "BLOCKED",
                "reason": "baseline has unsafe ignored files",
                "m3_attempts": 0,
                "terra_calls": 0,
                "gate_history": [],
            },
        )
        router, model, gate_runner = self.router([], [])

        with tempfile.TemporaryDirectory() as directory:
            result_path = Path(directory) / "result.json"

            result = router.run(brief, self.worktree, result_path=result_path)

            self.assertEqual(result.status, RouterStatus.BLOCKED)
            self.assertTrue(
                result_path.exists(),
                "a terminal-state run() call must persist result_path, "
                "not only return the in-memory result (E02-R21 / H6)",
            )
            payload = json.loads(result_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "BLOCKED")
            self.assertEqual(payload["reason"], "baseline has unsafe ignored files")
        self.assertEqual(model.profiles, [])
        self.assertEqual(gate_runner.calls, 0)

    def test_resume_after_crash_runs_gate_before_consuming_another_attempt(self) -> None:
        brief = self.brief()
        self.state.save_task(
            brief.task_id,
            {
                "schema_version": 1,
                "task_id": brief.task_id,
                "brief_hash": brief.metadata_hash,
                "phase": "M3_ATTEMPT_1",
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
        router, model, _ = self.router([], [gate("pass")])

        result = router.run(brief, self.worktree, resume=True)

        self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
        self.assertEqual(model.profiles, [])


if __name__ == "__main__":
    unittest.main()
