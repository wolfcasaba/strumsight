"""ADR-számozás őre.

MÉRT ütközés (2026-08-05): az autonóm lánc E04-R11 köre és egy párhuzamos
governance-munka **ugyanazt a 0139-es sorszámot** foglalta le, mert mindkettő
külön nézte meg a „legmagasabb ADR" értéket, órákkal egymás után. Mindkét
változat átment a saját CI-ján és a saját review-ján — az ütközés csak akkor
derült ki, amikor a második merge után valaki ránézett a könyvtárra.

Ez a hibaosztály nem emberi figyelmetlenség, hanem hiányzó gépi ellenőrzés:
két, egyenként helyes diff összege hibás. A repóban több ágens dolgozik
egyszerre (AGENTS.md §15.4), ezért a sorszám-egyediséget kapunak kell mérnie.
"""

import re
import unittest
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADR_DIR = ROOT / "docs" / "adr"
NAME = re.compile(r"^(\d{4})-[a-z0-9-]+\.md$")


def adr_files():
    return sorted(path for path in ADR_DIR.iterdir() if path.is_file() and path.suffix == ".md")


class AdrNumberingTest(unittest.TestCase):
    def test_every_adr_filename_follows_the_convention(self) -> None:
        for path in adr_files():
            with self.subTest(adr=path.name):
                self.assertRegex(path.name, NAME, "várt alak: NNNN-kebab-case-cim.md")

    def test_adr_numbers_are_unique(self) -> None:
        by_number = defaultdict(list)
        for path in adr_files():
            match = NAME.match(path.name)
            if match:
                by_number[match.group(1)].append(path.name)

        duplicates = {number: names for number, names in by_number.items() if len(names) > 1}

        self.assertEqual(
            duplicates,
            {},
            "ütköző ADR-sorszám(ok) — két párhuzamos kör ugyanazt foglalta le; "
            "a KÉSŐBB merge-elt kapja a következő szabad számot",
        )


if __name__ == "__main__":
    unittest.main()
