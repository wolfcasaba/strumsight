"""Regression guard for E16-R02 / H3 (ADR 0112 önjavító kör, 2026-09-03).

Measured on ``main @ 619232dd`` — the round's own pre-flight halted because the
brief promised to wire ``/profile/progress`` to ``ProgressDashboardScreen``
"valós projekcióval" while the mastery half of that projection had **no source
on the tree**::

    grep -rn "MasteryMilestone(" --include=*.dart lib test
    #   -> 9 sites: 1 definition + 8 tests, production catalog: 0
    grep -rn "List<MasteryMilestone>|milestoneCatalog" --include=*.dart lib
    #   -> 0 hits
    grep -rln "MasteryEvidence" --include=*.dart lib
    #   -> 4 files, not one of them a data/ producer
    grep -o '"[a-zA-Z0-9]*"' lib/l10n/app_en.arb | grep -i "mastery|milestone"
    #   -> 3 chrome keys, no milestone title/description

Why the round's own acceptance cells were blind to it: with an empty milestone
list ``ProgressOverviewProjection.isNewUser`` is ``true``
(``[].every(...)``, ``progress_overview_projection.dart:65``), so
``ProgressDashboardScreen`` renders ONLY ``_NewUserState``
(``progress_dashboard_screen.dart:38``). A1-A7 stayed green because each one
feeds the projection directly — the green gate would have shipped a route
switch that replaces the legacy ``ProgressScreen`` (which shows real data
today, ``app_router.dart:545``) with a permanently empty "get started" screen.

The self-heal did not weaken a cell and did not defer the route switch: it put
the missing SOURCE into the round (catalog, practice->evidence adapter,
milestone l10n segment + regenerated aggregates) and added the A8-A11 cells,
A10 being the one that turns exactly this failure mode red.

This guard is red on the pre-revision brief.
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

# The three missing pieces the halt measured, plus the barrels they must be
# reachable through.
MASTERY_SOURCE_PATHS = {
    "lib/features/gamification/domain/mastery/mastery_milestone_catalog.dart",
    "lib/features/gamification/data/practice_mastery_evidence_adapter.dart",
    "lib/features/gamification/public.dart",
    "lib/features/practice/public.dart",
}
SOURCE_SEGMENTS = {
    "lib/l10n/features/gamification_en.arb",
    "lib/l10n/features/gamification_hu.arb",
}
GENERATED_AGGREGATES = {
    "lib/l10n/app_en.arb",
    "lib/l10n/app_hu.arb",
}
NEW_GATE_TESTS = {
    "test/features/gamification/domain/mastery_milestone_catalog_test.dart",
    "test/features/gamification/data/practice_mastery_evidence_adapter_test.dart",
    "test/features/progress_v2/dashboard_states_test.dart",
    "test/l10n/arb_parity_test.dart",
    "test/tooling/gen_l10n_segments_test.dart",
}
PRESERVED_CELLS = ("| A1 |", "| A2 |", "| A3 |", "| A4 |", "| A5 |", "| A6 |", "| A7 |")


class E16R02MasterySourceScopeTest(unittest.TestCase):
    def test_brief_allows_the_missing_mastery_source(self) -> None:
        allowed = set(load_brief_metadata(BRIEF).allowed_paths)

        self.assertEqual(
            MASTERY_SOURCE_PATHS - allowed,
            set(),
            "E16-R02 must be able to author the milestone catalog and the "
            "practice->MasteryEvidence adapter; without them the wired "
            "dashboard is stuck in its new-user state (H3, 2026-09-03)",
        )
        self.assertEqual(
            SOURCE_SEGMENTS - allowed,
            set(),
            "milestone titles/descriptions have no ARB key on the tree — the "
            "round must write them to the feature segments",
        )
        self.assertEqual(
            GENERATED_AGGREGATES - allowed,
            set(),
            "the deterministic aggregate output must be committable "
            "(E08-R12/H6 class)",
        )

    def test_gate_runs_the_new_source_cells(self) -> None:
        metadata = load_brief_metadata(BRIEF)
        text = BRIEF.read_text(encoding="utf-8")

        self.assertEqual(
            NEW_GATE_TESTS - set(metadata.gate_tests),
            set(),
            "the catalog, adapter, dashboard-state and l10n guards must be in "
            "the round's gate — a source added outside the gate is unmeasured",
        )
        for gate in NEW_GATE_TESTS:
            self.assertIn(
                gate,
                text,
                f"the §7 round-gate command must actually run {gate}",
            )
        self.assertIn("dart run tool/gen_l10n_segments.dart --write", text)
        self.assertIn("generált aggregátum", text)
        self.assertIn("közvetlenül nem szerkeszthető", text)

    def test_empty_dashboard_failure_mode_has_its_own_cell(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        self.assertIn(
            "| A10 |",
            text,
            "the halt's failure mode (wired route rendering the new-user "
            "state forever) needs a cell of its own",
        )
        self.assertIn(
            "new-user",
            text,
            "the A10 cell must name the state it forbids",
        )
        self.assertIn(
            "const <MasteryMilestone>[]",
            text,
            "the §6.1 falsification probe must empty the catalog and require "
            "A8/A10 to go red",
        )

    def test_revision_kept_every_original_cell(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        for cell in PRESERVED_CELLS:
            self.assertIn(
                cell,
                text,
                f"the self-heal must not drop {cell.strip('| ')} — widening "
                "the source scope is the fix, weakening the bar is not",
            )


if __name__ == "__main__":
    unittest.main()
