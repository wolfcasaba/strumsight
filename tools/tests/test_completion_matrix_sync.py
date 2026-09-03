"""E15-R09 / H5 önjavító kör (ADR 0112, 2026-09-03) — regressziós őr.

MÉRT GYÖKÉROK. A `docs/sdd/program-completion-report.md` §3 matrixának négy
szám-oszlopa kézzel karbantartott volt, miközben a
`test/tooling/program_completion_test.dart` `A1` cellája SZIGORÚ egyenlőséget
mér a ÉLŐ `docs/execution/pipeline-queue.tsv` ellen. Minden `pending → done`
queue-billentés elavulttá tette a matrixot, és mivel a kör-driver nem indít
kört piros `main` fölé, a drift nem csak egy tesztet vitt pirosra: MEGÁLLÍTOTTA
a láncot.

MÉRVE ÉLESBEN: az E12-R36 riport merge-e utáni ELSŐ queue-flip (E15-R08,
`e9691f74`) pirosra vitte a main Full Gate-jét (run 33704424852) —
    `— (E15): reports done=8, queue measures done=9`
    `— (E15): reports pending=6, queue measures pending=5`
— és a lánc 02:25-től 03:54-ig (89 perc, 18 firing) egyetlen kört sem indított.

A mérce NEM lazult: az `A1` egyenlősége változatlan. Ami megszűnt, az a kézi
bookkeeping — a `tools/sync-completion-matrix.py` a queue-ból származtatja a
számokat, és a driver merge-ága ugyanabban a commitban futtatja, ahol a
queue-sort `done`-ra billenti.

A fixtúrák a VALÓDI, mért adatot használják (a fenti E15-sor a drift előtti
riportból és a mai queue-ból), nem kitalált példát.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "sync-completion-matrix.py"
DRIVER = ROOT / "tools" / "round-pipeline.sh"
REAL_QUEUE = ROOT / "docs" / "execution" / "pipeline-queue.tsv"
REAL_REPORT = ROOT / "docs" / "sdd" / "program-completion-report.md"


def _load_module():
    spec = importlib.util.spec_from_file_location("sync_completion_matrix", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sync = _load_module()


# A drift pontos alakja, ahogy a piros CI-futás mérte: a riport E15-sora a
# `done=8 | pending=6` állapotban ragadt, miközben az E15-R08 sora `done`-ra
# billent.
DRIFTED_REPORT = """# Fixture report

## 3. Completion matrix

| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---|---|---|---|---|---|
| Ch1 | Bevezetés | — | 0 | 0 | 0 | 0 | nincs queue-sor | — |
| Ch13 | UI/UX Design System | E13 | 2 | 0 | 0 | 0 | queue-szinten lezárva | — |
| — | Ch15 UI-migráció | E15 | 8 | 6 | 0 | 0 | nyitva (pending: R08–R13 hátravan) | — |

## 4. Utána
"""

# 9 done + 5 pending — a mai, mért E15 queue-állapot alakja.
QUEUE = "\n".join(
    ["# fejléc-komment", "E13-R01\tdocs/rounds/a.md\tcodex\t0001\tdone"]
    + ["E13-R02\tdocs/rounds/b.md\tcodex\t0002\tdone"]
    + [f"E15-R0{n}\tdocs/rounds/e15-r0{n}.md\tsonnet-impl\t0100\tdone" for n in range(1, 9)]
    + ["E15-R14\tdocs/rounds/e15-r14.md\tsonnet-impl\t0101\tdone"]
    + [f"E15-R{n:02d}\tdocs/rounds/e15-r{n:02d}.md\tsonnet-impl\t0102\tpending" for n in range(9, 14)]
)


class CompletionMatrixSyncTest(unittest.TestCase):
    def _fixture(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name)
        queue = base / "pipeline-queue.tsv"
        report = base / "program-completion-report.md"
        queue.write_text(QUEUE, encoding="utf-8")
        report.write_text(DRIFTED_REPORT, encoding="utf-8")
        return queue, report

    def _run(self, mode, queue, report):
        return subprocess.run(
            [sys.executable, str(SCRIPT), mode, "--queue", str(queue), "--report", str(report)],
            capture_output=True,
            text=True,
        )

    def test_check_reports_the_measured_drift_and_fails(self):
        queue, report = self._fixture()
        result = self._run("--check", queue, report)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("reports done=8, queue measures done=9", result.stdout)
        self.assertIn("reports pending=6, queue measures pending=5", result.stdout)
        # A --check SOHA nem ír: a drift kimutatása nem javítás.
        self.assertEqual(report.read_text(encoding="utf-8"), DRIFTED_REPORT)

    def test_write_syncs_only_the_count_cells(self):
        queue, report = self._fixture()
        self.assertEqual(self._run("--write", queue, report).returncode, 0)
        written = report.read_text(encoding="utf-8")
        self.assertIn("| E15 | 9 | 5 | 0 | 0 |", written)
        # A próza-oszlop és a nem-drifting sorok érintetlenek maradnak.
        self.assertIn("nyitva (pending: R08–R13 hátravan)", written)
        self.assertIn("| Ch13 | UI/UX Design System | E13 | 2 | 0 | 0 | 0 |", written)
        self.assertIn("| Ch1 | Bevezetés | — | 0 | 0 | 0 | 0 |", written)
        # Idempotens: a második futás már nem talál driftet.
        self.assertEqual(self._run("--check", queue, report).returncode, 0)

    def test_lane_without_queue_rows_is_left_alone(self):
        """A `—` előtagú sor (Ch1) nem mérhető a queue ellen — az A1 is kihagyja."""
        queue, report = self._fixture()
        self._run("--write", queue, report)
        self.assertIn("| Ch1 | Bevezetés | — | 0 | 0 | 0 | 0 |", report.read_text(encoding="utf-8"))

    def test_queue_parser_matches_the_dart_a1_measurement(self):
        counts = sync.parse_queue_counts(QUEUE)
        self.assertEqual(counts["E15"], {"done": 9, "pending": 5})
        self.assertEqual(counts["E13"], {"done": 2})

    def test_the_real_tree_is_in_sync(self):
        """A main-en NEM maradhat drift — pontosan ez állította meg a láncot."""
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--check"],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_driver_syncs_the_matrix_in_the_queue_flip_commit(self):
        """A driver merge-ága a sor-billentéssel EGY commitban szinkronizál."""
        source = DRIVER.read_text(encoding="utf-8")
        self.assertIn("sync-completion-matrix.py", source)
        flip = source.index('sed -i "s|^\\($round\\t.*\\t\\)pending$|\\1done|"')
        commit = source.index("chore(pipeline): $round done — fail-safe", flip)
        self.assertIn("sync-completion-matrix.py", source[flip:commit])
        self.assertIn("completion_report_file", source[flip:commit])


if __name__ == "__main__":
    unittest.main()
