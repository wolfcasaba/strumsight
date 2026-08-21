"""Regression guard for the E08-R15/H3 baseline-scope self-heal.

Measured on PR #383 at ``ae562c34``: the achievement list and detail screen
raise the deterministic production-screen inventory from 58 to 60.  The
prepared E08-R15 brief allowed the two new screens but did not allow the UI
inventory test or its baseline documentation to move in the same product
transaction, so the exact-SHA Full Gate failed with 5442 passing tests and
only ``test/ui/ui_inventory_test.dart`` failing.

The heal must not pre-increment the baseline on ``main`` while the product
screens are absent.  Instead, this guard requires the stopped round to own the
three exact baseline files and to execute the inventory test in its gate.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs/rounds/e08-r15-achievement-ui-and-evidence.md"

ORIGINAL_ALLOWED_PATHS = {
    "lib/features/gamification/presentation/screens/achievements_screen.dart",
    "lib/features/gamification/presentation/screens/achievement_detail_screen.dart",
    "lib/features/gamification/presentation/widgets/achievement_tile.dart",
    "lib/features/gamification/public.dart",
    "lib/l10n/app_en.arb",
    "lib/l10n/app_hu.arb",
    "test/features/gamification/presentation/achievements_screen_test.dart",
    "docs/rounds/e08-r15-achievement-ui-and-evidence.md",
}
# The stopped product branch already carries this earlier, independently
# reviewed pre-flight scope correction.  ``main`` does not yet carry it, so
# the H3 guard accepts either side of that merge without opening any other
# path.
KNOWN_ROUND_PREFLIGHT_PATHS = {
    "lib/l10n/features/gamification_en.arb",
    "lib/l10n/features/gamification_hu.arb",
}
BASELINE_PATHS = {
    "docs/ui/baseline/route-map.md",
    "docs/ui/migration-status.md",
    "test/ui/ui_inventory_test.dart",
}
ORIGINAL_GATE_TESTS = {
    "test/features/gamification/presentation/achievements_screen_test.dart",
}
INVENTORY_TEST = "test/ui/ui_inventory_test.dart"


class E08R15UiInventoryScopeTest(unittest.TestCase):
    def _make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "heal@example.invalid"],
            cwd=root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Heal Test"],
            cwd=root,
            check=True,
        )
        (root / "baseline.txt").write_text("baseline\n", encoding="utf-8")
        subprocess.run(["git", "add", "baseline.txt"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    @staticmethod
    def _head(root: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def _audit_untracked(self, relative: str):
        root = self._make_repo()
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("measured fixture\n", encoding="utf-8")
        return audit_legacy_scope(
            root,
            base=self._head(root),
            allowed_paths=load_brief(BRIEF).metadata.allowed_paths,
            protected_paths=(),
        )

    def test_allowed_paths_add_exact_transactional_baseline_gap(self) -> None:
        allowed = set(load_brief(BRIEF).metadata.allowed_paths)
        extras = allowed - ORIGINAL_ALLOWED_PATHS
        self.assertEqual(extras - KNOWN_ROUND_PREFLIGHT_PATHS, BASELINE_PATHS)
        self.assertEqual(
            extras - BASELINE_PATHS,
            extras & KNOWN_ROUND_PREFLIGHT_PATHS,
        )
        self.assertEqual(ORIGINAL_ALLOWED_PATHS - allowed, set())

    def test_each_measured_baseline_file_is_in_scope(self) -> None:
        for relative in BASELINE_PATHS:
            audit = self._audit_untracked(relative)
            self.assertTrue(audit.ok, f"{relative}: {audit.violations}")
            self.assertIn(relative, audit.changed_paths)

    def test_unrelated_ui_baseline_file_remains_out_of_scope(self) -> None:
        sibling = "docs/ui/baseline/token-debt.md"
        audit = self._audit_untracked(sibling)
        self.assertFalse(audit.ok)
        self.assertIn(f"path outside allowed scope: {sibling}", audit.violations)

    def test_inventory_guard_runs_in_the_round_gate(self) -> None:
        metadata = load_brief(BRIEF).metadata
        gate = set(metadata.gate_tests)
        self.assertEqual(gate - ORIGINAL_GATE_TESTS, {INVENTORY_TEST})
        self.assertEqual(ORIGINAL_GATE_TESTS - gate, set())
        self.assertTrue(gate.issubset(set(metadata.allowed_paths)))

    def test_revision_records_the_measured_58_to_60_transaction(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("58 → 60", text)
        self.assertIn("achievement_detail_screen.dart", text)
        self.assertIn("achievements_screen.dart", text)
        self.assertIn("ugyanabban a product-commitban", text)


if __name__ == "__main__":
    unittest.main()
