"""H8 self-heal (E99-R18, 2026-08-20) — a két generált-útvonal mechanizmus
egyszerre él a `tools/round-slots.py`-ban, és egyik sem nyeli el a másikat.

Gyökérok: az E99-R17 (`main`) az EXACT-SET `GENERATED_PATHS` frozensetet, a
jelen kör (E99-R18, D4) a GLOB-alapú `GENERATED_PATH_PATTERNS`/
`is_generated_path` mechanizmust vezette be — mindkettő ugyanazt a két
kódrészt (`tools/round-slots.py` konstans-blokk + `effective_paths` szűrő-
predikátum) módosította, ami a `main` szinkron rebase/merge-jén tartalmi
konfliktust adott. A két meglévő teszt-csomag
(`tools/tests/test_round_slots_generated_paths.py`,
`tools/tests/test_round_slots_generated_barrels.py`) kizárólag a SAJÁT
oldalát méri — egyik sem bizonyítja, hogy egy merge-feloldás nem nyeli el a
másik mechanizmust. Ez a fájl a hiányzó, KOMBINÁLT cellát méri.
"""

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _load(module_name: str, relative: str):
    """A kötőjeles fájlnevű CLI-k betöltése modulként (nem importálható névvel)."""
    spec = importlib.util.spec_from_file_location(module_name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


round_slots = _load("round_slots_coexist", "tools/round-slots.py")


class BothGeneratedPathMechanismsCoexistTest(unittest.TestCase):
    def test_exact_set_and_glob_pattern_both_filter_in_one_call(self) -> None:
        """Egyetlen `effective_paths` hívás mindkét kizárási okot méri."""
        paths = round_slots.effective_paths(
            (
                "lib/l10n/app_en.arb",  # E99-R17: GENERATED_PATHS (exact)
                "lib/features/x/public.dart",  # E99-R18: GENERATED_PATH_PATTERNS (glob)
                "lib/features/x/public/domain.dart",  # egyik mechanizmus sem fedi — marad
            )
        )
        self.assertEqual(paths, frozenset({"lib/features/x/public/domain.dart"}))

    def test_neither_mechanism_shadows_the_other_constant(self) -> None:
        """A GENERATED_PATHS és a GENERATED_PATH_PATTERNS egyszerre, és a
        várt tartalommal létezik — ha egy jövőbeli szerkesztés visszaírná a
        régi, egymást kizáró HEAD/main ágat, ez a cella piros lenne."""
        self.assertIn("lib/l10n/app_en.arb", round_slots.GENERATED_PATHS)
        self.assertIn("lib/l10n/app_hu.arb", round_slots.GENERATED_PATHS)
        self.assertEqual(
            round_slots.GENERATED_PATH_PATTERNS,
            ("lib/features/*/public.dart",),
        )

    def test_two_briefs_one_per_mechanism_do_not_conflict(self) -> None:
        """Két párhuzamos kör, az egyik csak ARB-t, a másik csak public.dart-ot
        érint — egyik mechanizmus szűrése sem terjed át a másikéra tévesen."""
        left = round_slots.effective_paths(("lib/l10n/app_en.arb",))
        right = round_slots.effective_paths(("lib/features/x/public.dart",))
        self.assertEqual(round_slots.paths_conflict(left, right), [])


if __name__ == "__main__":
    unittest.main()
