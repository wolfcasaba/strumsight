"""Motoronkénti statisztika (E99-R14 D3 / ADR 0307 §1).

A `tools/round-metrics.py --engines` alparancs a `.pipeline/chain.log`
eseményeiből motoronkénti táblát állít elő: `n`, `kiugró` (a 10 órás
küszöb feletti értékek száma), `medián`, `átlag`, `önjavító`. A
számítás kizárólag a chain.log eseményeiből dolgozik (nincs hálózat,
nincs `gh` hívás), így tesztelhető rögzített naplóból.

Falszifikációs cella: ha a kiugró-szűrést kivesszük a forrásból, a
medián-teszt PIROS kell legyen (a 2636p minta elhúzza a mediánt).
"""

import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-metrics.py"


# A 2636 perces (43.9 órás) kiugró a brief §3-ban mért E07-R16. A fixture
# ezt a mintát tartalmazza, hogy a kiugró-szűrés hatása determinisztikus
# legyen: az N=4 minta 3 rövid (27-47p) + 1 hosszú (2636p) kör, így a
# medián SZŰRÉS NÉLKÜL ~668p, SZŰRÉSSEL 27p.
FIXTURE_LOG = """\
2026-08-10T10:00:00+00:00  következő kör: E07-R01 · orchestrátor=claude · implementer=minimax · brief=x · ADR=y
2026-08-10T10:00:01+00:00  orchestrátor-session indul (E07-R01)
2026-08-10T10:30:00+00:00  E07-R01 MERGE-ELVE — done
2026-08-10T11:00:00+00:00  következő kör: E07-R02 · orchestrátor=claude · implementer=minimax · brief=x · ADR=y
2026-08-10T11:00:01+00:00  orchestrátor-session indul (E07-R02)
2026-08-10T11:27:00+00:00  E07-R02 MERGE-ELVE — done
2026-08-10T12:00:00+00:00  következő kör: E07-R03 · orchestrátor=claude · implementer=sonnet-impl · brief=x · ADR=y
2026-08-10T12:00:01+00:00  orchestrátor-session indul (E07-R03)
2026-08-10T12:46:00+00:00  E07-R03 MERGE-ELVE — done
2026-08-10T13:00:00+00:00  következő kör: E07-R04 · orchestrátor=claude · implementer=sonnet-impl · brief=x · ADR=y
2026-08-10T13:00:01+00:00  orchestrátor-session indul (E07-R04)
2026-08-10T13:35:00+00:00  ÖNJAVÍTÓ KÖR indul: E07-R04 / H-NOSIGNAL
2026-08-10T14:00:00+00:00  E07-R04 MERGE-ELVE — done
2026-08-10T15:00:00+00:00  következő kör: E07-R05 · orchestrátor=claude · implementer=minimax · brief=x · ADR=y
2026-08-10T15:00:01+00:00  orchestrátor-session indul (E07-R05)
2026-08-10T15:47:00+00:00  E07-R05 MERGE-ELVE — done
2026-08-10T16:00:00+00:00  következő kör: E07-R06 · orchestrátor=claude · implementer=minimax · brief=x · ADR=y
2026-08-10T16:00:01+00:00  orchestrátor-session indul (E07-R06)
2026-08-11T11:56:00+00:00  E07-R06 MERGE-ELVE — done (outlier: 2636p)
"""


def run_engines(additional: list[str] = None, log_text: str = FIXTURE_LOG) -> tuple[int, str, str]:
    """A round-metrics.py --engines hívása, visszaadja (exit, stdout, stderr)."""
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as handle:
        handle.write(log_text)
        log_path = Path(handle.name)
    try:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--chain-log", str(log_path), "--engines", *(additional or [])],
            capture_output=True, text=True, cwd=ROOT,
        )
        return result.returncode, result.stdout, result.stderr
    finally:
        log_path.unlink(missing_ok=True)


class EnginesSubcommandTest(unittest.TestCase):
    """A `--engines` alparancs determinisztikus kimenete a fixture-ből."""

    def test_engines_returns_deterministic_table(self) -> None:
        """A fixture 4 minimax + 2 sonnet-impl kört tartalmaz, ebből 1 outlier.

        A MINIMAX rúdja: n=4, kiugró=1, a 2636p outlier kimarad.
        A SONNET-IMPLE rúdja: n=2, kiugró=0, 1 önjavító.

        A konkrét medián-értékek a fixture-ből számolódnak:
          minimax: 27p, 30p, 47p + 2636p (outlier) → medián 30p
          sonnet-impl: 46p, 60p → medián 53p
        A táblázat-ellenőrzés a SZŰRT mediánt méri (== 30p), nem a
        szűretlen 668p-t — ez a kiugró-szűrés létének közvetlen bizonyítéka.
        """
        exit_code, stdout, stderr = run_engines()

        self.assertEqual(exit_code, 0, msg=f"stderr: {stderr}")
        self.assertIn("implementer", stdout)
        self.assertIn("minimax", stdout)
        self.assertIn("sonnet-impl", stdout)
        # A 2636p kiugró megjelenik a `kiugró` oszlopban (1).
        self.assertRegex(
            stdout,
            r"minimax\s+4\s+1\s+\S*30p\s+",
            msg=f"a minimax sor mediánja NEM 30p (a szűrt medián): {stdout!r}",
        )
        self.assertRegex(
            stdout,
            r"sonnet-impl\s+2\s+0\s+\S*53p\s+",
            msg=f"a sonnet-impl sor mediánja NEM 53p: {stdout!r}",
        )

    def test_engines_json_has_all_required_fields(self) -> None:
        """Az `--engines --format json` kilistázza a szerződésben ígért mezőket."""
        exit_code, stdout, _ = run_engines(["--format", "json"])

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["outlier_threshold_seconds"], 36000)
        engines = {row["implementer"]: row for row in payload["engines"]}
        self.assertIn("minimax", engines)
        self.assertIn("sonnet-impl", engines)
        self.assertEqual(engines["minimax"]["n"], 4)
        self.assertEqual(engines["minimax"]["outliers_dropped"], 1)
        self.assertEqual(engines["minimax"]["self_heal_rounds"], 0)
        self.assertEqual(engines["sonnet-impl"]["n"], 2)
        self.assertEqual(engines["sonnet-impl"]["self_heal_rounds"], 1)
        # A medián SZŰRT (27p tartományban) — NEM 668p.
        self.assertLess(engines["minimax"]["median_seconds"], 1800, msg="a medián túl magas — a kiugró-szűrés nem működik")

    def test_engines_without_log_is_clean_error(self) -> None:
        """Ha a napló nem tartalmaz egyetlen 'következő kört' sem, a kilépés 2."""
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as handle:
            handle.write("2026-08-10T10:00:00+00:00  no signals here\n")
            log_path = Path(handle.name)
        try:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--chain-log", str(log_path), "--engines"],
                capture_output=True, text=True, cwd=ROOT,
            )
        finally:
            log_path.unlink(missing_ok=True)

        self.assertEqual(result.returncode, 2, msg=f"stderr: {result.stderr}")
        self.assertIn("BEFEJEZETT", result.stderr)

    def test_engines_epic_filter_includes_only_matching_rounds(self) -> None:
        """--epic E07 (pozitív cella): a fixture minden köre E07, a teljes tábla megmarad.

        A fixture 4 minimax + 2 sonnet-impl kört tartalmaz, mind E07-R*. A
        `--epic E07` szűrés ugyanazt a táblát adja, mint a szűrés nélküli
        nézet — az értékek bit-re azonosak. A JSON kimenet `epic` mezője
        `E07`, és a sorok száma nem változik.
        """
        exit_code, stdout, _ = run_engines(["--epic", "E07", "--format", "json"])

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        self.assertEqual(payload["epic"], "E07")
        engines = {row["implementer"]: row for row in payload["engines"]}
        self.assertIn("minimax", engines)
        self.assertIn("sonnet-impl", engines)
        # A fixture-ből a szűrt nézet megegyezik a szűretlennel.
        self.assertEqual(engines["minimax"]["n"], 4)
        self.assertEqual(engines["sonnet-impl"]["n"], 2)

    def test_engines_epic_filter_excludes_other_epics(self) -> None:
        """--epic E99 (negatív cella): a fixture E07-R* köröket tartalmaz, E99-R*-t nem.

        A szűrés MIND a 6 kört kiszűri, a motor-aggregátum üres. A JSON
        `epic` mezője `E99`, a `engines` lista üres, a szöveges tábla
        az üres-napló üzenetet adja.
        """
        # A JSON-t nézzük: a `engines` lista üres, és az `epic` rögzítve van.
        exit_code, stdout, _ = run_engines(["--epic", "E99", "--format", "json"])

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        self.assertEqual(payload["epic"], "E99")
        self.assertEqual(payload["engines"], [], msg=f"a(z) E99 szűrés nem üres: {payload['engines']!r}")

        # A szöveges tábla: explicit üres-üzenet.
        _, table_stdout, _ = run_engines(["--epic", "E99"])
        self.assertIn("nincs motor-hozzárendelhető kör", table_stdout)

    def test_engines_epic_filter_partial_overlap(self) -> None:
        """--epic E07 parciális átfedés: a fixture csak E07 kört tartalmaz, DE a
        motor-aggregátum csak az epiches sorokra épül — egy másik epic hozzáadása
        a fixture-höz az E07 statisztikát NEM változtatná meg.

        Ez a cella az E07 + E99 keverékkel dolgozik: az E99-es köröknek
        NEM szabad megjelenniük az E07-es szűrt nézetben, és fordítva.
        """
        # Készítünk egy másik epicet (E99-R01) a fixture-höz, és ellenőrizzük,
        # hogy a két szűrt nézet DISZJUNKT.
        extended_log = FIXTURE_LOG + (
            "2026-08-12T10:00:00+00:00  következő kör: E99-R01 · orchestrátor=claude · implementer=claude-impl · brief=x · ADR=y\n"
            "2026-08-12T10:00:01+00:00  orchestrátor-session indul (E99-R01)\n"
            "2026-08-12T10:25:00+00:00  E99-R01 MERGE-ELVE — done\n"
        )
        exit_code, stdout, _ = run_engines(["--epic", "E07", "--format", "json"], log_text=extended_log)
        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        engines = {row["implementer"]: row for row in payload["engines"]}
        # Az E99-R01 (claude-impl) NEM jelenik meg az E07 nézetben.
        self.assertNotIn("claude-impl", engines)
        self.assertEqual(engines["minimax"]["n"], 4)

        # A fordított szűrés: csak a claude-impl jelenik meg.
        exit_code, stdout, _ = run_engines(["--epic", "E99", "--format", "json"], log_text=extended_log)
        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        engines = {row["implementer"]: row for row in payload["engines"]}
        self.assertEqual(list(engines.keys()), ["claude-impl"])
        self.assertEqual(engines["claude-impl"]["n"], 1)


class EnginesOutlierFalsificationTest(unittest.TestCase):
    """Falszifikációs cella (brief §4, kötelező).

    M2 javítás: a forrást IZOLÁLT MÁSOLATON módosítjuk. A termelési
    `tools/round-metrics.py` ÉRINTETLEN marad — sem a teszt futása
    alatt, sem párhuzamos futás / processz-halál esetén. A `setUp`
    előkészíti a másolatot, a `tearDown` (vagy `addCleanup`) törli.
    """

    def setUp(self) -> None:
        # M2 javítás: a forrást IZOLÁLT MÁSOLATRA cseréljük — a termelési
        # SCRIPT nem módosul, a teszt a másolaton dolgozik.
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.script_copy = Path(self._temp.name) / "round-metrics.py"
        shutil.copy(SCRIPT, self.script_copy)
        self._original = self.script_copy.read_text(encoding="utf-8")

    def tearDown(self) -> None:
        # M2 javítás: a forrást MINDIG visszaállítjuk (a másolatot) — egy
        # kósza hiba nem hagyhat módosított kódot a lemezen. A teljes
        # temp-könyvtárat amúgy is törli a `setUp` `addCleanup`
        # regisztrációja; ez a visszaállítás a párhuzamos futás
        # védelme, ha a `_temp` cleanup-ja késne.
        self.script_copy.write_text(self._original, encoding="utf-8")

    def _run_engines_with_copy(self, additional: list[str] = None, log_text: str = FIXTURE_LOG) -> tuple[int, str, str]:
        """A MÁSOLT scriptre futtatja a `--engines` parancsot."""
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as handle:
            handle.write(log_text)
            log_path = Path(handle.name)
        try:
            result = subprocess.run(
                [sys.executable, str(self.script_copy), "--chain-log", str(log_path), "--engines", *(additional or [])],
                capture_output=True, text=True, cwd=ROOT,
            )
            return result.returncode, result.stdout, result.stderr
        finally:
            log_path.unlink(missing_ok=True)

    def test_kiugro_szures_kivetelevel_a_median_teszt_piros(self) -> None:
        """A `n < outlier_threshold` szűrő kikapcsolása → a medián kiugró_after.

        M2 javítás: a módosítás a MÁSOLT scriptre fut, a termelési forrás
        nem változik. M3 javítás nincs hatással — a falszifikáció a
        D3 statisztikai kódot célozza, nem a motor-override-ot.
        """
        # A `OUTLIER_THRESHOLD_SECONDS = 10 * 3600` és a szűrő:
        # `filtered = [s for s in samples if s < outlier_threshold]`. A szűrő
        # kikapcsolása: threshold=999h → a 2636p (43.9h) BENT marad.
        modified = self._original.replace(
            "OUTLIER_THRESHOLD_SECONDS = 10 * 3600",
            "OUTLIER_THRESHOLD_SECONDS = 999 * 3600  # E99-R14 falszifikáció: kiugró-szűrés KIKAPCSOLVA",
        )
        self.assertNotEqual(modified, self._original, "a módosítás nem illeszkedett")
        self.script_copy.write_text(modified, encoding="utf-8")

        exit_code, stdout, _ = self._run_engines_with_copy(["--format", "json"])
        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        engines = {row["implementer"]: row for row in payload["engines"]}
        minimax = engines["minimax"]
        # A szűrő KI: a 2636p minta bennmarad → a medián az 1. és 2. elem
        # között (27p és 27p) FÖLÉ kerül. A 4 minta rendezve:
        # 1620, 1620, 2760, 158160 (2636p). A medián a 2. és 3. között:
        # (1620+2760)/2 = 2190p = 36,5p.
        # A szűrő BE: medián = 27p (1620s).
        self.assertGreater(
            minimax["median_seconds"], 1800,
            msg=f"szűrés nélkül a mediánnak 1800s FÖLÖTT kell lennie a 2636p miatt, "
                f"kapott: {minimax['median_seconds']:.0f}s. A teszt NEM őrzi az invariánst.",
        )


if __name__ == "__main__":
    unittest.main()
