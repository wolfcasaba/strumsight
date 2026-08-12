"""Regression guard for the E06-R23 self-heal (ADR 0112, halt H3, 2026-08-12).

Measured root cause of the halt: the sonnet-impl implementer organized the
`OverviewLabels` port's `AppLocalizations`-backed implementation (declared in
`presentation/controllers/overview_view_model.dart`, per the round's own §5
"the presentation layer does not compute, only formats" rule) into its own
file, `lib/features/audio_analysis/presentation/widgets/labels_adapter.dart`
(406 lines) -- necessary, non-duplicative i18n glue code the round's own §6
acceptance criteria require (language parity, no raw ARB keys surfaced) --
but neither the original 2026-08-07 batch-brief nor the 2026-08-12 pre-flight
revision (commit `86c8181`, which fixed the router path and added ADR 0241)
listed it in `allowed_paths`. The scope-audit (`tools/mm-round.sh` ->
`tools/round-scope-audit.sh` -> `tools/scope-audit.py`) correctly detected
this and forced `status=stopped`:

    .pipeline/HALTED, halted_at=2026-08-12T22:17:52+00:00
    summary=Scope violation: ... labels_adapter.dart ... outside the
      committed brief allowed_paths list.

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls -- against the REAL, currently
committed brief, both as it stands now and as it stood at the moment of the
halt (derived from the current file by removing exactly the two entries this
self-heal added -- not read via `git show <ancestor-sha>`, because CI's
default shallow checkout does not fetch ancestor commit objects and would
make this test flaky in exactly the environment it needs to guard):

  * with the two self-heal-added entries removed, `labels_adapter.dart` must
    be OUT of scope -- this reproduces the measured halt;
  * against the current, self-heal-revised `allowed_paths`, it must be IN
    scope -- the fix.
"""

import tempfile
import subprocess
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e06-r23-analysis-overview-and-metric-cards.md"

# Reproduced verbatim from `.pipeline/HALTED`.
MEASURED_HALT_PATH = "lib/features/audio_analysis/presentation/widgets/labels_adapter.dart"

# The other entry this same self-heal commit added alongside the fix itself
# (its own regression test) -- excluded from the "pre-heal" reconstruction
# below so that snapshot reflects only the pre-flight (86c8181) allowed_paths.
SELF_HEAL_TEST_PATH = "tools/tests/test_e06_r23_labels_adapter_scope.py"

# No protected-path fragment of the real `.ai/router.toml` touches either
# path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E06R23LabelsAdapterScopeTest(unittest.TestCase):
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

    def audit_with(self, allowed_paths):
        root = self.make_repo()
        base = self.head(root)
        path = root / MEASURED_HALT_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("// AppLocalizations-backed OverviewLabels adapter\n")
        return audit_legacy_scope(root, base=base, allowed_paths=allowed_paths, protected_paths=PROTECTED)

    def pre_heal_allowed_paths(self) -> tuple:
        current = load_brief(BRIEF).metadata.allowed_paths
        pre_heal = tuple(p for p in current if p not in {MEASURED_HALT_PATH, SELF_HEAL_TEST_PATH})
        # Sanity check the subtraction actually removed both self-heal
        # additions and nothing else -- otherwise this reconstruction would
        # silently stop matching the real pre-flight (86c8181) allowed_paths.
        assert len(pre_heal) == len(current) - 2, (
            "expected the self-heal to have added exactly two allowed_paths entries "
            f"(got current={len(current)}, reconstructed pre-heal={len(pre_heal)})"
        )
        return pre_heal

    def test_pre_heal_brief_correctly_rejected_the_file(self) -> None:
        pre_heal_allowed = self.pre_heal_allowed_paths()
        self.assertNotIn(
            MEASURED_HALT_PATH, pre_heal_allowed,
            "sanity check: the pre-flight allowed_paths must not already list labels_adapter.dart",
        )

        audit = self.audit_with(pre_heal_allowed)

        self.assertFalse(
            audit.ok,
            "the pre-flight brief must NOT have allowed labels_adapter.dart -- this reproduces the H3 halt",
        )
        self.assertIn(f"path outside allowed scope: {MEASURED_HALT_PATH}", audit.violations)

    def test_current_self_heal_revised_brief_allows_the_file(self) -> None:
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self.assertIn(
            MEASURED_HALT_PATH, allowed,
            "E06-R23 allowed_paths must cover labels_adapter.dart after the H3 self-heal (2026-08-12)",
        )

        audit = self.audit_with(allowed)

        self.assertTrue(
            audit.ok,
            f"labels_adapter.dart must be in scope after the self-heal fix -- got violations: {audit.violations}",
        )
        self.assertIn(MEASURED_HALT_PATH, audit.changed_paths)


if __name__ == "__main__":
    unittest.main()
