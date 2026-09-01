"""Regression guard for the E15-R07 self-heal (ADR 0112, halt H3, 2026-09-01).

MÉRT GYÖKÉROK. Az `E15-R07` (Practice Generator bekötése + migrálása) az
implementer `stopped` jelzésével állt meg (`.pipeline/HALTED`, `halt=H3`,
`halted_at=2026-09-01T09:46:43+00:00`). A STOP mérten indokolt volt; az
önjavító kör FÜGGETLENÜL reprodukálta a három mérést (`main @ 1544e6bd`):

    $ grep -rln "Provider<\\|NotifierProvider\\|ChangeNotifierProvider" \\
          lib/features/practice_generator
    (üres)                              # NULLA Riverpod-provider a feature alatt

    $ grep -rn "implements PracticeEvidenceRepository" lib/
    lib/features/practice_generator/domain/repository/
      practice_evidence_repository.dart:107:    implements ...
    # EGY találat, és az az `InMemoryPracticeEvidenceRepository` TESZT-FAKE
    # (doc-comment: „never forgets") — a `PlanPrivacyScreen` törlés/export
    # use case-e mögé kötve HAMIS consent-felület lenne.

    $ sed -n '96,99p' lib/features/practice_generator/presentation/screens/
          plan_setup_screen.dart
    # a step-4 „Befejezés" gomb KIZÁRÓLAG `controller.next()`-et hív:
    # nincs `onComplete`, nem indít generálást, nem navigál.

Ebből az `E15-R07` F1 fázisa („route + flag + belépési pont") NEM
route-méretű: a `PlanPrivacyScreen` `deleteUseCase`/`exportUseCase`-e
`PracticeEvidenceRepository`-t kér, a `PlanPreviewScreen` KÉSZ
`AdaptivePracticePlan`-t + `GenerationPlanActivation`-t, a
`PlanChangeReviewScreen` egy `PlanRevisionProposal`-t — egyik sem áll elő új
`data/` + `presentation/providers/` kód nélkül. Azt viszont a brief SAJÁT §0 /
§3 STOP-mondata tiltja: *„a képernyők a meglévő providereikből élnek; ha nem,
az önálló kör."*

A brief tehát ÖNMAGÁVAL volt ellentmondásban: bármely implementer, bármely
motoron, újra `stopped`-ot ad — a halt determinisztikusan visszatér. A javítás
NEM a STOP-mondat gyengítése (az valódi védelem), hanem a hiányzó kompozíciós
réteg önálló körbe emelése (`E15-R14`) és az `E15-R07` mögé sorolása.

EZ AZ ŐR azt a sorrendet pinneli, ami nélkül a halt visszatér. A VALÓDI,
commitolt sor-fájlt és a VALÓDI briefeket hajtja át pontosan azon a két
függvényen, amit a driver is futtat (`round-slots.declared_prerequisites` és
`round-slots.unmet_prerequisites`), tehát a regresszió mindkét irányban itt
bukik meg először:

  * ha az `E15-R14` sora az `E15-R07` sora ALÁ csúszik, vagy kikerül a sorból,
    az `E15-R07` újra admittálhatóvá válik a kompozíciós réteg nélkül;
  * ha az `E15-R07` §0.0.B `Előfeltétel` szava eltűnik, a szöveges (nem
    sor-sorrend alapú) blokkolás is elvész;
  * ha az `E15-R14` `allowed_paths`-ából kikerül a két kulcsfájl, a kör nem
    tudná szállítani azt, amiért létrejött;
  * ha az `E15-R07` listája MAGÁHOZ veszi ugyanezeket, a STOP-mondat üres
    betűvé válik és a két kör ugyanarra a fájlra ír (`paths_conflict`).
"""

from __future__ import annotations

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


round_slots = _load("round_slots", "tools/round-slots.py")

BLOCKED_ROUND = "E15-R07"
PREREQUISITE_ROUND = "E15-R14"
BLOCKED_BRIEF = "docs/rounds/e15-r07-practice-generator-migration.md"
PREREQUISITE_BRIEF = "docs/rounds/e15-r14-practice-generator-composition-layer.md"

# A STOP mérésében nevesített két hiány — ezeket a kompozíciós kör szállítja.
COMPOSITION_PATHS = (
    "lib/features/practice_generator/data/local/local_practice_evidence_repository.dart",
    "lib/features/practice_generator/presentation/providers/practice_generator_providers.dart",
)


def _rows():
    return round_slots.queue_rows(ROOT)


def _row(round_id: str):
    for row in _rows():
        if row[0] == round_id:
            return row
    return None


def _index(round_id: str) -> int:
    for position, row in enumerate(_rows()):
        if row[0] == round_id:
            return position
    return -1


class CompositionRoundIsQueuedTest(unittest.TestCase):
    """Az `E15-R14` létezik, a sorban van, és a briefje elemezhető."""

    def test_the_prerequisite_brief_exists_and_parses(self):
        path = ROOT / PREREQUISITE_BRIEF
        self.assertTrue(
            path.is_file(),
            f"a kompozíciós kör briefje hiányzik: {PREREQUISITE_BRIEF} — enélkül "
            "az E15-R07 F1-e ugyanabba a mért zsákutcába fut (H3, 2026-09-01)",
        )
        paths = round_slots.load_paths(ROOT, PREREQUISITE_BRIEF)
        self.assertTrue(paths, "az E15-R14 ai-router blokkja üres allowed_paths-t ad")

    def test_the_prerequisite_row_is_in_the_queue(self):
        row = _row(PREREQUISITE_ROUND)
        self.assertIsNotNone(row, f"nincs {PREREQUISITE_ROUND} sor a pipeline-queue.tsv-ben")
        self.assertEqual(row[1], PREREQUISITE_BRIEF)


class PrerequisiteOrderTest(unittest.TestCase):
    """A sor-sorrend ÉS a brief szava egyaránt blokkolja az E15-R07-et."""

    def test_the_prerequisite_row_precedes_the_blocked_round(self):
        prerequisite = _index(PREREQUISITE_ROUND)
        blocked = _index(BLOCKED_ROUND)
        self.assertGreaterEqual(prerequisite, 0, f"nincs {PREREQUISITE_ROUND} sor")
        self.assertGreaterEqual(blocked, 0, f"nincs {BLOCKED_ROUND} sor")
        self.assertLess(
            prerequisite,
            blocked,
            f"a {PREREQUISITE_ROUND} sorának a {BLOCKED_ROUND} sora FÖLÖTT kell "
            "állnia: az unmet_prerequisites az epicen belül SOR-SORRENDBEN "
            "blokkol (round-slots.py:137-141)",
        )

    def test_the_blocked_brief_declares_the_prerequisite_in_words(self):
        declared = round_slots.declared_prerequisites(ROOT, BLOCKED_BRIEF)
        self.assertIn(
            PREREQUISITE_ROUND,
            declared,
            f"a {BLOCKED_ROUND} briefjének 'Előfeltétel' sora nem nevezi meg a "
            f"{PREREQUISITE_ROUND}-et — a szöveges blokkolás elveszett",
        )

    def test_the_driver_would_not_admit_the_blocked_round(self):
        """A VALÓDI driver-függvény, az E15-R14-et `pending`-nek véve.

        A `pending`-re kényszerítés szándékos: az őr akkor is a sorrendet
        méri, amikor az E15-R14 már `done` — a kérdés mindig az, hogy a
        blokkolás MŰKÖDNE-e, nem az, hogy éppen aktív-e.
        """
        rows = [
            (row[0], row[1], row[2], row[3], "pending" if row[0] == PREREQUISITE_ROUND else row[4])
            for row in _rows()
        ]
        blocking = round_slots.unmet_prerequisites(ROOT, BLOCKED_ROUND, BLOCKED_BRIEF, rows)
        self.assertIn(
            PREREQUISITE_ROUND,
            blocking,
            f"a driver admittálná a {BLOCKED_ROUND}-et a kompozíciós réteg nélkül — "
            "pontosan ez a H3 halt (2026-09-01) visszatérése",
        )


class CompositionScopeTest(unittest.TestCase):
    """A két kulcsfájl a kompozíciós körben van, és NEM az E15-R07-ben."""

    def test_the_composition_round_owns_the_measured_gaps(self):
        paths = round_slots.load_paths(ROOT, PREREQUISITE_BRIEF)
        for path in COMPOSITION_PATHS:
            self.assertIn(
                path,
                paths,
                f"a {PREREQUISITE_ROUND} nem engedi a {path} fájlt — ezért jött létre",
            )

    def test_the_blocked_round_still_excludes_them(self):
        paths = round_slots.load_paths(ROOT, BLOCKED_BRIEF)
        for path in COMPOSITION_PATHS:
            self.assertNotIn(
                path,
                paths,
                f"a {BLOCKED_ROUND} MAGÁHOZ vette a {path} fájlt — a STOP-mondat "
                "üres betűvé vált, és a két kör ugyanarra a fájlra írna",
            )

    def test_the_two_rounds_do_not_collide(self):
        left = round_slots.effective_paths(tuple(round_slots.load_paths(ROOT, PREREQUISITE_BRIEF)))
        right = round_slots.effective_paths(tuple(round_slots.load_paths(ROOT, BLOCKED_BRIEF)))
        self.assertEqual(
            round_slots.paths_conflict(left, right),
            [],
            "az E15-R14 és az E15-R07 engedélyezett fájllistája ütközik",
        )


class StopClauseIsIntactTest(unittest.TestCase):
    """A javítás NEM gyengítheti a mércét: a STOP-mondat MARAD.

    Az önjavító kör jogosultsága a brief revíziójára szól, nem a védelem
    kikapcsolására (ADR 0112 §3). Ha valaki a halt „megoldásaként" kiveszi a
    STOP-mondatot az E15-R07-ből, az implementer legközelebb csendben ír
    `data/`-réteget egy adatvédelmi felület mögé — ez az őr azt fogja meg.
    """

    def test_the_blocked_brief_keeps_its_stop_protocol(self):
        text = (ROOT / BLOCKED_BRIEF).read_text(encoding="utf-8")
        self.assertIn("STOP-protokoll", text)
        self.assertIn(
            "képernyők a meglévő providereikből élnek; ha nem, az önálló kör",
            text,
            "az E15-R07 STOP-mondata eltűnt — a halt gyökéroka így nem javítva, "
            "hanem elrejtve lenne",
        )

    def test_the_composition_round_forbids_route_and_flag_work(self):
        text = (ROOT / PREREQUISITE_BRIEF).read_text(encoding="utf-8")
        self.assertIn("STOP-protokoll", text)
        for forbidden in ("app_router.dart", "practiceGeneratorEnabled"):
            self.assertIn(
                forbidden,
                text,
                f"az E15-R14 nem mondja ki, hogy a {forbidden} NEM az ő hatásköre — "
                "a fázissorrend (kompozíció → bekötés) enélkül elmosódik",
            )
        self.assertNotIn(
            "lib/app/routing/app_router.dart",
            round_slots.load_paths(ROOT, PREREQUISITE_BRIEF),
            "az E15-R14 engedi a routert — az a bekötés (E15-R07 / F1) hatásköre",
        )


if __name__ == "__main__":
    unittest.main()
