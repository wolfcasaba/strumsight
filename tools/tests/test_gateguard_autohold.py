"""A gate-érintő kör HOLD-ja lánc-szintű megállás helyett (ADR 0321).

MÉRT gyökérok (2026-08-19, E99-R17): a `H-GATEGUARD` az ADR 0112 egyetlen
emberi határa — az önjavítás helyesen nem nyúl hozzá —, a `.pipeline/HALTED`
jelzés viszont GLOBÁLIS. Egyetlen gate-érintő kör így háromszor (05:31, 09:56,
10:38) állította meg a sor MIND a 37 nyitott körét, köztük a tőle független
E07/E08 termék-munkát. A brief `allowed_paths` listáján ott volt a védett
`tool/ci/check_l10n_parity.dart`, tehát a kör MÁR A DISPATCH ELŐTT eldőlt.

Három őr, három hibaosztályra:

1. a kör-session H-GATEGUARD haltja a KÖRT teszi hold-ra és a lánc megy tovább;
2. az ŐRSZEM haltja (`gateguard_origin=selfheal`) továbbra is a LÁNCOT állítja
   meg — ott a mércét gyengítő commit már a main-en állhat;
3. a dispatch előtti pre-flight a védett listát MAGÁBÓL AZ ŐRBŐL olvassa, tehát
   a két lista nem tud szétcsúszni.
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "tools" / "round-pipeline.sh"
SCAN = ROOT / "tools" / "gateguard-scan.py"


def _load(module_name: str, relative: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


gateguard_scan = _load("gateguard_scan", "tools/gateguard-scan.py")


class GateguardScanTest(unittest.TestCase):
    def test_the_protected_list_is_imported_from_the_guard_not_copied(self) -> None:
        """Két igazság = drift. A lista forrása maga az őr."""
        source = SCAN.read_text(encoding="utf-8")
        self.assertNotIn('"tools/round-gate.sh",', source)
        globs = gateguard_scan.protected_globs()
        self.assertIn("tools/round-gate.sh", globs)
        self.assertIn("tool/ci/*", globs)

    def test_the_measured_e99_r17_path_is_flagged(self) -> None:
        globs = gateguard_scan.protected_globs()
        hits = gateguard_scan.conflicts(["tool/ci/check_l10n_parity.dart"], globs)
        self.assertEqual(len(hits), 1)

    def test_a_parent_directory_of_a_protected_glob_is_flagged(self) -> None:
        """`tools/ai_router` ⊃ `tools/ai_router/*` — a kör a védettet is írná."""
        globs = gateguard_scan.protected_globs()
        self.assertTrue(gateguard_scan.conflicts(["tools/ai_router"], globs))
        self.assertTrue(gateguard_scan.conflicts([".github/workflows/router-ci.yml"], globs))

    def test_an_ordinary_round_path_is_not_flagged(self) -> None:
        """Hamis pozitív = leszoktat az olvasásáról (brief-lint tanulság)."""
        globs = gateguard_scan.protected_globs()
        for path in (
            "lib/features/practice/domain/session.dart",
            "test/features/practice/session_test.dart",
            "tools/round-slots.py",
            "docs/rounds/e07-r26-outcome-ingestion-and-revision.md",
        ):
            with self.subTest(path=path):
                self.assertEqual(gateguard_scan.conflicts([path], globs), [])


class GateguardHoldTest(unittest.TestCase):
    """A driver halt-ága, izolált állapotkönyvtárral és sor-fájllal."""

    def run_driver(self, state: Path, queue: Path, **extra) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        env.update(
            PIPELINE_STATE_DIR=str(state),
            PIPELINE_QUEUE_FILE=str(queue),
            PIPELINE_NO_LAUNCH="1",
            **extra,
        )
        return subprocess.run(
            ["bash", str(PIPELINE)], env=env, text=True, capture_output=True, check=False
        )

    def write_queue(self, queue: Path, status: str = "pending") -> None:
        queue.write_text(
            "E09-R01\tdocs/rounds/e09-r01.md\tminimax\tnincs\t" + status + "\n"
            "E09-R02\tdocs/rounds/e09-r02.md\tcodex\tnincs\tpending\n",
            encoding="utf-8",
        )

    def test_a_round_level_gateguard_halt_holds_the_round_and_frees_the_chain(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir()
            queue = Path(directory) / "queue.tsv"
            self.write_queue(queue)
            (state / "HALTED").write_text(
                "round=E09-R01\nhalt=H-GATEGUARD\n"
                "summary=a D2 a védett tool/ci/check_l10n_parity.dart-ot módosítaná\n"
            )

            result = self.run_driver(state, queue)

            self.assertFalse((state / "HALTED").exists(), result.stderr)
            self.assertIn("H-GATEGUARD → HOLD", result.stderr)
            self.assertIn("E09-R01\tdocs/rounds/e09-r01.md\tminimax\tnincs\thold", queue.read_text())
            # A többi kör érintetlen: a hold KÖR-szintű, nem sor-szintű.
            self.assertIn("E09-R02\tdocs/rounds/e09-r02.md\tcodex\tnincs\tpending", queue.read_text())
            self.assertTrue((state / "gateguard-holds.tsv").exists())
            archives = list(state.glob("gateguard-hold-E09-R01-*.txt"))
            self.assertEqual(len(archives), 1)
            self.assertIn("resolution=queue-hold", archives[0].read_text())

    def test_the_sentinel_halt_still_stops_the_whole_chain(self) -> None:
        """`gateguard_origin=selfheal` = a mérce MÁR sérülhetett a main-en."""
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir()
            queue = Path(directory) / "queue.tsv"
            self.write_queue(queue)
            (state / "HALTED").write_text(
                "round=E09-R01\nhalt=H-GATEGUARD\ngateguard_origin=selfheal\n"
                "summary=az önjavítás a MÉRCÉHEZ nyúlt\n"
            )

            result = self.run_driver(state, queue)

            self.assertEqual(result.returncode, 3)
            self.assertTrue((state / "HALTED").exists())
            self.assertIn("E09-R01\tdocs/rounds/e09-r01.md\tminimax\tnincs\tpending", queue.read_text())

    def test_the_sentinel_marks_its_own_halt_machine_readably(self) -> None:
        """A megkülönböztetés nem szövegértelmezés: az őrszem MEZŐT ír."""
        driver = PIPELINE.read_text(encoding="utf-8")
        sentinel = driver.split("summary=az önjavítás a MÉRCÉHEZ nyúlt")[0]
        self.assertIn('echo "gateguard_origin=selfheal"', sentinel)

    def test_the_autohold_can_be_switched_off(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir()
            queue = Path(directory) / "queue.tsv"
            self.write_queue(queue)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H-GATEGUARD\nsummary=teszt\n")

            result = self.run_driver(state, queue, PIPELINE_GATEGUARD_AUTOHOLD="0")

            self.assertEqual(result.returncode, 3)
            self.assertTrue((state / "HALTED").exists())

    def test_a_halt_of_another_class_is_untouched(self) -> None:
        """Falszifikáció: a hold NEM nyelheti el a normál haltokat."""
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir()
            queue = Path(directory) / "queue.tsv"
            self.write_queue(queue)
            (state / "HALTED").write_text("round=E09-R01\nhalt=H6\nsummary=teszt halt\n")

            result = self.run_driver(state, queue, PIPELINE_SELFHEAL="0")

            self.assertEqual(result.returncode, 3)
            self.assertTrue((state / "HALTED").exists())
            self.assertIn("E09-R01\tdocs/rounds/e09-r01.md\tminimax\tnincs\tpending", queue.read_text())

    def test_a_round_that_is_no_longer_pending_is_not_silently_held(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            state.mkdir()
            queue = Path(directory) / "queue.tsv"
            self.write_queue(queue, status="running")
            (state / "HALTED").write_text("round=E09-R01\nhalt=H-GATEGUARD\nsummary=teszt\n")

            result = self.run_driver(state, queue)

            self.assertEqual(result.returncode, 3)
            self.assertTrue((state / "HALTED").exists())


class GateguardPreflightTest(unittest.TestCase):
    def test_the_driver_scans_the_brief_before_dispatch(self) -> None:
        driver = PIPELINE.read_text(encoding="utf-8")
        self.assertIn("tools/gateguard-scan.py", driver)
        preflight = driver.split("--- 4.1 MÉRCE-őr pre-flight")[1].split("# --- ")[0]
        self.assertIn("queue_hold_round", preflight)
        # A pre-flight a kör-KIVÁLASZTÁS után, de a kör-session INDÍTÁSA előtt
        # fut — a mérce a DISPATCH hívása (az utolsó előfordulás), nem a
        # függvény definíciója.
        self.assertLess(
            driver.index("MÉRCE-őr pre-flight"),
            driver.rindex('run_orchestrator_session "pipeline-$round"'),
        )
        self.assertLess(driver.index("A következő kör kiválasztása"), driver.index("MÉRCE-őr pre-flight"))

    def test_every_open_queue_brief_is_scanned_by_the_same_tool(self) -> None:
        """A sor jelenlegi állapota: minden ütköző kör 'hold'-on áll."""
        result = subprocess.run(
            [sys.executable, str(SCAN), "--all", "--format", "json"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        reports = json.loads(result.stdout)["reports"]
        flagged = [report for report in reports if report["conflicts"]]
        self.assertTrue(
            all(report["status"] == "hold" for report in flagged),
            f"gate-érintő kör NEM hold-on: {[r['round'] for r in flagged if r['status'] != 'hold']}",
        )


if __name__ == "__main__":
    unittest.main()
