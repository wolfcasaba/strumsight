"""A kör-állapotfájl KÖR-KULCSOLT (ADR 0272).

MÉRT hiba (2026-08-15, az ELSŐ `PIPELINE_SLOTS=2` firing). A driver a
kör-állapotot egyetlen GLOBÁLIS fájlban tartotta (`$state_dir/round-status`):
törölte dispatch előtt, a session oda írta az eredményt, és onnan olvasta az
`outcome`-ot. Két párhuzamos driver ugyanazt a fájlt használta, ezért:

* az `E14-R01` az `E07-R04` `outcome=merged` sorát olvasta ki;
* `done`-ra íródott a sora, miközben SEMMI nem épült meg belőle
  (0 recognition flag, nincs `docs/eval/recognition-release-guard.md`, nincs PR);
* az értesítése szó szerint a MÁSIK kör összefoglalója volt.

A slot-VÁLASZTÁS helyes volt: a `tools/round-slots.py check` mérve diszjunktot
adott a két körre. A hiba a kör-ÁLLAPOT megosztásában volt.

Ez a néma hamis-lezárás a legveszélyesebb hibaosztály: nem hibát jelez, hanem
sikert hazudik — ugyanaz, amit a projekt máshol már többször kimondott
(ADR 0251 §2, 0253 §3, 0261 §2, 0268).
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools" / "round-pipeline.sh"
STATUS_CLI = ROOT / "tools" / "pipeline-status.sh"


def _driver(*args: str, state: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(DRIVER), *args],
        capture_output=True,
        text=True,
        env=dict(os.environ, PIPELINE_STATE_DIR=str(state)),
        timeout=60,
    )


class PerRoundStatusPathTest(unittest.TestCase):
    """A két slot NEM láthatja egymás állapotfájlját."""

    def test_two_rounds_resolve_to_different_status_files(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            a = _driver("--status-file-for", "E07-R04", state=state).stdout.strip()
            b = _driver("--status-file-for", "E14-R01", state=state).stdout.strip()
            self.assertTrue(a, "üres útvonal")
            self.assertNotEqual(a, b, "két kör NEM oszthat állapotfájlt — ez volt a hiba")
            self.assertIn("E07-R04", a)
            self.assertIn("E14-R01", b)

    def test_the_path_is_inside_the_injected_state_dir(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            path = _driver("--status-file-for", "E07-R04", state=state).stdout.strip()
            self.assertTrue(
                path.startswith(str(state)),
                f"a kör-állapot az injektált állapotkönyvtárban éljen: {path}",
            )

    def test_the_driver_no_longer_uses_a_bare_global_round_status(self) -> None:
        """A regresszió őre: a dispatch-útvonal nem térhet vissza a globális
        fájlra. A `status_file` a kör kiválasztása UTÁN kör-kulcsolt lesz."""
        source = DRIVER.read_text(encoding="utf-8")
        self.assertIn(
            'status_file=$(round_status_file_for "$round")',
            source,
            "a kör-kulcsolt hozzárendelés nem térhet vissza globálisra",
        )
        self.assertNotIn(
            'rm -f "$state_dir/round-status" "$router_status_file"',
            source,
            "a dispatch nem törölheti a GLOBÁLIS kör-állapotot — az a másik sloté is",
        )


class RouterHaltHandoffUsesTheSamePathTest(unittest.TestCase):
    """A `--mark-halt` oda írjon, ahonnan a driver OLVAS.

    Ha a két oldal elcsúszik, a router halt-átadása némán elveszne: a driver a
    saját (üres) fájlját olvasná, és `H-NOSIGNAL`-t adna a valódi halt helyett.
    """

    def test_mark_halt_writes_the_round_keyed_file_the_driver_reads(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            expected = _driver("--status-file-for", "E14-R01", state=state).stdout.strip()

            result = subprocess.run(
                ["bash", str(STATUS_CLI), "--mark-halt", "H4", "teszt-halt"],
                capture_output=True,
                text=True,
                env=dict(
                    os.environ,
                    PIPELINE_STATE_DIR=str(state),
                    PIPELINE_ROUND="E14-R01",
                ),
                timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(
                Path(expected).exists(),
                f"a --mark-halt nem oda írt, ahonnan a driver olvas: {expected}",
            )
            body = Path(expected).read_text(encoding="utf-8")
            self.assertIn("round=E14-R01", body)
            self.assertIn("halt=H4", body)

    def test_a_second_round_halt_does_not_overwrite_the_first(self) -> None:
        """A két slot halt-átadása nem üthet egymásra."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            for round_id, summary in (("E14-R01", "elso"), ("E07-R05", "masodik")):
                subprocess.run(
                    ["bash", str(STATUS_CLI), "--mark-halt", "H4", summary],
                    capture_output=True,
                    text=True,
                    env=dict(
                        os.environ,
                        PIPELINE_STATE_DIR=str(state),
                        PIPELINE_ROUND=round_id,
                    ),
                    timeout=60,
                    check=True,
                )
            first = Path(_driver("--status-file-for", "E14-R01", state=state).stdout.strip())
            second = Path(_driver("--status-file-for", "E07-R05", state=state).stdout.strip())
            self.assertIn("elso", first.read_text(encoding="utf-8"))
            self.assertIn("masodik", second.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
