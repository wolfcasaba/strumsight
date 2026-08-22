"""Regression guard for the E09-R03 self-heal (ADR 0112, halt H3, 2026-08-22).

Measured root cause: the L411 pattern (E09-R02 self-heal, same halt class)
recurred one chain-link deeper. E09-R03's own §5 decision (ADR 0397) chains
the new handle migration onto the existing head --
`e09_r03_0003.down_revision = "e09_r02_0002"` -- which is correct (Alembic
allows exactly one head). But two cross-round regression tests, written
during E09-R02 to close THAT round's H3 halt, hardcoded a two-migration-world
assumption:

  * `backend/tests/community/test_profile_schema.py::
    test_alembic_upgrade_head_applies_community_migration` asserts
    `set(script_heads) == {"e09_r02_0002"}` ("round E09-R02 contract") --
    false once a third migration chains on top.
  * `backend/tests/community/test_profile_schema.py::
    test_alembic_downgrade_drops_community_tables` and
    `backend/tests/test_migrations.py::
    test_downgrade_one_revision_drops_only_community_tables` both assume
    `downgrade -1` from HEAD reverses the E09-R02 Community migration
    specifically -- true only while E09-R02's migration IS the head.

Neither file was in E09-R03's pre-dispatch `allowed_paths` (it only listed
the round's own new handle-policy files), so the implementer correctly
signalled `stopped` per the brief's STOP-protocol instead of silently
widening scope or rewriting the tests unsupervised (`.pipeline/HALTED`,
halt=H3, halted_at=2026-08-22T14:45:39+00:00). Reproduced independently:

    cd backend && .venv/bin/python -m pytest tests/test_migrations.py \\
        tests/community/test_profile_schema.py -q
    # 3 failed:
    #   test_migrations.py::test_downgrade_one_revision_drops_only_community_tables
    #   test_profile_schema.py::test_alembic_upgrade_head_applies_community_migration
    #   test_profile_schema.py::test_alembic_downgrade_drops_community_tables

This guard drives `tools.ai_router.legacy_scope.audit_legacy_scope` -- the
exact function `tools/scope-audit.py` calls for the legacy (Codex/MiniMax-M3)
implementer path this round runs on -- against the REAL, currently committed
brief so a regression in either direction shows up here first:

  * both measured halt paths must now pass (the gap the halt exposed is
    closed) -- the fix widens scope for BOTH files, not just one, because
    the same chain-shift breaks assertions in both of them;
  * a sibling top-level backend test file, untouched by this round, must
    keep failing (the fix is a narrow, two-file scope addition, not a
    blanket widening of `backend/tests/`).
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e09-r03-public-identity-and-handle-policy.md"

# Reproduced verbatim from `.pipeline/HALTED` (E09-R03, H3, 2026-08-22) --
# real measured data, not an invented fixture.
MEASURED_HALT_PATHS = (
    "backend/tests/test_migrations.py",
    "backend/tests/community/test_profile_schema.py",
)

# A plausible neighbour that must stay out of scope: it sits in the exact
# same directory as the migration tests but this round's fix never needs to
# touch it (auth tests are unrelated to the Community handle migration).
SIBLING_OUT_OF_SCOPE_PATH = "backend/tests/test_auth.py"

# No protected-path fragment of the real `.ai/router.toml` touches any
# candidate path; an empty tuple keeps this guard focused on `allowed_paths`.
PROTECTED = ()


class E09R03MigrationChainTestScopeTest(unittest.TestCase):
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

    def audit_untracked(self, root: Path, base: str, *relatives: str):
        for relative in relatives:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("migration chain test made head/downgrade assertions chain-tolerant\n")
        allowed = load_brief(BRIEF).metadata.allowed_paths
        return audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

    def test_both_measured_halt_paths_are_now_in_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        audit = self.audit_untracked(root, base, *MEASURED_HALT_PATHS)

        self.assertTrue(
            audit.ok,
            "E09-R03 allowed_paths must cover both "
            f"{MEASURED_HALT_PATHS} (halt H3, 2026-08-22) -- got violations: {audit.violations}",
        )
        for path in MEASURED_HALT_PATHS:
            self.assertIn(path, audit.changed_paths)

    def test_sibling_auth_test_remains_out_of_scope(self) -> None:
        """The fix widens scope narrowly: a sibling backend test file must
        still violate -- otherwise the self-heal would have silently
        legalized the whole `backend/tests/` directory instead of just the
        two migration-contract files R03 actually needs to extend."""
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
