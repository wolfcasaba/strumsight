"""E99-R17 §4 — a GENERATED_PATHS halmaz két cellájának őre.

A `tools/round-slots.py` `GENERATED_PATHS` halmaz feloldja a mechanikus
ARB-ütközést: a `lib/l10n/app_en.arb` és `lib/l10n/app_hu.arb` aggregátumok
NEM ütközési felületek — a `tool/gen_l10n_segments.dart` újraírja őket, és a
`tool/ci/check_l10n_parity.dart` gate a frissességet is méri.

A fragmentumok (`lib/l10n/features/<feature>_<locale>.arb`) viszont TOVÁBBRA
TELJES ÉRTÉKŰ ütközési felületek maradnak: két kör ugyanarra a feature-re nem
futhat párhuzamosan, mert a feature-ön belüli kulcs-hozzáfűzés NEM regenerálható.

FONTOS: a `paths_conflict` nyers útvonalakat hasonlít össze — az
`effective_paths` hívja le a GENERATED_PATHS szűrést a brief-betöltés során.
A tesztek ezért a `load_paths` és `effective_paths` köré épülnek, nem a
`paths_conflict` közvetlen hívására.
"""

import importlib.util
import tempfile
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


round_slots = _load("round_slots", "tools/round-slots.py")


class GeneratedPathsExclusionTest(unittest.TestCase):
    """A `lib/l10n/app_<locale>.arb` aggregátumok NEM ütköznek — §4 cella 5."""

    def test_aggregates_are_removed_from_effective_paths(self) -> None:
        paths = round_slots.effective_paths(
            ("lib/l10n/app_en.arb", "lib/l10n/app_hu.arb")
        )
        self.assertEqual(paths, frozenset())

    def test_generated_paths_constant_contains_both_locales(self) -> None:
        self.assertIn("lib/l10n/app_en.arb", round_slots.GENERATED_PATHS)
        self.assertIn("lib/l10n/app_hu.arb", round_slots.GENERATED_PATHS)

    def test_two_briefs_only_touching_generated_aggregates_do_not_conflict(self) -> None:
        """§4 5. cella: két brief, mindkettő `lib/l10n/app_en.arb` → NINCS ütközés.

        A GENERATED_PATHS szűrés az `effective_paths`-ban fut — a
        `paths_conflict` már a szűrt halmazokon dolgozik.

        Ha a GENERATED_PATHS halmazt véletlenül kiszedné valaki, ez az eset
        PIROSRA váltana — a falszifikációs cella a D4-et védi.
        """
        # A brief-ből jövő allowed_paths MINDkét oldalon tartalmazza az
        # aggregátumot; az effective_paths szűri ki.
        left = round_slots.effective_paths(
            ("lib/l10n/app_en.arb", "lib/l10n/features/tuner_en.arb")
        )
        right = round_slots.effective_paths(("lib/l10n/app_en.arb",))
        self.assertEqual(round_slots.paths_conflict(left, right), [])


class FeatureFragmentIsFullConflictTest(unittest.TestCase):
    """A feature-fragmentumok TOVÁBBRA IS TELJES ütközési felületek — §4 cella 6."""

    def test_two_briefs_on_same_feature_fragment_conflict(self) -> None:
        """§4 6. cella: két brief, mindkettő `lib/l10n/features/tuner_en.arb`
        → ÜTKÖZÉS (fragmentum, nem generált)."""
        left = frozenset({"lib/l10n/features/tuner_en.arb"})
        right = frozenset({"lib/l10n/features/tuner_en.arb"})
        self.assertTrue(round_slots.paths_conflict(left, right))


class EffectivePathsIntegrationTest(unittest.TestCase):
    """Az `effective_paths` hívja le a GENERATED_PATHS szűrést."""

    def test_serialization_and_generation_are_independent_exclusions(self) -> None:
        """A SERIALIZED_PATHS és a GENERATED_PATHS külön-külön szűr — ha
        bármelyik halmaz módosul, a másik nem változik."""
        paths = round_slots.effective_paths(
            (
                "HANDOFF.md",
                "lib/l10n/app_en.arb",
                "lib/features/foo/foo.dart",
                "lib/l10n/features/tuner_en.arb",
            )
        )
        self.assertEqual(
            paths,
            frozenset({"lib/features/foo/foo.dart", "lib/l10n/features/tuner_en.arb"}),
        )

    def test_actual_brief_loads_do_not_expose_generated_paths(self) -> None:
        """A GENERATED_PATHS valós használata: a round-slots egy briefből
        olvas, és a `load_paths` már a szűrt halmazzal tér vissza. A
        tényleges E99-R17 brief `allowed_paths` listáján ott van az
        aggregátum — ez a teszt bizonyítja, hogy a `load_paths` levágja."""
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "docs" / "rounds").mkdir(parents=True)
            brief = repo / "docs" / "rounds" / "e99-r17-fixture.md"
            brief.write_text(
                """# E99-R17 — fixture

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/l10n/features/tuner_en.arb",
]
gate_tests = [
  "test/tooling/_placeholder_test.dart",
]
native_gate = false
```
""",
                encoding="utf-8",
            )
            paths = round_slots.load_paths(repo, brief)
            self.assertNotIn("lib/l10n/app_en.arb", paths)
            self.assertNotIn("lib/l10n/app_hu.arb", paths)
            self.assertIn("lib/l10n/features/tuner_en.arb", paths)


if __name__ == "__main__":
    unittest.main()