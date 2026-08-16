"""Regression guard for the E07-R11 self-heal (ADR 0112, halt H3, 2026-08-16).

Measured root cause of the halt: the E07-R11 brief's `allowed_paths` names
two exact test files (`plan_validator_test.dart`, `plan_repairer_test.dart`)
and one property test, but no shared-fixture location. The round's own §6/
§6.1 acceptance criteria (9 cells plus the mandatory three-cell severity
boundary) all need the SAME non-trivial `AdaptivePracticePlan`/`PracticeDay`/
`PracticeBlock`/`WeeklyAvailability` construction across those two
independent test files -- exactly the case the repo's established
`test/fixtures/<feature>/<sub>/*_fixtures.dart` convention exists for. The
closest precedent is the immediately PRIOR round in this same feature tree,
`docs/rounds/e07-r10-adaptive-practice-plan-domain.md` §0.0.1 (merged as
PR #283, `c2778bbc`, hours before this halt), which hit the identical gap for
`test/fixtures/practice_generator/plan/plan_fixtures.dart` and explicitly
named the repo-wide convention. See also [[L242]] (E06-R20) and [[L246]]
(E06-R23) for the same pattern in a different feature tree.

Measured halt: with no allowed fixture location, the sonnet-impl
(engine=minimax-m3) implementer created
`test/fixtures/practice_generator/validation/validation_fixtures.dart`
(work copy `/home/ubuntu/ss-sonnet-impl-e07-r11`, `head=a82bef17`, 7 dirty
files, none committed) -- outside `allowed_paths` -- and the scope-audit
correctly forced `stopped`:

    python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e07-r11 \
      --brief docs/rounds/e07-r11-plan-validator-and-repair.md \
      --base a82bef17a5b9cd6d8ac27f45c12c50e494511775
    -> exit 1, "path outside allowed scope:
       test/fixtures/practice_generator/validation/validation_fixtures.dart"

(`.pipeline/HALTED`, halted_at=2026-08-16T06:06:06+00:00.)

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls -- against the REAL, currently
committed brief so a regression in either direction shows up here first:

  * the measured halt path must now pass (the gap the halt exposed is
    closed);
  * a sibling path directly under `test/fixtures/practice_generator/` but
    OUTSIDE the new `validation/` subdirectory must keep failing (the fix is
    a narrow scope *addition* -- one subdirectory -- not a blanket widening
    of the whole shared `practice_generator` fixtures tree).
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r11-plan-validator-and-repair.md"

# Reproduced verbatim from `.pipeline/HALTED` / the halted work copy's
# `.codex-round-status` (`scope_audit_violations=`) -- real measured data,
# not an invented fixture.
MEASURED_HALT_PATH = "test/fixtures/practice_generator/validation/validation_fixtures.dart"

# A plausible neighbour that must stay out of scope: it sits directly under
# the shared `practice_generator` fixtures root, not inside the newly
# allowed `validation/` subdirectory.
SIBLING_OUT_OF_SCOPE_PATH = "test/fixtures/practice_generator/validation_helper.dart"

# No protected-path fragment of the real `.ai/router.toml` touches either
# candidate path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E07R11ValidationFixtureScopeTest(unittest.TestCase):
    def make_repo(self) -> Path:
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

    def head(self, root: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def audit_untracked(self, root: Path, base: str, relative: str):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("shared fixture builders\n")
        allowed = load_brief(BRIEF).metadata.allowed_paths
        return audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

    def test_measured_halt_path_is_now_in_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, MEASURED_HALT_PATH)

        self.assertTrue(
            audit.ok,
            "E07-R11 allowed_paths must cover "
            "test/fixtures/practice_generator/validation/ (halt H3, 2026-08-16) "
            f"-- got violations: {audit.violations}",
        )
        self.assertIn(MEASURED_HALT_PATH, audit.changed_paths)

    def test_sibling_outside_the_new_subdirectory_remains_out_of_scope(self) -> None:
        """The fix widens scope narrowly: a file placed directly under the
        shared `practice_generator` fixtures root (sibling to, not inside,
        `validation/`) must still violate -- otherwise the self-heal would
        have silently legalized the whole shared fixtures tree instead of
        just the one subdirectory this round actually needs."""
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, SIBLING_OUT_OF_SCOPE_PATH)

        self.assertFalse(audit.ok)
        self.assertIn(
            f"path outside allowed scope: {SIBLING_OUT_OF_SCOPE_PATH}",
            audit.violations,
        )


if __name__ == "__main__":
    unittest.main()
