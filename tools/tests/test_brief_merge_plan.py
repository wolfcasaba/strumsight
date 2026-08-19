"""Brief-összevonási javaslat (E99-R16 D2) mérése.

A `tools/brief-merge-plan.py` a sor-fájlból JAVASOL brief-párokat a négy
feltétel együttes teljesülésére (azonos epic + szomszédos sorszám; azonos
lib/features|<lib/core| feature-gyökér az allowed_paths többségében;
egyesített allowed_paths ≤ --max-paths; egyik sem native_gate).

A teszt kizárólag lokális adatból dolgozik (rögzített queue + briefek),
hálózat nélkül. A küszöb-mátrix és a falszifikációs cellák a brief §4
szerint kötelezőek.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "brief-merge-plan.py"


def _brief_text(allowed_paths: list[str], gate_tests: list[str] | None = None, native_gate: bool = False) -> str:
    """Mini brief, ami átmegy a brief-metadata parserén. Az `allowed_paths`
    a feature-gyökeret a `lib/features/<x>/...` mintával adja; a `gate_tests`
    nem lehet üres (a parser követelménye)."""
    gate = gate_tests or ["test/x/gate_test.dart"]
    paths = "\n".join(f'"{p}",' for p in allowed_paths)
    gates = "\n".join(f'"{g}",' for g in gate)
    native_str = "true" if native_gate else "false"
    return (
        "# E##-R## fixture\n\n"
        "```ai-router\n"
        "schema_version = 1\n"
        "risk = \"normal\"\n"
        f"allowed_paths = [\n{paths}\n]\n"
        f"gate_tests = [\n{gates}\n]\n"
        f"native_gate = {native_str}\n"
        "```\n"
    )


def _build_queue(
    *,
    rows: list[tuple[str, str, str]],
    briefs: dict[str, tuple[list[str], bool]],
    brief_dir_name: str = "rounds",
) -> tuple[Path, Path]:
    """Queue + briefek egy temp könyvtárban. A `rows` (round, brief_rel, status)
    hármasok listája; a `briefs` a round_id → (allowed_paths, native_gate) leképezés.

    Visszaadja: (queue_path, repo_root). A `repo_root` az a gyökér, amit a
    CLI `--repo`-nak kell kapnia, hogy a briefeket a `repo / <brief_rel>`
    útvonalon megtalálja.
    """
    tmp = Path(tempfile.mkdtemp(prefix="merge-plan-fixture-"))
    docs = tmp / "docs" / brief_dir_name
    docs.mkdir(parents=True, exist_ok=True)
    pipeline = tmp / "docs" / "execution"
    pipeline.mkdir(parents=True, exist_ok=True)
    queue_path = pipeline / "pipeline-queue.tsv"
    queue_lines = []
    for round_id, brief_rel, status in rows:
        brief_path = tmp / brief_rel
        allowed, native_gate = briefs[round_id]
        brief_path.write_text(_brief_text(allowed, native_gate=native_gate), encoding="utf-8")
        queue_lines.append(f"{round_id}\t{brief_rel}\tcodex\tnincs\t{status}")
    queue_path.write_text("\n".join(queue_lines) + "\n", encoding="utf-8")
    return queue_path, tmp


def run_merge_plan(repo_root: Path, extra: list[str] | None = None) -> tuple[int, str, str]:
    """A brief-merge-plan.py hívása a megadott fixture-ön."""
    result = subprocess.run(
        [
            sys.executable, str(SCRIPT),
            "--repo", str(repo_root),
            *(extra or []),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, result.stdout, result.stderr


class BriefMergePlanThresholdTest(unittest.TestCase):
    """A `--max-paths` küszöb hármas cellája (brief §4, mérce-mátrix):

    | egyesített allowed_paths | elvárt                         |
    |--------------------------|-------------------------------|
    | 11                       | a pár JAVASOLT                |
    | 12                       | a pár JAVASOLT (inkluzív)     |
    | 13                       | a pár NEM javasolt, indoklással |
    """

    def setUp(self) -> None:
        self._tmp = Path(tempfile.mkdtemp(prefix="merge-plan-"))

    def tearDown(self) -> None:
        shutil.rmtree(self._tmp, ignore_errors=True)

    def _make_pair(
        self, *, left_files: int, right_files: int, native_gate: bool = False
    ) -> tuple[Path, Path]:
        """Egy szomszédos E07-R01/R02 pár, azonos feature-gyökérrel.

        A `left_files` és `right_files` a brief-FÁJLON FELÜLI munkafájlok
        száma; az egyesített allowed_paths = (1 brief bal + left_files) +
        (1 brief jobb + right_files) - átfedés nélkül.
        """
        rows = [
            ("E07-R01", "docs/rounds/e07-r01.md", "pending"),
            ("E07-R02", "docs/rounds/e07-r02.md", "pending"),
        ]
        briefs = {
            "E07-R01": (
                ["docs/rounds/e07-r01.md"]
                + [f"lib/features/songs/x_{i}.dart" for i in range(left_files)],
                native_gate,
            ),
            "E07-R02": (
                ["docs/rounds/e07-r02.md"]
                + [f"lib/features/songs/y_{i}.dart" for i in range(right_files)],
                native_gate,
            ),
        }
        queue_path, repo_root = _build_queue(rows=rows, briefs=briefs)
        # Átmásoljuk a teszt tempjébe a takarításhoz.
        new_root = self._tmp / f"fixture-{left_files}-{right_files}"
        shutil.copytree(repo_root, new_root)
        new_queue = new_root / "docs" / "execution" / "pipeline-queue.tsv"
        return new_queue, new_root

    def test_threshold_under_is_suggested(self) -> None:
        """11 fájl: a küszöb alatt → a pár JAVASOLT."""
        # left=5 (5+1 brief=6), right=5 (5+1 brief=6) → egyesített = 12
        # VAGY left=4 right=4 → egyesített = 10 (alatta).
        # A mátrix az EGYESÍTETT halmaz méretét méri — legyen 11 a határ
        # alatti utolsó érték: left=4 (5), right=5 (6) → 5+6=11.
        queue_path, repo_root = self._make_pair(left_files=4, right_files=5)
        exit_code, stdout, stderr = run_merge_plan(repo_root, ["--format", "json", "--max-paths", "12"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["max_paths"], 12)
        candidates = payload["candidates"]
        self.assertEqual(len(candidates), 1)
        pair = candidates[0]
        self.assertEqual(pair["left_round"], "E07-R01")
        self.assertEqual(pair["right_round"], "E07-R02")
        self.assertEqual(pair["merged_paths"], 11)
        self.assertEqual(pair["feature_root"], "lib/features/songs")

    def test_threshold_at_is_suggested(self) -> None:
        """12 fájl: a küszöbön (inkluzív) → a pár JAVASOLT."""
        # left=5 (5+1=6), right=5 (5+1=6) → egyesített = 12.
        queue_path, repo_root = self._make_pair(left_files=5, right_files=5)
        exit_code, stdout, stderr = run_merge_plan(repo_root, ["--format", "json", "--max-paths", "12"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        candidates = payload["candidates"]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["merged_paths"], 12)

    def test_threshold_over_is_not_suggested(self) -> None:
        """13 fájl: a küszöb fölött → a pár NEM javasolt."""
        # left=6 (6+1=7), right=5 (5+1=6) → egyesített = 13.
        queue_path, repo_root = self._make_pair(left_files=6, right_files=5)
        exit_code, stdout, stderr = run_merge_plan(repo_root, ["--format", "json", "--max-paths", "12"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["candidates"], [])


class BriefMergePlanFalsificationTest(unittest.TestCase):
    """A brief §4 két kötelező falszifikációs cellája."""

    def setUp(self) -> None:
        self._tmp = Path(tempfile.mkdtemp(prefix="merge-plan-falsif-"))

    def tearDown(self) -> None:
        shutil.rmtree(self._tmp, ignore_errors=True)

    def test_native_gate_pair_excluded(self) -> None:
        """Falszifikációs cella: a D2 4. feltétele (natív gate kizárása) —
        ha kivennénk, a `native_gate=true` pár megjelenne a javaslatban.
        A teszt bizonyítja, hogy a jelenlegi szabály KIZÁRJA."""
        rows = [
            ("E07-R01", "docs/rounds/e07-r01.md", "pending"),
            ("E07-R02", "docs/rounds/e07-r02.md", "pending"),
        ]
        briefs = {
            "E07-R01": (
                ["docs/rounds/e07-r01.md", "lib/features/songs/a_0.dart", "lib/features/songs/a_1.dart", "lib/features/songs/a_2.dart", "lib/features/songs/a_3.dart"],
                True,  # natív gate!
            ),
            "E07-R02": (
                ["docs/rounds/e07-r02.md", "lib/features/songs/b_0.dart", "lib/features/songs/b_1.dart", "lib/features/songs/b_2.dart", "lib/features/songs/b_3.dart"],
                False,
            ),
        }
        queue_path, repo_root = _build_queue(rows=rows, briefs=briefs)
        new_root = self._tmp / "fixture-native"
        shutil.copytree(repo_root, new_root)
        exit_code, stdout, stderr = run_merge_plan(new_root, ["--format", "json"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["candidates"], [])

    def test_non_neighbor_epic_pair_excluded(self) -> None:
        """Az 1. feltétel: a két kör a sorban SZOMSZÉDOS és egymás előfeltétele
        (azonos epic, egymás utáni sorszám). Ha nem szomszédosak, kimaradnak."""
        rows = [
            ("E07-R01", "docs/rounds/e07-r01.md", "pending"),
            # E07-R02 HIÁNYZIK — a sorban E07-R03 következik.
            ("E07-R03", "docs/rounds/e07-r03.md", "pending"),
        ]
        briefs = {
            "E07-R01": (
                ["docs/rounds/e07-r01.md", "lib/features/songs/a.dart"],
                False,
            ),
            "E07-R03": (
                ["docs/rounds/e07-r03.md", "lib/features/songs/b.dart"],
                False,
            ),
        }
        queue_path, repo_root = _build_queue(rows=rows, briefs=briefs)
        new_root = self._tmp / "fixture-non-neighbor"
        shutil.copytree(repo_root, new_root)
        exit_code, stdout, stderr = run_merge_plan(new_root, ["--format", "json"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["candidates"], [])

    def test_different_feature_root_excluded(self) -> None:
        """A 2. feltétel: azonos feature-gyökér az allowed_paths többségében —
        különböző gyökér esetén kimaradnak."""
        rows = [
            ("E07-R01", "docs/rounds/e07-r01.md", "pending"),
            ("E07-R02", "docs/rounds/e07-r02.md", "pending"),
        ]
        briefs = {
            "E07-R01": (
                ["docs/rounds/e07-r01.md", "lib/features/songs/a.dart", "lib/features/songs/b.dart"],
                False,
            ),
            "E07-R02": (
                ["docs/rounds/e07-r02.md", "lib/features/auth/c.dart", "lib/features/auth/d.dart"],
                False,
            ),
        }
        queue_path, repo_root = _build_queue(rows=rows, briefs=briefs)
        new_root = self._tmp / "fixture-diff-root"
        shutil.copytree(repo_root, new_root)
        exit_code, stdout, stderr = run_merge_plan(new_root, ["--format", "json"])
        self.assertEqual(exit_code, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["candidates"], [])

    def test_text_rendering_contains_header(self) -> None:
        """A szöveges kimenet fejléce megjelenik — a kiugró-szűrés NEM a
        brief-merge-plan feladata, de a javaslatot szövegesen is ki kell
        tudni olvasni."""
        rows = [
            ("E07-R01", "docs/rounds/e07-r01.md", "pending"),
            ("E07-R02", "docs/rounds/e07-r02.md", "pending"),
        ]
        briefs = {
            "E07-R01": (
                ["docs/rounds/e07-r01.md", "lib/features/songs/a.dart", "lib/features/songs/b.dart"],
                False,
            ),
            "E07-R02": (
                ["docs/rounds/e07-r02.md", "lib/features/songs/c.dart", "lib/features/songs/d.dart"],
                False,
            ),
        }
        queue_path, repo_root = _build_queue(rows=rows, briefs=briefs)
        new_root = self._tmp / "fixture-text"
        shutil.copytree(repo_root, new_root)
        exit_code, stdout, stderr = run_merge_plan(new_root, ["--format", "text"])
        self.assertEqual(exit_code, 0, stderr)
        self.assertIn("E07-R01", stdout)
        self.assertIn("E07-R02", stdout)
        self.assertIn("lib/features/songs", stdout)


if __name__ == "__main__":
    unittest.main()