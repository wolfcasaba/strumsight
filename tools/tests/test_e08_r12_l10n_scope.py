"""Regression guard for E08-R12/H6 (ADR 0112, 2026-08-20).

Measured on the stopped round worktree at ``524cf246``: the round brief
allowed direct edits to ``lib/l10n/app_{en,hu}.arb`` but did not allow a
feature segment.  Since E99-R17 those two aggregate files are generated from
``lib/l10n/base`` and ``lib/l10n/features``.  The implementer's otherwise
in-scope ARB additions therefore made ``gen_l10n_segments.dart --check`` fail
for both locales, while ``--write`` would have discarded the new keys because
no source segment contained them.

This guard keeps the round's source segments and generated outputs in scope
and requires the brief to name the deterministic regeneration step.
"""

import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = (
    REPO_ROOT
    / "docs"
    / "rounds"
    / "e08-r12-streak-ui-v2-and-recovery-flow.md"
)

SOURCE_SEGMENTS = {
    "lib/l10n/features/gamification_en.arb",
    "lib/l10n/features/gamification_hu.arb",
}
GENERATED_AGGREGATES = {
    "lib/l10n/app_en.arb",
    "lib/l10n/app_hu.arb",
}


class E08R12L10nScopeTest(unittest.TestCase):
    def test_brief_allows_feature_segments_and_generated_aggregates(self) -> None:
        metadata = load_brief_metadata(BRIEF)
        allowed = set(metadata.allowed_paths)

        self.assertEqual(
            SOURCE_SEGMENTS - allowed,
            set(),
            "E08-R12 must write new translations to gamification feature "
            "segments; editing only the generated aggregates reproduces H6",
        )
        self.assertEqual(
            GENERATED_AGGREGATES - allowed,
            set(),
            "E08-R12 must be able to commit the deterministic aggregate output",
        )

    def test_brief_requires_regeneration_instead_of_manual_aggregate_edits(
        self,
    ) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        self.assertIn("dart run tool/gen_l10n_segments.dart --write", text)
        self.assertIn("generált aggregátum", text)
        self.assertIn("közvetlenül nem szerkeszthető", text)


if __name__ == "__main__":
    unittest.main()
