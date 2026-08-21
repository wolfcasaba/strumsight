"""Regression guard for the E13-R04/H3 typography scope self-heal.

Measured on the stopped round branch at ``54b32ed0``: ADR 0383 requires
``SsTypography`` to be added to the ``ThemeData`` returned by
``SsThemeExtensions.legacyThemeForBrightness``.  The existing
``test/core/design_system/foundations_test.dart`` contract instead compared
that result directly with the extension-free ``AppTheme.dark()`` and
``AppTheme.light()`` values.  The round could not honestly implement the
required integration while that existing test was outside both its allowlist
and its targeted gate.

The product change remains the stopped round's responsibility.  This guard
only requires that transaction to own the exact compatibility test and run it
in the same round gate; neighbouring design-system tests remain out of scope.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs/rounds/e13-r04-typography-and-text-scale.md"
FOUNDATIONS_TEST = "test/core/design_system/foundations_test.dart"

ORIGINAL_ALLOWED_PATHS = {
    "lib/core/design_system/foundations/ss_typography.dart",
    "lib/core/design_system/themes/ss_theme_extensions.dart",
    "lib/core/design_system/components/music/ss_chord_hero_text.dart",
    "lib/core/design_system/public.dart",
    "test/core/design_system/typography/ss_typography_test.dart",
    "test/core/design_system/typography/text_scale_overflow_test.dart",
    "docs/ui/typography.md",
    "docs/rounds/e13-r04-typography-and-text-scale.md",
}
ORIGINAL_GATE_TESTS = {
    "test/core/design_system/typography/ss_typography_test.dart",
    "test/core/design_system/typography/text_scale_overflow_test.dart",
}


class E13R04TypographyFoundationsScopeTest(unittest.TestCase):
    def _audit_untracked(self, relative: str):
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
        base = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("measured fixture\n", encoding="utf-8")
        return audit_legacy_scope(
            root,
            base=base,
            allowed_paths=load_brief(BRIEF).metadata.allowed_paths,
            protected_paths=(),
        )

    def test_allowed_paths_add_only_the_measured_compatibility_test(self) -> None:
        allowed = set(load_brief(BRIEF).metadata.allowed_paths)
        self.assertEqual(allowed - ORIGINAL_ALLOWED_PATHS, {FOUNDATIONS_TEST})
        self.assertEqual(ORIGINAL_ALLOWED_PATHS - allowed, set())

    def test_foundations_compatibility_test_is_in_real_scope(self) -> None:
        audit = self._audit_untracked(FOUNDATIONS_TEST)
        self.assertTrue(audit.ok, audit.violations)
        self.assertIn(FOUNDATIONS_TEST, audit.changed_paths)

    def test_neighbouring_foundation_test_remains_out_of_scope(self) -> None:
        sibling = "test/core/design_system/semantic_colors_test.dart"
        audit = self._audit_untracked(sibling)
        self.assertFalse(audit.ok)
        self.assertIn(f"path outside allowed scope: {sibling}", audit.violations)

    def test_compatibility_test_runs_in_the_round_gate(self) -> None:
        metadata = load_brief(BRIEF).metadata
        gate = set(metadata.gate_tests)
        self.assertEqual(gate - ORIGINAL_GATE_TESTS, {FOUNDATIONS_TEST})
        self.assertEqual(ORIGINAL_GATE_TESTS - gate, set())
        self.assertTrue(gate.issubset(set(metadata.allowed_paths)))

    def test_revision_records_the_measured_contract_collision(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("0.0.1", text)
        self.assertIn("H3", text)
        self.assertIn("equals(AppTheme.dark())", text)
        self.assertIn("equals(AppTheme.light())", text)
        self.assertIn(FOUNDATIONS_TEST, text)


if __name__ == "__main__":
    unittest.main()
