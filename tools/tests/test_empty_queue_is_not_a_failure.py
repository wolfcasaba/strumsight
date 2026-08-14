"""A kiürült kör-sor epic-határ, nem defekt (2026-08-14).

MÉRT eset. Az Epic 6 utolsó köre (`E06-R30`) 2026-08-14T01:04-kor `done`-ra
váltotta az utolsó sort, amivel a `docs/execution/pipeline-queue.tsv` minden
sora `done` lett. Két teszt ezen a ponton `assertTrue`-val bukott:

    test_pipeline_integration.py::test_open_rounds_follow_the_measured_engine_rule
        AssertionError: [] is not true : nincs egyetlen nyitott sor sem — a szabály mérhetetlen
    test_pipeline_throughput.py::test_every_open_round_brief_passes_the_base_gate
        AssertionError: [] is not true : nincs nyitott kör — a kapu mérhetetlen

Ettől a main Router CI-ja pirosra váltott, a `round-pipeline.sh:1584`
main-health kapuja pedig nem indít munkát piros main fölé — **a lánc magára
zárta az ajtót**, és csak emberi észrevétel oldotta fel (6 óra állás).

Ez MÁSODSZOR fordult elő: a `test_pipeline_integration.py` docstringje
rögzíti a 2026-08-05-i, E04-R07 utáni esetet, ahol nyolc körön át volt piros
a Router CI. Akkor a szűrő lett epic-agnosztikus, de az üres-lista assertion
maradt — a hibaosztály fele javítva.

A mérce NEM gyengül: mindkét teszt ugyanúgy végigméri az ÖSSZES nyitott kört.
Csak azt ismerjük el, hogy nulla nyitott körön nincs mit mérni — és a
sérült/üres sor-fájl továbbra is VALÓDI bukás.
"""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTEGRATION = ROOT / "tools" / "tests" / "test_pipeline_integration.py"
THROUGHPUT = ROOT / "tools" / "tests" / "test_pipeline_throughput.py"


def _load(module_name: str, relative: str):
    """A kötőjeles fájlnevű CLI-k betöltése modulként (ugyanaz a minta, mint
    a `test_pipeline_throughput.py:33`-ban)."""
    spec = importlib.util.spec_from_file_location(module_name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load("brief_lint", "tools/brief-lint.py")


def _queue(root: Path, body: str) -> Path:
    target = root / "docs" / "execution" / "pipeline-queue.tsv"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(body, encoding="utf-8")
    return target


class EmptyQueueIsAnEpicBoundaryTest(unittest.TestCase):
    """A viselkedés: a LEGITIM üres sor nulla nyitott kört ad, nem hibát."""

    def test_an_all_done_queue_yields_zero_open_rounds(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            _queue(
                root,
                "# fejléc\n"
                "E06-R29\tdocs/rounds/a.md\tcodex\tnincs\tdone\n"
                "E06-R30\tdocs/rounds/b.md\tcodex\tnincs\tdone\n",
            )
            rows = list(brief_lint.queue_rows(root))
            self.assertTrue(rows, "a sorok kiolvashatók — a fájl ép")
            self.assertEqual(
                [r for r in rows if r[2] != "done"],
                [],
                "minden sor done → nulla nyitott kör, ez az epic-határ",
            )

    def test_a_queue_with_an_open_row_still_has_something_to_measure(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            _queue(
                root,
                "# fejléc\n"
                "E06-R30\tdocs/rounds/b.md\tcodex\tnincs\tdone\n"
                "E99-R09\tdocs/rounds/c.md\tcodex\t0250\tpending\n",
            )
            rows = list(brief_lint.queue_rows(root))
            self.assertEqual([r[0] for r in rows if r[2] != "done"], ["E99-R09"])


class TheTwoGatesSkipInsteadOfFailingTest(unittest.TestCase):
    """A mérce mércéje: a két hívóhely skipel, nem bukik — és a sérült fájlt
    továbbra is VALÓDI hibaként kezeli. Forrás-szintű őr, mert a két teszt a
    VALÓDI repó-gyökeret olvassa, így a viselkedés futásidőben nem injektálható
    (ugyanaz a minta, mint a `MainHealthTest`/`RoundBranchGuardTest`)."""

    def test_the_engine_rule_gate_skips_on_a_legitimately_empty_queue(self) -> None:
        source = INTEGRATION.read_text(encoding="utf-8")
        self.assertIn("self.skipTest(", source, "üres soron skip kell, nem bukás")
        self.assertNotIn(
            'self.assertTrue(open_rounds, "nincs egyetlen nyitott sor sem',
            source,
            "a régi, láncot megállító assertion nem térhet vissza",
        )
        self.assertIn(
            'self.assertTrue(rows,',
            source,
            "a sérült/üres sor-fájl továbbra is VALÓDI bukás",
        )

    def test_the_brief_gate_skips_on_a_legitimately_empty_queue(self) -> None:
        source = THROUGHPUT.read_text(encoding="utf-8")
        self.assertIn("self.skipTest(", source, "üres soron skip kell, nem bukás")
        self.assertNotIn(
            'self.assertTrue(paths, "nincs nyitott kör',
            source,
            "a régi, láncot megállító assertion nem térhet vissza",
        )
        self.assertIn(
            'self.assertTrue(rows,',
            source,
            "a sérült/üres sor-fájl továbbra is VALÓDI bukás",
        )


class TheGatesStillMeasureEveryOpenRoundTest(unittest.TestCase):
    """A skip nem tehet vakká: a JELENLEGI (nem üres) sorral mindkét kapunak
    ténylegesen FUTNIA kell, nem skipelnie."""

    def test_both_gates_run_against_the_live_non_empty_queue(self) -> None:
        live_open = [r for r in brief_lint.queue_rows(ROOT) if r[2] != "done"]
        if not live_open:
            self.skipTest("az éles sor épp üres — ezt a cellát a fenti kettő fedi")
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "pytest",
                "-q",
                "-rs",
                f"{INTEGRATION}::PipelineIntegrationTest::test_open_rounds_follow_the_measured_engine_rule",
                f"{THROUGHPUT}::BriefLintTest::test_every_open_round_brief_passes_the_base_gate",
            ],
            capture_output=True,
            text=True,
            cwd=ROOT,
            timeout=300,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn(
            "skipped",
            result.stdout,
            "nem üres sor mellett egyik kapu sem skipelhet — az vakság lenne",
        )


if __name__ == "__main__":
    unittest.main()
