"""Az `S13` szabály — az `allowed_paths` NEM LÉTEZŐ könyvtár-előtagjai.

MÉRT, KÉTSZER visszatért hibaosztály ([L497](../../docs/LESSONS.md#l497)).

**E13-R22 pre-flight (2026-08-26).** Az induláskor kapott brief-lint jelentés
(`.pipeline/brief-lint-E13-R22.md`) egyetlen sor volt: *„Brief-lint (strict) —
nincs lelet."* A pre-flight első mérése viszont:

    find lib/features/practice -type d
    → application  data  domain  presentation

miközben a brief `allowed_paths`-a `lib/features/practice/results/`,
`.../history/` és `.../speed_builder/` könyvtárakat sorolt fel — **egyik sem
létezik**. A lista NULLA létező fájlt fedett: a kör egyetlen engedélyezett
fájlon sem dolgozhatott volna, a migrálandó `PracticeResultScreen` pedig (ami
LÉTEZIK, route-on regisztrált, és három teszt pinneli) kívül esett rajta.

**E13-R23 pre-flight (ugyanaznap).** Ugyanez, három másik könyvtárral
(`lib/features/songs/library|overview/`, `lib/features/setlists/`) — a lint
megint „nincs lelet"-et adott.

**Miért volt néma az eddigi mérce.** Az `S9` a képernyő-leltárat, az `S11` a
listán kívüli típus-pineket, az `S12` a gate-parancsot méri — mindegyik a fán
TALÁLT állapotból indul, tehát egy útvonal, ami semmire sem illeszkedik,
egyik predikátumot sem aktiválja. A rés nem a szabályok gyengesége, hanem egy
hiányzó, triviális elő-ellenőrzés: *létezik-e egyáltalán, amit a lista
felsorol?*

MÉRVE a teljes brief-korpuszon (`main @ 4185418d`): **19 lelet, mind NYITOTT
körön** — 11 `pending` (a maradék Ch13 sáv) és 8 `hold` —, **0 `done`
(merge-elt) kör**.
"""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
BRIEF_NAME = "e13-r25-song-trainer-and-setlist-run.md"
REAL_DIR = "lib/features/songs/screens/"
PHANTOM_DIR = "lib/features/songs/trainer/"
OWN_TEST = "test/features/songs/trainer_test.dart"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _make_repo(directory: Path, *, status: str = "pending") -> Path:
    for relative in (
        "docs/rounds",
        "docs/execution",
        ".ai",
        REAL_DIR,
        "lib/features/songs/model",
        "test/features/songs",
    ):
        (directory / relative).mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    (directory / REAL_DIR / "song_screen.dart").write_text("class SongScreen {}\n", encoding="utf-8")
    (directory / "lib/features/songs/model/song.dart").write_text("class Song {}\n", encoding="utf-8")
    (directory / OWN_TEST).write_text("void main() {}\n", encoding="utf-8")
    (directory / "docs" / "execution" / "pipeline-queue.tsv").write_text(
        f"E13-R25\tdocs/rounds/{BRIEF_NAME}\tsonnet-impl\tnincs\t{status}\n", encoding="utf-8"
    )
    # A predikátum `git ls-files`-t olvas: a gitignore-olt/generált kimenet NEM
    # számít létező szerződésnek, ezért a fixture is valódi git-fa.
    for argv in (
        ["git", "init", "-q"],
        ["git", "config", "user.email", "t@t"],
        ["git", "config", "user.name", "t"],
        ["git", "add", "-A"],
        ["git", "commit", "-qm", "fixture"],
    ):
        subprocess.run(argv, cwd=directory, check=True, capture_output=True)
    return directory


def _brief_text(*, allowed_paths) -> str:
    paths = "\n".join(f'  "{path}",' for path in [*allowed_paths, f"docs/rounds/{BRIEF_NAME}"])
    return f"""# E13-R25 — Song trainer és setlist run

**STOP-protokoll:** scope-ütközésnél állj meg.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
{paths}
]
gate_tests = ["{OWN_TEST}"]
native_gate = false
```

## 7. A mérce

```bash
tools/round-gate.sh {OWN_TEST}
```

## 9. Kör-jelzés

`done` csak review + CI + merge után.
"""


def _lint(repo: Path, text: str):
    path = repo / "docs" / "rounds" / BRIEF_NAME
    path.write_text(text, encoding="utf-8")
    return brief_lint.lint_text(text, path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _message(findings, code: str) -> str:
    return next(item["message"] for item in findings if item["code"] == code)


class BriefAllowedPathsExistenceTest(unittest.TestCase):
    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def test_a_phantom_directory_prefix_is_a_finding(self) -> None:
        repo = self._repo()
        findings = _lint(repo, _brief_text(allowed_paths=(PHANTOM_DIR, OWN_TEST)))
        self.assertIn(
            "S13",
            _codes(findings),
            "a nulla fájlt fedő könyvtár-előtag némán maradt — pontosan az "
            "E13-R22/E13-R23 pre-flight hibaosztálya (L497)",
        )
        self.assertIn(PHANTOM_DIR, _message(findings, "S13"))

    def test_the_finding_names_the_nearest_existing_ancestor_and_its_real_children(self) -> None:
        # Ez teszi a leletet JAVÍTHATÓVÁ: a pre-flight enélkül `find`-dal keresi
        # ki ugyanezt (L497 mérése), így a javítás útvonal-csere, nem nyomozás.
        repo = self._repo()
        findings = _lint(repo, _brief_text(allowed_paths=(PHANTOM_DIR, OWN_TEST)))
        message = _message(findings, "S13")
        self.assertIn("lib/features/songs/", message)
        self.assertIn("`screens`", message)
        self.assertIn("`model`", message)

    def test_an_existing_directory_prefix_is_not_a_finding(self) -> None:
        repo = self._repo()
        findings = _lint(repo, _brief_text(allowed_paths=(REAL_DIR, OWN_TEST)))
        self.assertNotIn("S13", _codes(findings))

    def test_a_not_yet_existing_dart_file_is_not_a_finding(self) -> None:
        # A kör ÚJ fájlt hozhat létre — a fájlútvonal hiánya nem ennek a
        # szabálynak a mércéje (azt az S5 méri típusnév-ütközésre). Az S13
        # KIZÁRÓLAG könyvtár-előtagra lő.
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(allowed_paths=("lib/features/songs/screens/brand_new_screen.dart", OWN_TEST)),
        )
        self.assertNotIn("S13", _codes(findings))

    def test_a_done_round_is_never_flagged_retroactively(self) -> None:
        repo = self._repo(status="done")
        findings = _lint(repo, _brief_text(allowed_paths=(PHANTOM_DIR, OWN_TEST)))
        self.assertNotIn(
            "S13",
            _codes(findings),
            "egy már merge-elt kör visszamenőleges riasztást kapott — ugyanaz a "
            "hamis-pozitív osztály, amit az S5/S7/S10/S11/S12 `done` szűrője zár ki",
        )


if __name__ == "__main__":
    unittest.main()
