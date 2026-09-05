"""Regression guard for E17-R01 / H3 (ADR 0112 önjavító kör, 2026-09-05).

MÉRT GYÖKÉROK. Az `E17-R01` (Onboarding First-Win állomás bekötése) a saját
pre-flightján állt meg (`.pipeline/HALTED`, `halt=H3`,
`halted_at=2026-09-05T19:05:09+00:00`, dispatch NEM történt). A brief §2
mért állítása — „a képernyő adatforrása MÁR LÉTEZIK:
`onboardingFirstWinConfidenceProvider`" — a bekötés szempontjából félrevezető
volt. Az önjavító kör függetlenül újramérte (`main @ 0b2feb43`)::

    $ sed -n '20,23p' lib/features/onboarding/first_win_providers.dart
    final onboardingFirstWinEngineFactoryProvider =
        Provider<OnboardingFirstWinEngine Function()>(
          (_) => FakeOnboardingFirstWinEngine.new,     # a SZÁLLÍTOTT default
        );

    $ grep -rn "\\.emit(" lib/features/onboarding/ --include=*.dart
    (üres)      # a fake motor kizárólag teszt/preview hookból emittál

    $ grep -rn "onboardingFirstWinEngineFactoryProvider.overrideWith" lib/
    (üres)      # nincs produkciós felülírás a kompozícióban

A provider tehát létezik, de a szállított kompozícióban egy fake motor hajtja,
ami a produkcióban SOHA nem bocsát ki értéket. A bekötés így egy örökké
`onboardFirstWinListening` állapotban álló képernyőt tett volna a MÁR MŰKÖDŐ
first-win út (`OnboardingScreen._completeFirstWin` → scored
`LearnScreen(lesson: Lessons.firstWin)`) elé — és az A1/A4 cella közben ZÖLD
lett volna, mert a képernyő tényleg a valós providert olvassa és tényleg
elérhetővé válik. Pontosan az [L606](../../docs/LESSONS.md#l606) (E16-R02 /
H3) hibaosztálya: *az üres forrás és a zöld kapu megkülönböztethetetlen*.

A javítás NEM cella-gyengítés és NEM a bekötés elhalasztása: a hiányzó
FORRÁS került a körbe (produkciós `OnboardingFirstWinEngine` a
`strumEngineProvider` fölött, a default gyár átkötése, és a forrás-hiba
őszinte ága a Stage-en), az A8–A10 cellákkal együtt.

EZ AZ ŐR a revideált scope-ot pinneli. A landolás UTÁN is áll: kizárólag a
brief listáit/celláit méri (a kör terméke ezeken nem mozdít), nem a
munkájának HIÁNYÁT ([L612](../../docs/LESSONS.md#l612)).
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


ROOT = Path(__file__).resolve().parents[2]
BRIEF_PATH = "docs/rounds/e17-r01-onboarding-first-win-stage-wiring.md"
BRIEF = ROOT / BRIEF_PATH
QUEUE = ROOT / "docs" / "execution" / "pipeline-queue.tsv"
ROUND = "E17-R01"

# A halt §3 táblázatában mért hiány: a produkciós konfidencia-forrás és az
# őszinte hiba-ág. A Stage a `strumEngineProvider`-t a `live/public.dart`
# felületén át éri el (precedens: practice_observation_gateway_provider.dart:31),
# ezért a `lib/core/audio/**` NEM kell a listára.
FIRST_WIN_SOURCE_PATHS = {
    "lib/features/onboarding/first_win_engine.dart",
    "lib/features/onboarding/first_win_providers.dart",
    "lib/features/onboarding/screens/first_win_stage_screen.dart",
}
PRODUCTION_ENGINE_TEST = (
    "test/features/onboarding/first_win_production_engine_test.dart"
)
# A halt által elemzett, MÁR MŰKÖDŐ út és a forrás-szemantika őrei — ezek a
# revízió után is a tiltás oldalán állnak.
PRESERVED_CELLS = ("| A1 |", "| A2 |", "| A3 |", "| A4 |", "| A5 |", "| A6 |", "| A7 |")
NEW_CELLS = ("| A8 |", "| A9 |", "| A10 |")
ADR_IN_BRIEF = re.compile(r"\*\*Előre kiosztott ADR:\*\*\s*`ADR (\d{4})`")


def _queue_rows() -> list[list[str]]:
    rows = []
    for line in QUEUE.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        rows.append(line.split("\t"))
    return rows


class FirstWinSourceScopeTest(unittest.TestCase):
    """A kör megkapta a hiányzó FORRÁST — enélkül a halt determinisztikus."""

    def test_the_brief_allows_the_production_confidence_source(self) -> None:
        allowed = set(load_brief_metadata(BRIEF).allowed_paths)

        self.assertEqual(
            FIRST_WIN_SOURCE_PATHS - allowed,
            set(),
            "az E17-R01 nem tudná átkötni a first-win konfidencia-forrást a "
            "fake motorról a valósra — a bekötés így egy örökké „Listening…” "
            "képernyőt tenne a működő first-win út elé (H3, 2026-09-05)",
        )

    def test_the_production_engine_has_its_own_gate_test(self) -> None:
        metadata = load_brief_metadata(BRIEF)
        text = BRIEF.read_text(encoding="utf-8")

        self.assertIn(
            PRODUCTION_ENGINE_TEST,
            set(metadata.allowed_paths),
            "az új forrásnak saját tesztet kell kapnia, különben a "
            "produkciós motor mérés nélkül szállna",
        )
        self.assertIn(
            PRODUCTION_ENGINE_TEST,
            set(metadata.gate_tests),
            "a produkciós motor tesztje nincs a kör kapujában — a kapun "
            "kívüli forrás mérés nélküli forrás",
        )
        self.assertIn(
            PRODUCTION_ENGINE_TEST,
            text,
            "a §7 round-gate parancssora nem futtatja a produkciós motor "
            "tesztjét (S12: a mérce a PARANCS, nem a metaadat)",
        )


class FailureModeHasItsOwnCellTest(unittest.TestCase):
    """A halt hibamódja saját, gépi cellát kapott."""

    def test_the_fake_engine_failure_mode_is_a_named_cell(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        for cell in NEW_CELLS:
            self.assertIn(
                cell,
                text,
                f"hiányzik a {cell.strip('| ')} cella — a halt hibamódjait "
                "(fake forrás, motor-életciklus, forrás-hiba) mérni kell",
            )
        self.assertIn(
            "FakeOnboardingFirstWinEngine",
            text,
            "az A8 cellának NÉVVEL kell tiltania a szállított fake motort — "
            "egy általános valós-forrás mondat nem gépi mérce",
        )

    def test_the_falsification_probe_covers_the_new_cell(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        probe = text.split("Falszifikációs próba", 1)
        self.assertEqual(
            len(probe),
            2,
            "a §6.1 falszifikációs próba eltűnt a briefből",
        )
        self.assertIn(
            "FakeOnboardingFirstWinEngine",
            probe[1].split("## 7", 1)[0],
            "a §6.1 próbájának vissza kell állítania a fake default gyárat és "
            "meg kell követelnie, hogy az A8 PIROSRA váltson",
        )


class BarIsNotWeakenedTest(unittest.TestCase):
    """Az önjavítás a scope-ot tágítja, a mércét nem gyengíti (ADR 0112 §3)."""

    def test_every_original_cell_survived(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        for cell in PRESERVED_CELLS:
            self.assertIn(
                cell,
                text,
                f"a self-heal elejtette a {cell.strip('| ')} cellát — a forrás "
                "tágítása a javítás, a cellák törlése nem",
            )

    def test_the_threshold_semantics_stay_forbidden(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")

        self.assertIn("STOP-protokoll", text)
        for symbol in ("kFirstWinConfidenceThreshold", "isFirstWinSuccess"):
            self.assertIn(
                symbol,
                text,
                f"a §3 tiltásának NÉVVEL kell védenie a {symbol} őszinteség-"
                "szerződését (ADR 0281 §2): a forrás átkötése engedélyezett, a "
                "siker-küszöb átírása nem",
            )

    def test_the_round_does_not_take_the_audio_core(self) -> None:
        allowed = set(load_brief_metadata(BRIEF).allowed_paths)

        for path in allowed:
            self.assertFalse(
                path.startswith("lib/core/audio/"),
                f"a kör a {path} fájlt is elkérte — a mért feloldás a "
                "`live/public.dart` felületén megy, új `AudioOwner` variáns "
                "és lease-szerződés módosítás nélkül",
            )


class AdrNumberIsFreeTest(unittest.TestCase):
    """A brief 0520-as száma egy MÁS, már megírt ADR-é volt."""

    def test_the_brief_and_the_queue_agree_on_a_number(self) -> None:
        match = ADR_IN_BRIEF.search(BRIEF.read_text(encoding="utf-8"))
        self.assertIsNotNone(match, "a brief fejlécében nincs ADR-szám")
        number = match.group(1)

        self.assertNotEqual(
            number,
            "0520",
            "a 0520 egy MEGÍRT, más körhöz tartozó ADR "
            "(docs/adr/0520-live-uncertainty-reason-...md) — a kör ütköző "
            "sorszámot kapott volna",
        )

        rows = [row for row in _queue_rows() if row and row[0] == ROUND]
        self.assertEqual(len(rows), 1, f"nincs (vagy több) {ROUND} sor a queue-ban")
        self.assertEqual(
            rows[0][3],
            number,
            "a queue ADR-oszlopa és a brief fejléce eltér — a kör indulásakor "
            "megint elavult szám menne a promptba",
        )

    def test_no_other_queued_round_claims_the_same_number(self) -> None:
        match = ADR_IN_BRIEF.search(BRIEF.read_text(encoding="utf-8"))
        assert match is not None
        number = match.group(1)

        collisions = [
            row[0]
            for row in _queue_rows()
            if len(row) >= 4 and row[3] == number and row[0] != ROUND
        ]
        self.assertEqual(
            collisions,
            [],
            f"a(z) {number} sorszámot más kör is elkérte: {collisions} — a "
            "test_adr_numbering.py őre a MERGE után bukna el",
        )


if __name__ == "__main__":
    unittest.main()
