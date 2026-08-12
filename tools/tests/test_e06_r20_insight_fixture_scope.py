"""Regression guard for the E06-R20 self-heal (ADR 0112, halt H3, 2026-08-12).

Measured root cause of the halt: the E06-R20 brief's `allowed_paths` names
four exact test files (three under `test/features/audio_analysis/engine/`
and one under `test/property/`) but no shared-fixture location. The round's
own §6 acceptance criteria (an 18-cell rule matrix, threshold triplets on
both sides of two thresholds, a referential-integrity property test, and a
localization-parity sweep) all need the SAME `AnalysisDocument` /
`AnalysisInsightContext` construction across those independent test files --
exactly the case the repo's established `test/fixtures/<feature>/<sub>/
*_fixtures.dart` convention exists for (precedent: the E05-R20 brief
pre-allows `test/fixtures/vision/posture` for the identical reason; ADR 0228
Kontextus records an earlier H3 self-heal, PR #224, that resolved an
analogous gap by retargeting `allowed_paths`).

Measured halt: with no allowed fixture location, the MiniMax M3 implementer
improvised `test/features/audio_analysis/engine/insights/
_insight_test_helpers.dart` (branch `codex/e06-r20-deterministic-insights-
and-hotspots`, commit `fa836e87`, work copy `/home/ubuntu/ss-mm-e06-r20`) --
outside `allowed_paths` -- and self-halted per its own STOP protocol:

    python3 tools/scope-audit.py --repo /home/ubuntu/ss-mm-e06-r20 \
      --brief docs/rounds/e06-r20-deterministic-insights-and-hotspots.md \
      --base fa836e87
    -> exit 1, "path outside allowed scope:
       test/features/audio_analysis/engine/insights/_insight_test_helpers.dart"

(`.pipeline/HALTED`, halted_at=2026-08-12T16:53:49+00:00.)

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls -- against the REAL, currently
committed brief so a regression in either direction shows up here first:

  * a file placed under the new `test/fixtures/analysis/insights/` location
    must pass (the gap the halt exposed is closed);
  * the halted run's own ad hoc path must keep failing (the fix is a scope
    *addition*, not a blanket weakening of the audit).
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e06-r20-deterministic-insights-and-hotspots.md"

# Reproduced verbatim from `.pipeline/HALTED` / the halted work copy's
# `git status --porcelain` -- real measured data, not an invented fixture.
MEASURED_HALT_PATH = "test/features/audio_analysis/engine/insights/_insight_test_helpers.dart"

NEW_FIXTURE_PATH = "test/fixtures/analysis/insights/insight_fixtures.dart"

# No protected-path fragment of the real `.ai/router.toml` touches either
# candidate path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E06R20InsightFixtureScopeTest(unittest.TestCase):
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

    def test_new_shared_fixtures_directory_is_in_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, NEW_FIXTURE_PATH)

        self.assertTrue(
            audit.ok,
            "E06-R20 allowed_paths must cover test/fixtures/analysis/insights/ "
            f"(halt H3, 2026-08-12) -- got violations: {audit.violations}",
        )
        self.assertIn(NEW_FIXTURE_PATH, audit.changed_paths)

    def test_measured_halt_path_remains_correctly_out_of_scope(self) -> None:
        """The fix widens scope narrowly: it must not retroactively legalize
        the halted run's own ad hoc location, or the audit would no longer
        discriminate at all."""
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, MEASURED_HALT_PATH)

        self.assertFalse(audit.ok)
        self.assertIn(
            f"path outside allowed scope: {MEASURED_HALT_PATH}",
            audit.violations,
        )


if __name__ == "__main__":
    unittest.main()
