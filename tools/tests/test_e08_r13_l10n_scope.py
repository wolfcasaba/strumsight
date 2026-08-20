"""Regression guard for E08-R13/H3 (ADR 0112, 2026-08-20).

Measured on the stopped round at ``ecfbde54``: E08-R13 requires new
achievement translations, but its brief allowed only the generated
``lib/l10n/app_{en,hu}.arb`` aggregates.  Since E99-R17, translation changes
must originate in a feature segment and the aggregates must be regenerated.

This guard keeps the gamification source segments and generated outputs in
scope and requires the brief to name the deterministic regeneration step.
"""

import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = (
    REPO_ROOT
    / "docs"
    / "rounds"
    / "e08-r13-achievement-domain-and-catalog.md"
)

SOURCE_SEGMENTS = {
    "lib/l10n/features/gamification_en.arb",
    "lib/l10n/features/gamification_hu.arb",
}
GENERATED_AGGREGATES = {
    "lib/l10n/app_en.arb",
    "lib/l10n/app_hu.arb",
}


class E08R13L10nScopeTest(unittest.TestCase):
    def test_brief_allows_feature_segments_and_generated_aggregates(self) -> None:
        metadata = load_brief_metadata(BRIEF)
        allowed = set(metadata.allowed_paths)

        self.assertEqual(
            SOURCE_SEGMENTS - allowed,
            set(),
            "E08-R13 must write achievement translations to the gamification "
            "feature segments; aggregate-only scope reproduces H3",
        )
        self.assertEqual(
            GENERATED_AGGREGATES - allowed,
            set(),
            "E08-R13 must be able to commit the deterministic aggregate output",
        )

    def test_brief_requires_regeneration_not_manual_aggregate_edits(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        self.assertIn("dart run tool/gen_l10n_segments.dart --write", text)
        self.assertIn("generált aggregátum", text)
        self.assertIn("közvetlenül nem szerkeszthető", text)


if __name__ == "__main__":
    unittest.main()
