"""Regression guard for E07-R15's H3 self-heal (2026-08-16).

The measured halt was not a product scope violation: both permitted scheduling
tests import the same parameterized availability, budget, and candidate
builders, but the original brief named no shared-fixture location.  The
implementer consequently created the conventionally located
``test/fixtures/practice_generator/scheduling/scheduling_fixtures.dart``, and
the legacy scope audit correctly rejected that path.

This test drives the exact ``audit_legacy_scope()`` function used by
``tools/scope-audit.py`` against the committed brief.  It proves the narrow
repair in both directions: the measured scheduling fixture is allowed, while a
sibling directly under ``practice_generator`` remains forbidden.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r15-weekly-scheduler.md"
MEASURED_HALT_PATH = "test/fixtures/practice_generator/scheduling/scheduling_fixtures.dart"
SIBLING_OUT_OF_SCOPE_PATH = "test/fixtures/practice_generator/scheduling_helper.dart"


class E07R15SchedulingFixtureScopeTest(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "heal@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Heal Test"], cwd=root, check=True)
        (root / ".gitignore").write_text("build/\n")
        subprocess.run(["git", "add", ".gitignore"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    def audit_untracked(self, root: Path, relative_path: str):
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("shared fixture builders\n")
        base = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()
        return audit_legacy_scope(
            root,
            base=base,
            allowed_paths=load_brief(BRIEF).metadata.allowed_paths,
            protected_paths=(),
        )

    def test_measured_scheduling_fixture_is_in_scope(self) -> None:
        audit = self.audit_untracked(self.make_repo(), MEASURED_HALT_PATH)

        self.assertTrue(audit.ok, audit.violations)
        self.assertIn(MEASURED_HALT_PATH, audit.changed_paths)

    def test_sibling_outside_scheduling_fixture_directory_stays_out_of_scope(self) -> None:
        audit = self.audit_untracked(self.make_repo(), SIBLING_OUT_OF_SCOPE_PATH)

        self.assertFalse(audit.ok)
        self.assertIn(
            f"path outside allowed scope: {SIBLING_OUT_OF_SCOPE_PATH}", audit.violations
        )


if __name__ == "__main__":
    unittest.main()
