"""E15-R09 / H5 önjavító kör (ADR 0112, 2026-09-03) — a H5-holtpont őre.

MÉRT HELYZET. A `docs/execution/pipeline-orchestrator-prompt.md` H5 sora
(„a CI kétszer piros ezen a körön") nem mondta ki, mi történik a számlálóval,
miután egy önjavító kör a pirosak MÉRT gyökérokát javította és merge-elte.
Az E15-R09 ág két piros CI-futással (33707997183, 33711465885) áll, a
`round-resume-probe` pedig helyesen a MEGLÉVŐ ágon folytatandó javító körre
irányítja a folytatást — ha ez a folytatás a heal ELŐTTI két pirosra
hivatkozva azonnal újra H5-öt jelent, a kör soha nem fejezhető be:

    halt → önjavítás (a gyökérok javítva) → folytatás → azonnali halt → …

vagyis pont az a holtpont, aminek a megszüntetésére az ADR 0112 létezik.

A kikötés a MÉRCÉBŐL SEMMIT nem enged el: minden gate, a teljes CI-suite és a
Router CI zöldje a merge SHA-n változatlanul kötelező. Kizárólag a
piros-számláló kezdőértékéről szól. Ez a teszt azt köti ki, hogy a kikötés a
promptban BENNE MARADJON — enélkül a következő H5-önjavítás ugyanebbe a
holtpontba fut.
"""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROMPT = ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md"


class H5CounterResetTest(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT.read_text(encoding="utf-8")

    def test_h5_row_still_exists(self):
        """A kikötés nem helyettesíti a H5-öt — a megállási ok marad."""
        self.assertIn("| **H5** | a **CI kétszer piros** ezen a körön |", self.prompt)

    def test_selfheal_resets_the_red_ci_counter(self):
        self.assertIn(
            "piros-CI számláló egy merge-elt önjavító kör után NULLÁRÓL indul",
            self.prompt,
        )

    def test_the_reset_does_not_relax_the_green_gate(self):
        h5_note_start = self.prompt.index(
            "piros-CI számláló egy merge-elt önjavító kör után NULLÁRÓL indul"
        )
        note = self.prompt[h5_note_start : h5_note_start + 1200]
        self.assertIn("zöld kapu változatlan", note)
        self.assertIn("Router CI", note)


if __name__ == "__main__":
    unittest.main()
