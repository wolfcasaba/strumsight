"""Kör-granularitás (E99-R16 D1) mérése.

A `tools/round-metrics.py --granularity` alparancs a merge-elt körök
kör-idejét a briefmérettel (allowed_paths + gate_tests darabszáma) párosítja,
és méret-sávonkénti (1–4, 5–8, 9+) mediánt + lineáris regressziót ad. A
teszt kizárólag lokális adatból dolgozik (rögzített napló + BriefMetadata
fixture), hálózat nélkül.

Falszifikációs cella (kötelező, brief §4): ha a kiugró-szűrést kivesszük,
a 2636p (43.9 órás) fixture-minta a regresszió meredekségét a tűrésen
kívülre mozdítja → a teszt PIROS.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-metrics.py"


# A fix kör-ideje a 2636p kiugró MELLÉ a regresszió szépen látható legyen:
# 4 pont: (1 fájl, 30p), (3 fájl, 50p), (5 fájl, 70p), (8 fájl, 110p) —
# a meredekség ~12p/fájl, a tengelymetszet ~18p. A kiugró hozzáadása
# (size=10, duration=2636p) a meredekséget ~+250p/fájl-ra rúgja, ami a
# TOLERANCE-ot (30p) messze meghaladja.
LINEAR_FIT_BASE = """\
2026-08-01T10:00:00+00:00  orchestrátor-session indul (E07-R01)
2026-08-01T10:30:00+00:00  E07-R01 MERGE-ELVE — done
2026-08-01T11:00:00+00:00  orchestrátor-session indul (E07-R02)
2026-08-01T11:50:00+00:00  E07-R02 MERGE-ELVE — done
2026-08-01T12:00:00+00:00  orchestrátor-session indul (E07-R03)
2026-08-01T13:10:00+00:00  E07-R03 MERGE-ELVE — done
2026-08-01T13:30:00+00:00  orchestrátor-session indul (E07-R04)
2026-08-01T15:20:00+00:00  E07-R04 MERGE-ELVE — done
"""


LINEAR_FIT_WITH_OUTLIER = LINEAR_FIT_BASE + """\
2026-08-02T08:00:00+00:00  orchestrátor-session indul (E07-R05)
2026-08-04T03:56:00+00:00  E07-R05 MERGE-ELVE — done
"""


def _brief_text(allowed_paths: list[str], gate_tests: list[str] | None = None) -> str:
    """Egy mini brief, ami átmegy a brief-metadata parserén. A `gate_tests`
    NEM lehet üres tömb a parser szerint — minimum egy elemet várunk, de a
    granularitás-számítás a méretbe a gate-eket is beleszámolja, tehát
    egyetlen `test/...` útvonal a default."""
    gate = gate_tests or ["test/x/gate_test.dart"]
    paths = "\n".join(f'"{p}",' for p in allowed_paths)
    gates = "\n".join(f'"{g}",' for g in gate)
    return (
        "# E##-R## fixture\n\n"
        "```ai-router\n"
        "schema_version = 1\n"
        "risk = \"normal\"\n"
        f"allowed_paths = [\n{paths}\n]\n"
        f"gate_tests = [\n{gates}\n]\n"
        "native_gate = false\n"
        "```\n"
    )


def _build_fixture(
    *,
    sizes: list[tuple[str, int, int | None]],
    log_text: str,
) -> tuple[Path, Path]:
    """Egy temp könyvtár: brief-ek + queue + lánc-napló.

    `sizes`: [(round_id, allowed_paths_count, duration_minutes_or_None_for_outlier), ...]
    A `path_count` a brief-fájlon FELÜLI munkafájlok száma — a teljes
    `allowed_paths` = 1 brief + `path_count` munkafájl.
    """
    tmp = Path(tempfile.mkdtemp(prefix="granularity-fixture-"))
    docs = tmp / "docs" / "rounds"
    docs.mkdir(parents=True, exist_ok=True)
    pipeline = tmp / "docs" / "execution"
    pipeline.mkdir(parents=True, exist_ok=True)
    queue_path = pipeline / "pipeline-queue.tsv"
    log_path = tmp / "chain.log"
    log_path.write_text(log_text, encoding="utf-8")
    queue_lines = []
    for round_id, path_count, _duration in sizes:
        brief_rel = f"docs/rounds/{round_id.lower()}.md"
        brief_path = docs / f"{round_id.lower()}.md"
        allowed = [brief_rel] + [f"lib/features/x/y_{i}.dart" for i in range(path_count)]
        brief_path.write_text(_brief_text(allowed), encoding="utf-8")
        queue_lines.append(f"{round_id}\t{brief_rel}\tcodex\tnincs\tpending")
    queue_path.write_text("\n".join(queue_lines) + "\n", encoding="utf-8")
    return queue_path, log_path


def run_granularity(
    queue_path: Path, log_path: Path, extra: list[str] | None = None
) -> tuple[int, str, str]:
    """A round-metrics.py --granularity hívása a megadott fixture-ön.

    A `--repo` a queue_path parent.parent.parent értékére mutat — a
    `load_briefs_for_queue` a brief-eket a `repo / <brief_rel>` útvonalon
    keresi, és a fixture a temp könyvtárban van."""
    repo_root = queue_path.parent.parent.parent
    result = subprocess.run(
        [
            sys.executable, str(SCRIPT),
            "--chain-log", str(log_path),
            "--queue", str(queue_path),
            "--repo", str(repo_root),
            "--granularity",
            *(extra or []),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, result.stdout, result.stderr


class RoundMetricsGranularityTest(unittest.TestCase):
    """A granularitás-elemzés kulcsmutatói: méret-sáv + regresszió + kiugró-szűrés."""

    def setUp(self) -> None:
        self._tmp = Path(tempfile.mkdtemp(prefix="granularity-"))

    def tearDown(self) -> None:
        shutil.rmtree(self._tmp, ignore_errors=True)

    def test_size_bands_bucketed(self) -> None:
        """A 1–4, 5–8, 9+ sávokba a minták a fájlszám alapján kerülnek — kontrollált
        `briefs` dict-tel (3 kör, mind más-más sávba).

        A `path_count` a brief-fájlon FELÜLI munkafájlok száma; a teljes
        `size = 1 (brief) + path_count + 1 (default gate_test)` — ezért
        a sáv-számítás az alábbi N értékekre:
          N=2  → size=4  → sáv: 1-4
          N=5  → size=7  → sáv: 5-8
          N=11 → size=13 → sáv: 9+
        """
        sizes = [
            ("E07-R01", 2, 30),
            ("E07-R02", 5, 50),
            ("E07-R03", 11, 70),
        ]
        # A lineáris fit-hez duration percekben: E07-R03 70p, E07-R04 110p.
        log_text = (
            "2026-08-01T10:00:00+00:00  orchestrátor-session indul (E07-R01)\n"
            "2026-08-01T10:30:00+00:00  E07-R01 MERGE-ELVE — done\n"
            "2026-08-01T11:00:00+00:00  orchestrátor-session indul (E07-R02)\n"
            "2026-08-01T11:50:00+00:00  E07-R02 MERGE-ELVE — done\n"
            "2026-08-01T12:00:00+00:00  orchestrátor-session indul (E07-R03)\n"
            "2026-08-01T13:10:00+00:00  E07-R03 MERGE-ELVE — done\n"
        )
        queue_path, log_path = _build_fixture(sizes=sizes, log_text=log_text)
        queue_path, log_path = self._copy_to_tmp(queue_path, log_path)
        exit_code, stdout, stderr = run_granularity(queue_path, log_path, ["--format", "json"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        bands = {b["size_min"]: b["n"] for b in payload["bands"]}
        self.assertEqual(bands.get(1, 0), 1)  # E07-R01
        self.assertEqual(bands.get(5, 0), 1)  # E07-R02
        self.assertEqual(bands.get(9, 0), 1)  # E07-R03

    def test_regression_requires_brief_pairs(self) -> None:
        """Brief-párosítás nélkül a regresszió n=0 — a parancs kilép, de a kimenet
        konzisztens (üres samples + n=0)."""
        queue_path, log_path = _build_fixture(sizes=[], log_text=LINEAR_FIT_BASE)
        queue_path, log_path = self._copy_to_tmp(queue_path, log_path)
        exit_code, stdout, stderr = run_granularity(queue_path, log_path, ["--format", "json"])
        # Üres queue esetén a samples lista üres, és a tool kilép.
        self.assertEqual(exit_code, 2)
        self.assertIn("nincs", stderr)

    def test_outlier_filter_keeps_regression_clean(self) -> None:
        """Falszifikációs cella (brief §4): a kiugró-szűrés VÉD — ha kivennénk,
        a 2636p minta a meredekséget a tűrésen kívülre rúgná."""
        sizes = [
            ("E07-R01", 2, 30),  # size=2 (brief + 1)
            ("E07-R02", 4, 50),  # size=4
            ("E07-R03", 6, 70),  # size=6
            ("E07-R04", 9, 110),  # size=9
            ("E07-R05", 11, 2636),  # size=11, duration 2636p (outlier)
        ]
        queue_path, log_path = _build_fixture(sizes=sizes, log_text=LINEAR_FIT_WITH_OUTLIER)
        queue_path, log_path = self._copy_to_tmp(queue_path, log_path)
        exit_code, stdout, stderr = run_granularity(queue_path, log_path, ["--format", "json"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["outliers_dropped"], 1)
        self.assertEqual(payload["regression"]["n"], 4)
        slope = payload["regression"]["slope_minutes_per_file"]
        self.assertIsNotNone(slope)
        self.assertGreater(slope, 0)
        # Ha a kiugró-szűrés kimaradna, a meredekség ~+260p lenne. A
        # TOLERANCE (30p) a felső korlátja annak, amit a 4-pontos tiszta
        # mintán várunk — ezzel a teszt megfogja a kiugró-szűrés
        # kimaradását.
        self.assertLess(slope, 30.0)

    def _copy_to_tmp(self, queue_path: Path, log_path: Path) -> tuple[Path, Path]:
        """A `_build_fixture` a saját tempjébe ír — átmásoljuk az EGÉSZ
        könyvtárat (brief-ekkel együtt) a teszt tempjébe, hogy a tearDown
        biztosan takarítson, ÉS a `repo`/`queue`/`briefs` konzisztens legyen."""
        fixture_root = queue_path.parent.parent.parent  # az eredeti fixture gyökere
        new_root = self._tmp / "fixture"
        shutil.copytree(fixture_root, new_root)
        return new_root / "docs" / "execution" / "pipeline-queue.tsv", new_root / "chain.log"

    def test_render_includes_slope_and_intercept(self) -> None:
        """A szöveges kimenet tartalmazza a meredekséget és a tengelymetszetet —
        a CLI-n keresztül, kontrollált fixture-ön (3 tiszta kör, hogy a
        regresszió a várható meredekséget adja)."""
        sizes = [
            ("E07-R01", 1, 30),  # size=3 (brief+1working+1gate)
            ("E07-R02", 4, 50),  # size=6
            ("E07-R03", 9, 110),  # size=11
        ]
        log_text = (
            "2026-08-01T10:00:00+00:00  orchestrátor-session indul (E07-R01)\n"
            "2026-08-01T10:30:00+00:00  E07-R01 MERGE-ELVE — done\n"
            "2026-08-01T11:00:00+00:00  orchestrátor-session indul (E07-R02)\n"
            "2026-08-01T11:50:00+00:00  E07-R02 MERGE-ELVE — done\n"
            "2026-08-01T12:00:00+00:00  orchestrátor-session indul (E07-R03)\n"
            "2026-08-01T13:50:00+00:00  E07-R03 MERGE-ELVE — done\n"
        )
        queue_path, log_path = _build_fixture(sizes=sizes, log_text=log_text)
        queue_path, log_path = self._copy_to_tmp(queue_path, log_path)
        exit_code, stdout, stderr = run_granularity(queue_path, log_path)
        self.assertEqual(exit_code, 0, stderr)
        self.assertIn("meredekség", stdout)
        self.assertIn("tengelymetszet", stdout)


if __name__ == "__main__":
    unittest.main()