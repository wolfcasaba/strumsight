"""Őrtesztek a `router-ci` Python-suite futásidejének MÉRT hibaosztályára.

MIÉRT VAN EZ A FÁJL (E14-R13 / H5 önjavító kör, ADR 0112, 2026-09-05):

A `.github/workflows/router-ci.yml` job-plafonja `timeout-minutes: 10`, és a
suite beérte: a `08c17390` merge SHA-n a futás **10m 06s**-nél `cancelled` lett
(run 33973215326), a pytest saját bemondása az előző, még végigfutó mérésen
`947 passed … in 582.56s`. Egy KÉSZ és APPROVED kör így nem tudott zöld Router
CI-t felmutatni a merge SHA-n → merge tilos, a lánc megállt
(`.pipeline/halt-detail-E14-R13.md`).

A plafon emelése a self-heal ABSZOLÚT tiltott zónája (ADR 0112 §3, gépi őr:
`heal_pr_gate_violation` a `tools/round-pipeline.sh`-ban), ezért a javítás a
suite MÉRT költség-tételeit szüntette meg. Ez a fájl azokat a tételeket köti le
determinisztikusan — óra nélkül, hogy a mérce ne legyen flaky —, hogy ugyanaz a
lassulás ne csendben kússzon vissza a következő körig.

Mérési alap (`main @ 9632a96d`, `python3 -m pytest tools/tests -q
--durations=40`, 949 passed / 1 skipped, 850,85 s ezen a boxon):

| tétel | mért ár | ez a fájl mit köt le |
|---|---|---|
| `predecessor_paths()` négyzetes brief-elemzése | 75 149 `load_brief` hívás 413 briefre; a 77,5 s-os korpusz-menetből 63,1 s | `BriefLintCorpusCostTest` |
| a `mm-round.sh` SIGTERM→SIGKILL türelme a hamis binárisú cellákban | 5 s × ~20 cella | `ProductionDefaultsAreUnchangedTest` |
| az `attempt_selfheal` halt-RAG lekérdezése | 27,0 s / hívás (24,9 s CPU) × 9 cella | `ProductionDefaultsAreUnchangedTest` |

A két gyorsítás KAPCSOLÓVAL megy (`MM_KILL_GRACE_SECONDS`,
`PIPELINE_HEAL_RAG`), és az ÉLES alapértelmezés változatlan — a
`ProductionDefaultsAreUnchangedTest` pontosan ezt méri, hogy a suite
gyorsítása ne váljon észrevétlenül termék-viselkedés-változtatássá.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location(
        "brief_lint_suite_cost", TOOLS / "brief-lint.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


# A szelet a sor VÉGÉRŐL jön: ott a legtöbb az előd, tehát ott a legnagyobb a
# négyzetes hatás. 25 elég ahhoz, hogy a régi alak nagyságrendekkel lépje túl a
# korlátot (mérve: 25 × ~390 előd ≈ 9 700 elemzés), és elég kevés ahhoz, hogy a
# javított alak másodpercek alatt fusson.
CORPUS_SLICE = 25


class BriefLintCorpusCostTest(unittest.TestCase):
    """Egy brief-fájlt EGY korpusz-menet legfeljebb egyszer elemez.

    Ez az invariáns, nem a fali óra: a `predecessor_paths()` a sorban korábbi
    körök briefjeit járja be, tehát N brief lintelése a naiv alakban
    N × (N/2) elemzést jelent. A javítás fájl-identitáshoz kötött
    gyorsítótár, ezért a menet elemzés-száma a KÜLÖNBÖZŐ fájlok számához
    tapad.
    """

    def _slice(self) -> list[Path]:
        rows = brief_lint.queue_rows(ROOT)
        briefs = [ROOT / brief for _round, brief, _status in rows]
        return [brief for brief in briefs if brief.is_file()][-CORPUS_SLICE:]

    def test_a_corpus_pass_parses_each_brief_file_at_most_once(self) -> None:
        briefs = self._slice()
        self.assertGreaterEqual(
            len(briefs), 10, "a sor-fájlból nem jött elég létező brief a méréshez"
        )

        seen: list[str] = []
        original = brief_lint.load_brief

        def counting_load_brief(path: Path):
            seen.append(str(path))
            return original(path)

        brief_lint.load_brief = counting_load_brief
        # `getattr`, hogy a cella a gyorsítótár NÉLKÜLI alakon is a MÉRÉSÉN
        # bukjon (a négyzetes elemzés-számon), ne szimbólum-hiányon.
        getattr(brief_lint, "_BRIEF_CACHE", {}).clear()
        try:
            for brief in briefs:
                try:
                    brief_lint.lint_text(
                        brief.read_text(encoding="utf-8"), path=brief, repo=ROOT
                    )
                except Exception:  # noqa: BLE001 — elemezhetetlen brief nem ennek a mércéje
                    continue
        finally:
            brief_lint.load_brief = original

        distinct = len(set(seen))
        # A felső korlát: minden KÜLÖNBÖZŐ fájl egyszer, plusz legfeljebb egy
        # közvetlen elemzés lintelt briefenként (a `lint_text` a saját
        # briefjét a gyorsítótár megkerülésével olvassa).
        self.assertLessEqual(
            len(seen),
            distinct + len(briefs),
            "a korpusz-menet ismételten elemzi ugyanazt a brief-fájlt — ez a "
            f"négyzetes alak (mérve a javítás előtt: 75 149 elemzés 413 briefre). "
            f"Most: {len(seen)} elemzés, {distinct} különböző fájl, "
            f"{len(briefs)} lintelt brief.",
        )


class BriefLintCacheFreshnessTest(unittest.TestCase):
    """A gyorsítótár a fájl IDENTITÁSÁHOZ tapad, nem az útvonalhoz.

    Enélkül a gyorsítás csendben helyességi hibává válna: egy menet közben
    átírt brief a régi tartalmával mérődne. A cella ezt inverz próbával
    mutatja meg — ugyanaz az útvonal, más tartalom, MÁS eredmény.
    """

    BRIEF = (
        "# {title}\n\n"
        "```ai-router\n"
        "schema_version = 1\n"
        'risk = "normal"\n'
        'allowed_paths = ["{allowed}"]\n'
        'gate_tests = ["test/{gate}"]\n'
        "native_gate = true\n"
        "```\n"
    )

    def test_rewriting_a_brief_in_place_is_seen_by_the_next_load(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            path = Path(directory_name) / "e99-r01-fixture.md"

            path.write_text(
                self.BRIEF.format(title="első", allowed="lib/a.dart", gate="a_test.dart"),
                encoding="utf-8",
            )
            first = brief_lint._cached_load_brief(path).metadata.allowed_paths

            path.write_text(
                self.BRIEF.format(
                    title="második", allowed="lib/bb.dart", gate="bb_test.dart"
                ),
                encoding="utf-8",
            )
            second = brief_lint._cached_load_brief(path).metadata.allowed_paths

            self.assertEqual(("lib/a.dart",), first)
            self.assertEqual(
                ("lib/bb.dart",),
                second,
                "a gyorsítótár elavult tartalmat adott vissza — a kulcsnak a fájl "
                "identitását (mtime_ns + méret) kell tartalmaznia",
            )

    def test_the_cached_loader_still_raises_for_an_unparseable_brief(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            path = Path(directory_name) / "e99-r02-fixture.md"
            path.write_text("nincs benne ai-router blokk\n", encoding="utf-8")
            with self.assertRaises(brief_lint.BriefMetadataError):
                brief_lint._cached_load_brief(path)
            # A kivétel is gyorsítótárazódik — másodszorra is ugyanaz jön.
            with self.assertRaises(brief_lint.BriefMetadataError):
                brief_lint._cached_load_brief(path)


class ProductionDefaultsAreUnchangedTest(unittest.TestCase):
    """A suite gyorsítása NEM termék-viselkedés-változtatás.

    Mindkét gyorsító kapcsoló alapértelmezése az ÉLES viselkedés; csak a mérő
    cellák kapcsolják ki azt, amit nem ők mérnek (ugyanaz a minta, mint a
    korábbi `PIPELINE_STATUS_CHECK=0`). Ha valaki az alapértelmezést mozdítja
    el, az már a terméket érinti, és itt bukik.
    """

    def test_the_wrapper_keeps_a_five_second_sigterm_grace_by_default(self) -> None:
        wrapper = (TOOLS / "mm-round.sh").read_text(encoding="utf-8")
        self.assertIn("kill_grace_seconds=${MM_KILL_GRACE_SECONDS:-5}", wrapper)
        self.assertIn('sleep "$kill_grace_seconds"', wrapper)
        self.assertNotIn(
            "\n    sleep 5\n",
            wrapper,
            "maradt bedrótozott 5 másodperces sleep a burkolóban",
        )

    def test_the_driver_runs_the_halt_retrieval_by_default(self) -> None:
        driver = (ROOT / "tools" / "round-pipeline.sh").read_text(encoding="utf-8")
        self.assertIn('[ "${PIPELINE_HEAL_RAG:-1}" = "1" ]', driver)
        # A visszakeresés MAGA (ADR 0312) változatlanul a self-heal prompt része.
        self.assertIn("Korábbi, hasonló esetek a tudás-indexből", driver)
        self.assertIn("knowledge-rag.mjs", driver)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
