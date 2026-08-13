"""Regression guard for the E06-R25 self-heal (ADR 0112, halt H3, 2026-08-13).

Measured root cause of the halt: the PREPARED E06-R25 brief (session
comparison + trend) requires a new flag-gated route -- its own §6 "Flag-őr"
acceptance criterion reads "flag OFF esetén a route nem oldható fel" (route
must not resolve while the flag is off), which is only meaningful if the
round actually registers a route. Registering any Audio Analysis V2 route is
owned by exactly two files app-wide:

  * lib/app/routing/app_router.dart -- the sole `GoRoute` registration site
    for every Audio Analysis V2 screen (measured: the single
    `audioAnalysisV2Enabled`-guarded block registers `analysisOverview`,
    `analysisMetricDetail` and `analysisTimeline`; nothing outside that block
    registers an analysis route).
  * lib/app/routing/app_route.dart -- the `AppRoutes` constant catalogue
    those `GoRoute`s are built from.

Neither file was in the brief's `allowed_paths`, so the first dispatch
(sonnet-impl) correctly reported `stopped` after touching zero files rather
than wiring the route outside its declared scope.

This is the THIRD time this exact batch-authoring gap -- a new Audio
Analysis V2 screen whose brief omits the shared router files -- has surfaced
in this batch (all three briefs were authored together on 2026-08-07):
E06-R23 measured and fixed it in its own pre-dispatch pre-flight (§0.0 point
1, no halt), and E06-R24 needed a second, halt-triggered pre-flight for it
(`docs/LESSONS.md` L250). L250 explicitly recommended grepping the rest of
the batch's still-pending briefs for the same pattern; that audit was not
carried out before E06-R25 was dispatched, hence this halt.

This guard encodes the measured truth as a machine check so the same halt
cannot silently return to this specific brief.
"""

import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e06-r25-session-comparison-and-trend.md"
APP_ROUTER = REPO_ROOT / "lib" / "app" / "routing" / "app_router.dart"
APP_ROUTE = REPO_ROOT / "lib" / "app" / "routing" / "app_route.dart"

ROUTER_PATH = "lib/app/routing/app_router.dart"
ROUTE_CATALOGUE_PATH = "lib/app/routing/app_route.dart"

# Audio Analysis V2 routes that already exist (E06-R23/E06-R24) -- proof that
# both files above are real, shared registration points and not a one-off.
EXISTING_V2_ROUTE_CONSTANTS = ("analysisOverview", "analysisMetricDetail", "analysisTimeline")


class E06R25RouterScopeTest(unittest.TestCase):
    def test_brief_declares_the_router_files_in_allowed_paths(self) -> None:
        """The halt trigger: allowed_paths must list both router-owning files."""
        metadata = load_brief_metadata(BRIEF)
        missing = {ROUTER_PATH, ROUTE_CATALOGUE_PATH} - set(metadata.allowed_paths)
        self.assertEqual(
            missing,
            set(),
            "E06-R25 allowed_paths is missing the shared router file(s) a new "
            f"flag-gated route must touch (halt H3 recurrence): {sorted(missing)}",
        )

    def test_app_router_is_still_the_sole_v2_route_registration_point(self) -> None:
        """Measured fact the fix relies on -- catch it drifting silently."""
        router_text = APP_ROUTER.read_text(encoding="utf-8")
        route_text = APP_ROUTE.read_text(encoding="utf-8")
        for constant in EXISTING_V2_ROUTE_CONSTANTS:
            self.assertIn(
                f"static const String {constant}",
                route_text,
                f"AppRoutes.{constant} moved out of app_route.dart -- "
                "re-measure the H3 fix before trusting this guard",
            )
            self.assertIn(
                f"AppRoutes.{constant}",
                router_text,
                f"the {constant} GoRoute moved out of app_router.dart -- "
                "re-measure the H3 fix before trusting this guard",
            )
        self.assertIn(
            "audioAnalysisV2Enabled",
            router_text,
            "Audio Analysis V2 routes are no longer flag-gated in app_router.dart "
            "-- re-measure the H3 fix before trusting this guard",
        )


if __name__ == "__main__":
    unittest.main()
