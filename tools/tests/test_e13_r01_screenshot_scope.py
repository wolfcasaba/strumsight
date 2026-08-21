r"""Regression guard for the E13-R01 H3 self-heal (2026-08-21).

The measured halt was a contract/scope contradiction: Chapter 13 R01
requires seven compact-portrait baseline screenshots and a check that they
are openable and non-empty, while the prepared round brief allowed neither
the screenshot files nor a screenshot-corpus test.  This guard exercises the
real brief parser and legacy scope audit so the fix cannot silently widen to
an entire directory or omit the executable evidence.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs/rounds/e13-r01-ui-baseline-inventory.md"

ORIGINAL_ALLOWED_PATHS = (
    "tool/ui_inventory.dart",
    "docs/ui/README.md",
    "docs/ui/migration-status.md",
    "docs/ui/baseline/route-map.md",
    "docs/ui/baseline/token-debt.md",
    "docs/ui/baseline/accessibility-findings.md",
    "test/ui/ui_inventory_test.dart",
    "docs/rounds/e13-r01-ui-baseline-inventory.md",
)
ORIGINAL_GATE_TESTS = ("test/ui/ui_inventory_test.dart",)

SCREENSHOT_PATHS = (
    "docs/ui/baseline/screenshots/live-compact-portrait.png",
    "docs/ui/baseline/screenshots/tuner-compact-portrait.png",
    "docs/ui/baseline/screenshots/analyze-compact-portrait.png",
    "docs/ui/baseline/screenshots/learn-compact-portrait.png",
    "docs/ui/baseline/screenshots/library-compact-portrait.png",
    "docs/ui/baseline/screenshots/settings-compact-portrait.png",
    "docs/ui/baseline/screenshots/onboarding-compact-portrait.png",
)
SCREENSHOT_TEST = "test/ui/ui_baseline_screenshot_test.dart"
NEW_ALLOWED_PATHS = SCREENSHOT_PATHS + (SCREENSHOT_TEST,)


class E13R01ScreenshotScopeTest(unittest.TestCase):
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
        (root / "baseline.txt").write_text("baseline\n")
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

    def _audit_untracked(self, root: Path, relative: str):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"measured fixture\n")
        return audit_legacy_scope(
            root,
            base=self._head(root),
            allowed_paths=load_brief(BRIEF).metadata.allowed_paths,
            protected_paths=(),
        )

    def test_exact_screenshot_files_and_validator_are_in_scope(self) -> None:
        for relative in NEW_ALLOWED_PATHS:
            root = self._make_repo()
            audit = self._audit_untracked(root, relative)
            self.assertTrue(
                audit.ok,
                f"{relative} must be in scope after the H3 brief revision: "
                f"{audit.violations}",
            )
            self.assertIn(relative, audit.changed_paths)

    def test_screenshot_directory_was_not_opened_broadly(self) -> None:
        root = self._make_repo()
        sibling = "docs/ui/baseline/screenshots/profile-compact-portrait.png"
        audit = self._audit_untracked(root, sibling)
        self.assertFalse(audit.ok)
        self.assertIn(f"path outside allowed scope: {sibling}", audit.violations)

    def test_allowed_paths_is_original_plus_exact_measured_gap(self) -> None:
        allowed = set(load_brief(BRIEF).metadata.allowed_paths)
        self.assertEqual(allowed - set(ORIGINAL_ALLOWED_PATHS), set(NEW_ALLOWED_PATHS))
        self.assertEqual(set(ORIGINAL_ALLOWED_PATHS) - allowed, set())

    def test_gate_adds_exactly_the_screenshot_validator(self) -> None:
        metadata = load_brief(BRIEF).metadata
        gate = set(metadata.gate_tests)
        self.assertEqual(gate - set(ORIGINAL_GATE_TESTS), {SCREENSHOT_TEST})
        self.assertEqual(set(ORIGINAL_GATE_TESTS) - gate, set())
        self.assertTrue(gate.issubset(set(metadata.allowed_paths)))

    def test_brief_keeps_all_seven_named_sdd_states_executable(self) -> None:
        brief_text = BRIEF.read_text()
        self.assertEqual(len(SCREENSHOT_PATHS), 7)
        for path in SCREENSHOT_PATHS:
            self.assertIn(path, brief_text)
        self.assertIn("decodeImageFromList", brief_text)
        self.assertIn("compact portrait", brief_text.lower())


if __name__ == "__main__":
    unittest.main()
