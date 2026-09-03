"""Regression guard for E16-R02 / H3, 3rd pre-flight (ADR 0112, 2026-09-03).

Measured on ``main @ b685831a`` (the §0.0.H and §0.0.I revisions already in).
The round's THIRD pre-flight halted because cell A1 rebinds ``/profile/progress``
from the legacy ``ProgressScreen`` to ``ProgressDashboardScreen``, while three
tests that live OUTSIDE the brief reach that screen through exactly that route::

    sed -n '247,255p' test/features/today/hub_navigation_test.dart
    # shell-ON router, router.go(AppRoutes.progress) -> ProgressScreen
    flutter test test/features/today/hub_navigation_test.dart
    # 00:03 +8: All tests passed!  <- a LIVE guard, not an already-red test

Neither ``allowed_paths`` nor ``gate_tests`` carried them, so the implementer
could not touch them and the round's targeted gate would have gone green on a
tree the round turns red — the L593 class, from the outside this time.

The §0.0.J revision puts all three on BOTH lists without weakening a single
cell. This guard is red on the pre-revision brief.
"""

import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = (
    REPO_ROOT
    / "docs"
    / "rounds"
    / "e16-r02-progress-projection-and-router-placeholders.md"
)
ROUTER = REPO_ROOT / "lib" / "app" / "routing" / "app_router.dart"

# The tests that reach ProgressScreen through the rebound route (halt §1/§2).
ROUTE_PINS = (
    "test/features/today/hub_navigation_test.dart",
    "test/app/routing/app_router_test.dart",
    "test/app/offline_network_guard_test.dart",
)
# Measured clean: they build the screen directly, no router involved.
NON_ROUTE_PINS = (
    "test/core/screen_size_guard_test.dart",
    "test/features/progress/progress_screen_test.dart",
)


class E16R02HubNavigationPinScopeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.metadata = load_brief_metadata(BRIEF)
        self.text = BRIEF.read_text(encoding="utf-8")

    def test_every_route_level_pin_is_on_both_lists(self) -> None:
        allowed = set(self.metadata.allowed_paths)
        gate = set(self.metadata.gate_tests)

        for pin in ROUTE_PINS:
            self.assertIn(
                pin,
                allowed,
                f"{pin} pins ProgressScreen on the route this round rebinds; "
                "without the permission the implementer cannot update it (H3)",
            )
            self.assertIn(
                pin,
                gate,
                f"{pin} must run on the round's OWN gate — otherwise the "
                "targeted gate is green on a tree the round turns red (L593)",
            )

    def test_the_gate_command_mirrors_the_new_entries(self) -> None:
        section = self.text.split("## 7.", 1)[1]

        for pin in ROUTE_PINS:
            self.assertIn(
                pin,
                section,
                f"the §7 gate command must run {pin} too (S12) — the metadata "
                "and the command that actually runs must not drift apart",
            )

    def test_the_permission_is_narrow_and_forbids_weakening(self) -> None:
        table = self.text.split("## 4.", 1)[1].split("## 5.", 1)[0]

        self.assertIn(
            "hub_navigation_test.dart",
            table,
            "the §4 allowed-files table must carry the new guards with their "
            "narrow reason, not only the ai-router block",
        )
        self.assertRegex(
            table,
            r"hub_navigation_test\.dart[^|]*\|[^|]*TILOS",
            "the row must say that deleting, skipping or weakening the cell is "
            "forbidden — only the EXPECTED SCREEN TYPE may change",
        )

    def test_screens_built_without_the_router_stay_out_of_scope(self) -> None:
        allowed = set(self.metadata.allowed_paths)

        for pin in NON_ROUTE_PINS:
            self.assertNotIn(
                pin,
                allowed,
                f"{pin} builds ProgressScreen directly (or is the legacy "
                "screen's own test, inside the forbidden zone) — a "
                "GoRoute.builder rebinding cannot turn it red, so widening "
                "scope to it would be unmeasured permission",
            )

    def test_the_premise_still_holds_on_the_tree(self) -> None:
        """If the route no longer builds the legacy screen, re-measure."""
        self.assertIn(
            "const ProgressScreen()",
            ROUTER.read_text(encoding="utf-8"),
            "the round's starting point is that /profile/progress still "
            "builds the legacy screen; if that changed, this guard must be "
            "re-measured, not deleted",
        )


if __name__ == "__main__":
    unittest.main()
