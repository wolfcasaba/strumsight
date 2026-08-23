"""Regression guard for the E13-R05/H3 component-catalog scope self-heal.

Measured on PR #392 at ``03788441``: the corrected ``SsCard`` deliberately
uses the single ``Material`` owned by ``SsSurface`` and no legacy ``Card``.
The existing ``test/core/design_system/component_catalog_test.dart`` still
required one ``Card`` in three widget cells, so the Full Gate failed with
``Found 0 widgets with type \"Card\"``.  That existing contract was outside
both the round allowlist and its targeted gate.

The product/test transaction remains the stopped round's responsibility.
This guard only requires the exact catalog contract to be owned and executed
by the round; neighbouring design-system tests remain outside the grant.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs/rounds/e13-r05-spacing-and-surfaces.md"
CATALOG_TEST = "test/core/design_system/component_catalog_test.dart"

ORIGINAL_ALLOWED_PATHS = {
    "lib/core/design_system/foundations/ss_elevation.dart",
    "lib/core/design_system/components/surfaces/ss_surface.dart",
    "lib/core/design_system/components/surfaces/ss_card.dart",
    "lib/core/design_system/components/surfaces/ss_hero_card.dart",
    "lib/core/design_system/components/surfaces/ss_section.dart",
    "lib/core/design_system/documentation/component_catalog_screen.dart",
    "lib/core/design_system/public.dart",
    "test/core/design_system/surfaces/ss_surface_test.dart",
    "test/core/design_system/surfaces/spacing_grid_test.dart",
    "docs/rounds/e13-r05-spacing-and-surfaces.md",
}
ORIGINAL_GATE_TESTS = {
    "test/core/design_system/surfaces/ss_surface_test.dart",
    "test/core/design_system/surfaces/spacing_grid_test.dart",
}


class E13R05ComponentCatalogScopeTest(unittest.TestCase):
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

    def test_allowed_paths_add_only_the_measured_catalog_contract(self) -> None:
        allowed = set(load_brief(BRIEF).metadata.allowed_paths)
        self.assertEqual(allowed - ORIGINAL_ALLOWED_PATHS, {CATALOG_TEST})
        self.assertEqual(ORIGINAL_ALLOWED_PATHS - allowed, set())

    def test_catalog_contract_is_in_real_scope(self) -> None:
        audit = self._audit_untracked(CATALOG_TEST)
        self.assertTrue(audit.ok, audit.violations)
        self.assertIn(CATALOG_TEST, audit.changed_paths)

    def test_neighbouring_design_system_test_remains_out_of_scope(self) -> None:
        sibling = "test/core/design_system/foundations_test.dart"
        audit = self._audit_untracked(sibling)
        self.assertFalse(audit.ok)
        self.assertIn(f"path outside allowed scope: {sibling}", audit.violations)

    def test_catalog_contract_runs_in_the_round_gate(self) -> None:
        metadata = load_brief(BRIEF).metadata
        gate = set(metadata.gate_tests)
        self.assertEqual(gate - ORIGINAL_GATE_TESTS, {CATALOG_TEST})
        self.assertEqual(ORIGINAL_GATE_TESTS - gate, set())
        self.assertTrue(gate.issubset(set(metadata.allowed_paths)))

    def test_revision_records_the_measured_card_collision(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("0.0.1", text)
        self.assertIn("H3", text)
        self.assertIn("find.byType(Card)", text)
        self.assertIn('Found 0 widgets with type "Card"', text)
        self.assertIn(CATALOG_TEST, text)


if __name__ == "__main__":
    unittest.main()
