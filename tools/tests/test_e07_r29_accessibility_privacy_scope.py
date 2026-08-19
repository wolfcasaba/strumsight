r"""Regression guard for the E07-R29 self-heal (ADR 0112, halt H3, 2026-08-19).

Measured root cause of the halt: the PREPARED E07-R29 brief's `allowed_paths`
granted only brand-new files (`plan_privacy_screen.dart`, the two new
`delete_practice_planning_data.dart` / `export_practice_planning_data.dart`
use cases, the two new ARB files, one new privacy doc, two new test files) --
but the round's own §3/§5.5 scope requires a POLICY-COMPLIANT full delete and
export, and an accessibility audit+fix of EXISTING planner screens. Neither
is reachable from only-new files:

  * the actual persistent owners are `data/local/generation_draft_repository.
    dart` (the wizard draft) and `data/local/local_practice_plan_repository.
    dart` (active pointer, per-revision records, the bounded revision/outcome
    archive) -- neither exposes a policy-scoped "delete everything for this
    plan" mutation today, only `clearDraft(draftKey)` (one draft) and
    per-eviction `keyValueStore.remove()` calls internal to `appendRevision`/
    `appendOutcome`;
  * `domain/repository/practice_evidence_repository.dart` documents, by
    design, "there is deliberately no delete/expire operation" (ADR 0260 §5:
    evidence is immutable past, expiry is query-time only) -- but §5.5 of
    THIS round explicitly requires the evidence tied to a deleted plan's
    outcomes to actually disappear on an explicit user request, which is a
    structurally different trigger than automatic expiry;
  * the A2-A5/A9 accessibility behaviour (large-text overflow, screen-reader
    order, non-colour-only status, reduced motion, no post-pain hardening)
    lives today in the already-existing `presentation/screens/
    today_plan_screen.dart`, `weekly_plan_screen.dart`, `plan_setup_screen.
    dart` and their controllers -- a brand-new, not-yet-wired
    `plan_privacy_screen.dart` cannot audit or fix behaviour it doesn't
    render.

The round's own pre-flight (Terra orchestrator, 2026-08-19, commit `29863cba`
on the never-pushed `minimax/e07-r29-accessibility-privacy-hardening` branch)
measured exactly this gap and correctly refused implementer-dispatch (H3) --
see the brief's own ported `## 0.0 Pre-flight revízió` section. That commit
never reached `main`; `.pipeline/HALTED` (`halted_at=2026-08-19T15:08:58+00:00`)
records the same finding independently:

    rg -n "clearDraft|readArchive|remove\(" \\
      lib/features/practice_generator/data/local/local_practice_plan_repository.dart \\
      lib/features/practice_generator/data/local/generation_draft_repository.dart
    sed -n '1,120p' lib/core/storage/key_value_store.dart

This self-heal (§0.0.1 in the brief) resolves it with ONE brief-only widening,
no new ADR (the round's own §0.0 already concluded none applies): 17 named
entries added to `allowed_paths` (10 existing `lib/` owners + 7 of their own
existing tests), 7 of those added to `gate_tests` too. It also measured a
narrower alternative than the pre-flight's own phrasing suggested: `lib/core/
storage/key_value_store.dart` (the shared, cross-feature `KeyValueStore`
interface) does NOT need to be touched -- `LocalPracticePlanRepository`
already computes every key it owns from its own static builders
(`local_practice_plan_repository.dart:157-202`) and already calls
`keyValueStore.remove(<a key it just computed>)` per individually-known key
during bounded-history eviction (`appendRevision`/`appendOutcome`, same file
438-445 and 477-483) -- so a policy-scoped "delete everything for one plan"
method fits inside that ONE file, without widening a shared interface used by
every other feature's storage.

This guard locks in four things, deliberately none of which is "this file's
content must never change" (the L279/L280 branch-ahead-of-main trap
`tools/tests/test_e07_r25_vision_evidence_scope.py` already documents a
correction for: the round this brief unblocks is EXPECTED to edit every file
listed in `NEW_ALLOWED_PATHS`, so nothing here pins their bodies):

  * the exact paths the measured halt named, plus the rest of the §0.0.1
    grant, are in scope via the REAL `audit_legacy_scope()` -- the same
    function `tools/scope-audit.py` calls -- against the actually committed
    brief;
  * a representative sibling in each widened area (the shared KeyValueStore
    interface; a neighbouring repository/domain-policy/service file the
    pre-flight explicitly measured as already-safe and did NOT name; a
    sibling screen+test the accessibility audit was never scoped to) stays
    OUT of scope -- proving this is a named-file addition, not a directory or
    feature-wide opening;
  * `allowed_paths`/`gate_tests` equal the original set plus EXACTLY the new
    entries -- no silent extra grant, no dropped original entry;
  * every newly granted path exists in the repository today (catches a typo'd
    path before it ever reaches a round-gate run) -- an existence check, not
    a content pin, so it stays true across every future edit the round makes.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r29-accessibility-privacy-hardening.md"

# The brief's allowed_paths/gate_tests before this self-heal (PREPARED,
# written 2026-08-15, `main @ 0afb9994`) -- reproduced verbatim.
ORIGINAL_ALLOWED_PATHS = (
    "lib/l10n/app_en.arb",
    "lib/l10n/app_hu.arb",
    "lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart",
    "lib/features/practice_generator/application/usecase/delete_practice_planning_data.dart",
    "lib/features/practice_generator/application/usecase/export_practice_planning_data.dart",
    "lib/features/practice_generator/public.dart",
    "docs/privacy/practice-planning-data.md",
    "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
    "test/features/practice_generator/accessibility/planner_privacy_test.dart",
    "test/fixtures/practice_generator/accessibility/",
    "docs/rounds/e07-r29-accessibility-privacy-hardening.md",
)
ORIGINAL_GATE_TESTS = (
    "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
    "test/features/practice_generator/accessibility/planner_privacy_test.dart",
)

# The §0.0.1 self-heal widening: the measured storage/evidence owners plus
# the measured accessibility-audited screens/controllers/widgets, and each
# one's own pre-existing test.
NEW_LIB_PATHS = (
    "lib/features/practice_generator/data/local/local_practice_plan_repository.dart",
    "lib/features/practice_generator/data/local/generation_draft_repository.dart",
    "lib/features/practice_generator/domain/repository/practice_evidence_repository.dart",
    "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
    "lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart",
    "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
    "lib/features/practice_generator/application/controller/today_plan_controller.dart",
    "lib/features/practice_generator/presentation/controller/plan_setup_controller.dart",
    "lib/features/practice_generator/presentation/widgets/availability_editor.dart",
    "lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart",
)
NEW_TEST_PATHS = (
    "test/features/practice_generator/data/local_repository_test.dart",
    "test/features/practice_generator/data/generation_draft_repository_test.dart",
    "test/features/practice_generator/evidence/evidence_repository_fake_test.dart",
    "test/features/practice_generator/application/today_plan_controller_test.dart",
    "test/features/practice_generator/presentation/today_plan_screen_test.dart",
    "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
    "test/features/practice_generator/presentation/availability_editor_test.dart",
)
NEW_ALLOWED_PATHS = NEW_LIB_PATHS + NEW_TEST_PATHS

# Reproduced verbatim from `.pipeline/HALTED`'s `detail=` reproduction command
# -- real measured data, not an invented fixture.
MEASURED_HALT_PATHS = (
    "lib/features/practice_generator/data/local/local_practice_plan_repository.dart",
    "lib/features/practice_generator/data/local/generation_draft_repository.dart",
)

# A representative sibling per widened area that must stay OUT of scope.
SIBLING_OUT_OF_SCOPE_PATHS = (
    # The shared, cross-feature KeyValueStore interface -- §0.0.1 measured
    # that the storage-owner files can implement a full-plan delete using
    # only their own already-computed keys, so the shared interface itself
    # was deliberately NOT widened.
    "lib/core/storage/key_value_store.dart",
    # A sibling in the same data/local/ directory the halt never named.
    "lib/features/practice_generator/data/local/practice_plan_migrator.dart",
    # The §0.0 pre-flight explicitly measured this service as already safe
    # (discomfort text is dropped before logging) and did NOT request it.
    "lib/features/practice_generator/application/service/evidence_aggregator.dart",
    # A domain/policy file the audited screens only import, never modify.
    "lib/features/practice_generator/domain/policy/scheduling_policy.dart",
    # A sibling screen the accessibility audit was never scoped to.
    "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
    "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
)

# No protected-path fragment of the real .ai/router.toml touches any
# candidate path; an empty tuple keeps this guard focused on allowed_paths.
PROTECTED = ()


class E07R29AccessibilityPrivacyScopeTest(unittest.TestCase):
    def _make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "heal@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Heal Test"], cwd=root, check=True)
        (root / ".gitignore").write_text("build/\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    def _head(self, root: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def _audit_untracked(self, root: Path, base: str, relative: str, allowed):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("placeholder\n")
        return audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

    def test_measured_halt_paths_are_now_in_scope(self) -> None:
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths

        for relative in MEASURED_HALT_PATHS:
            audit = self._audit_untracked(root, base, relative, allowed)
            self.assertTrue(
                audit.ok,
                f"{relative} -- the exact path named in .pipeline/HALTED's "
                f"reproduction -- must be in scope after the E07-R29 H3 "
                f"brief revision, got violations: {audit.violations}",
            )
            self.assertIn(relative, audit.changed_paths)

    def test_new_paths_are_in_scope_via_the_real_audit(self) -> None:
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths

        for relative in NEW_ALLOWED_PATHS:
            audit = self._audit_untracked(root, base, relative, allowed)
            self.assertTrue(
                audit.ok,
                f"{relative} must be in scope after the E07-R29 H3 §0.0.1 "
                f"brief revision -- got violations: {audit.violations}",
            )

    def test_sibling_paths_outside_the_new_grants_remain_out_of_scope(self) -> None:
        """The fix widens scope by named file, not by directory or feature
        area: a plausible neighbour in each of the four widened areas
        (shared storage interface, sibling repository, already-safe service,
        sibling screen) must still violate -- otherwise the self-heal would
        have silently legalized far more than the measured gap needed."""
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths

        for relative in SIBLING_OUT_OF_SCOPE_PATHS:
            audit = self._audit_untracked(root, base, relative, allowed)
            self.assertFalse(
                audit.ok,
                f"{relative} unexpectedly fell in scope -- the H3 fix must "
                "widen allowed_paths narrowly (named files), not open a "
                "whole directory or feature area",
            )
            self.assertIn(f"path outside allowed scope: {relative}", audit.violations)

    def test_allowed_paths_is_the_original_plus_exactly_the_new_entries(self) -> None:
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self.assertEqual(
            set(allowed) - set(ORIGINAL_ALLOWED_PATHS),
            set(NEW_ALLOWED_PATHS),
            "E07-R29 H3 must resolve by adding exactly the measured "
            "storage-owner/evidence-port/screen/controller/widget/test "
            "files the gap requires -- not a wider or narrower change to "
            "allowed_paths (ADR 0112 §3)",
        )
        self.assertEqual(
            set(ORIGINAL_ALLOWED_PATHS) - set(allowed),
            set(),
            "an original allowed_paths entry was dropped; the self-heal "
            "must only ADD scope, never remove it",
        )

    def test_gate_tests_is_the_original_plus_exactly_the_new_test_entries(self) -> None:
        gate = load_brief(BRIEF).metadata.gate_tests
        self.assertEqual(
            set(gate) - set(ORIGINAL_GATE_TESTS),
            set(NEW_TEST_PATHS),
            "gate_tests must gain exactly the 7 pre-existing test files the "
            "widened lib/ owners now put at regression risk -- the round's "
            "own gate should catch a break there, not only the final CI "
            "full suite",
        )
        self.assertEqual(set(ORIGINAL_GATE_TESTS) - set(gate), set())
        # Every gate_tests entry must also be allowed_paths -- otherwise the
        # round's own gate would demand a test file it is forbidden to edit.
        allowed = set(load_brief(BRIEF).metadata.allowed_paths)
        self.assertTrue(set(gate).issubset(allowed))

    def test_new_paths_exist_in_the_repo_today(self) -> None:
        """Existence, not content: every file this heal newly allows must be
        a real path today, so a typo never silently ships as an
        unreachable grant. This does NOT pin file content -- the round this
        brief unblocks is expected to edit every one of these files."""
        missing = [p for p in NEW_ALLOWED_PATHS if not (REPO_ROOT / p).is_file()]
        self.assertEqual(missing, [], f"newly allowed path(s) do not exist: {missing}")

    def test_brief_documents_the_self_heal_resolution(self) -> None:
        """RED before this self-heal (no §0.0.1 widening section exists yet
        on top of the ported §0.0 pre-flight); GREEN once the resolution is
        recorded."""
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("0.0.1", text)
        self.assertIn("H3", text)
        for path in NEW_ALLOWED_PATHS:
            self.assertIn(path, text)


if __name__ == "__main__":
    unittest.main()
