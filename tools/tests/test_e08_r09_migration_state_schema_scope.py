"""Regression guard for the E08-R09 self-heal (ADR 0112, halt H3, 2026-08-20).

Measured root cause of the halt: the E08-R09 brief's bound decision (§5.3,
ADR 0307) requires a *persisted* migration checkpoint -- A5: "Félbeszakadt
migráció az ellenőrzőponttól folytatódik, nem elölről" -- but the only place
that checkpoint state can live, `GamificationMigrationState` in
`lib/features/gamification/data/gamification_storage_schema.dart`, was left
by the immediately prior round as a version-only placeholder on purpose:
ADR 0344 (E08-R08, accepted 2026-08-20) D7 states "A tényleges migrációs
mezőket a Kör 9/10 ... tölti ki" (measured, `main @ 71512fff`):

    nl -ba lib/features/gamification/data/gamification_storage_schema.dart \
      | sed -n '121,135p'
    #   121  /// Versioned placeholder for the migration state contract owned by R09/R10.
    #   122  final class GamificationMigrationState {
    #   123    const GamificationMigrationState()
    #   124      : schemaVersion = gamificationStorageSchemaVersion;
    #   126    final int schemaVersion;
    #   ...    -- no other field: nowhere to put a checkpoint

The pre-dispatch E08-R09 `allowed_paths` never listed that schema file (it
only listed the two NEW migration files plus the barrel and the round's own
test), so the round could not satisfy its own §5.3/A5 without either editing
a file outside scope (`stopped`) or silently widening `allowed_paths` (the
one thing this repo's self-heal protocol forbids doing quietly). The
orchestrator correctly halted (H3) before ever dispatching the implementer
(`.pipeline/HALTED`, halted_at=2026-08-20T09:53:07+00:00, "implementer/PR/CI
nem indult").

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls -- against the REAL, currently
committed brief so a regression in either direction shows up here first:

  * the measured halt path must now pass (the gap the halt exposed is
    closed);
  * a sibling file in the SAME directory
    (`gamification_repository.dart`, the repository interface -- untouched
    by this round) must keep failing (the fix is a narrow, single-file scope
    *addition*, not a blanket widening of the whole `data/` directory).
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e08-r09-legacy-progress-adapter-and-backfill.md"

# Reproduced verbatim from `.pipeline/HALTED` (E08-R09, H3, 2026-08-20) --
# real measured data, not an invented fixture.
MEASURED_HALT_PATH = "lib/features/gamification/data/gamification_storage_schema.dart"

# A plausible neighbour that must stay out of scope: it sits in the exact
# same directory as the schema file but is the repository INTERFACE, which
# this round's §5.3/A5 checkpoint work never needs to touch.
SIBLING_OUT_OF_SCOPE_PATH = "lib/features/gamification/data/gamification_repository.dart"

# No protected-path fragment of the real `.ai/router.toml` touches either
# candidate path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E08R09MigrationStateSchemaScopeTest(unittest.TestCase):
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
        path.write_text("checkpoint field addition\n")
        allowed = load_brief(BRIEF).metadata.allowed_paths
        return audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

    def test_measured_halt_path_is_now_in_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, MEASURED_HALT_PATH)

        self.assertTrue(
            audit.ok,
            "E08-R09 allowed_paths must cover "
            "lib/features/gamification/data/gamification_storage_schema.dart "
            "(halt H3, 2026-08-20) -- got violations: "
            f"{audit.violations}",
        )
        self.assertIn(MEASURED_HALT_PATH, audit.changed_paths)

    def test_sibling_repository_interface_remains_out_of_scope(self) -> None:
        """The fix widens scope narrowly: the repository INTERFACE file next
        to the schema file must still violate -- otherwise the self-heal
        would have silently legalized the whole `data/` directory instead of
        just the one schema file R09 actually needs to extend."""
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
