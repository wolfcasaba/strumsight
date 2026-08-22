"""Regression guard for the E09-R02 self-heal (ADR 0112, halt H3, 2026-08-22).

Measured root cause of the halt: the round's own §0.0/§5 decision (ADR 0396)
chains the new migration onto the existing one --
`e09_r02_0002.down_revision = "e01_r12_0001"` -- but
`backend/tests/test_migrations.py::test_downgrade_one_revision_removes_application_schema`
hardcodes a single-migration-world assumption ("`downgrade -1` from head ==
`users`/`user_settings` gone"). Once the chain has two links, `downgrade -1`
from head only reverts the newest migration (the Community tables), leaving
`users`/`user_settings` in place -- a necessary, foreseeable consequence of
the round's own migration-chaining decision, not a bug in the new migration.

`backend/tests/test_migrations.py` was never in the pre-dispatch
`allowed_paths` (it only listed the two new Community test files), so the
implementer correctly signalled `blocked` per the brief's STOP-protocol
instead of silently widening scope or rewriting the test unsupervised
(`.pipeline/HALTED`, halt=H3, halted_at=2026-08-22T12:41:38+00:00). Reproduced
independently:

    cd backend && python -m pytest tests/test_migrations.py -q
    # FAILED test_downgrade_one_revision_removes_application_schema
    # AssertionError: assert 'users' not in
    #     {'alembic_version', 'user_settings', 'users'}

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls for the legacy (Codex/MiniMax-M3)
implementer path this round runs on -- against the REAL, currently committed
brief so a regression in either direction shows up here first:

  * the measured halt path must now pass (the gap the halt exposed is
    closed);
  * a sibling top-level backend test file, untouched by this round, must
    keep failing (the fix is a narrow, single-file scope addition, not a
    blanket widening of the whole `backend/tests/` directory).
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e09-r02-backend-community-module-and-migration.md"

# Reproduced verbatim from `.pipeline/HALTED` (E09-R02, H3, 2026-08-22) --
# real measured data, not an invented fixture.
MEASURED_HALT_PATH = "backend/tests/test_migrations.py"

# A plausible neighbour that must stay out of scope: it sits in the exact
# same directory as the migration test but this round's §0.1 fix never
# needs to touch it (auth tests are unrelated to the Community migration
# chain).
SIBLING_OUT_OF_SCOPE_PATH = "backend/tests/test_auth.py"

# No protected-path fragment of the real `.ai/router.toml` touches either
# candidate path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E09R02MigrationDowngradeTestScopeTest(unittest.TestCase):
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
        path.write_text("downgrade test split into two-migration cases\n")
        allowed = load_brief(BRIEF).metadata.allowed_paths
        return audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

    def test_measured_halt_path_is_now_in_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, MEASURED_HALT_PATH)

        self.assertTrue(
            audit.ok,
            "E09-R02 allowed_paths must cover backend/tests/test_migrations.py "
            f"(halt H3, 2026-08-22) -- got violations: {audit.violations}",
        )
        self.assertIn(MEASURED_HALT_PATH, audit.changed_paths)

    def test_sibling_auth_test_remains_out_of_scope(self) -> None:
        """The fix widens scope narrowly: a sibling backend test file must
        still violate -- otherwise the self-heal would have silently
        legalized the whole `backend/tests/` directory instead of just the
        one migration test file R02 actually needs to extend."""
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
