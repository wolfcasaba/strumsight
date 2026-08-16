"""Regression guard for E07-R15/H7 resumed-round upstream synchronization.

The E07-R15 scheduler branch had already committed its implementation when the
H7 self-heal merged a stricter song-target brief contract to ``main``.  The
next orchestrator session resumed the old branch without integrating ``main``;
it consequently re-ran the superseded A5 expectation and halted again.  The
orchestrator prompt is the executable operating contract for that resume, so
it must require a measured upstream integration before any repair or review.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md"


class ResumeUpstreamSynchronizationTest(unittest.TestCase):
    def test_resumed_round_requires_main_integration_before_repair_or_review(self) -> None:
        text = TEMPLATE.read_text(encoding="utf-8")
        section = text.split("## 0.3 Folytatáskori upstream-szinkron", 1)[1]
        section = section.split("\n## ", 1)[0]

        self.assertIn("git -C <kör-munkapéldány> fetch origin main", section)
        self.assertIn(
            "git -C <kör-munkapéldány> merge-base --is-ancestor origin/main HEAD",
            section,
        )
        self.assertIn("git -C <kör-munkapéldány> merge --no-ff origin/main", section)
        self.assertIn("git -C <kör-munkapéldány> push", section)
        self.assertIn("H8", section)
        self.assertIn("review", section.lower())
        self.assertIn("javító", section.lower())


if __name__ == "__main__":
    unittest.main()
