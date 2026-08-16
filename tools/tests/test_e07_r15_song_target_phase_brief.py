"""Regression guard for E07-R15 H7 (ADR 0112, 2026-08-16).

The halted implementation had correctly changed phase calculation to the
signed ``songTargetDate - scheduledDate`` distance.  Its pre-existing test
still expected new material on a date after a target set to today, contradicting
the signed distance and the SDD's rule that a song target must not generate an
unbounded continuation afterwards.  This guard keeps the repaired brief
explicit about that boundary so a future implementer cannot recreate the
contradictory test expectation.
"""

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r15-weekly-scheduler.md"


class E07R15SongTargetPhaseBriefTest(unittest.TestCase):
    def test_brief_defines_target_and_post_target_performance_boundary(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        self.assertIn("songTargetDate − scheduledDate <= 0", text)
        self.assertIn("performance fázis", text)
        self.assertIn("csak review jelölt lehet", text)
        self.assertIn("céldátum utáni napon sem", text)


if __name__ == "__main__":
    unittest.main()
