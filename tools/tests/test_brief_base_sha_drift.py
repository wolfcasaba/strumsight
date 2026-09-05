"""Az `S15` szabály — az ELŐRE MEGÍRT brief mért alapja azóta ELMOZDULT.

MÉRT ok (E14-R10 / H3, 2026-09-05, `docs/LESSONS.md` L636). Az E14-R10 briefje
2026-08-20-án, `main @ 88e08e65`-en készült, és egy ÚJ irány-abstention kaput írt
elő (`strum_direction_gate.dart`, margó **0,150**, ELFOGADÁS-oldalon inkluzív).
Közben 2026-09-04-én ugyanaz a döntés MERGE-ELVE landolt az E14-R04 / ADR 0505
szerződésében (`StrumPrediction.decision`, margó **0,05**, ELUTASÍTÁS-oldalon
inkluzív) — a kör tehát egy MÁSODIK, versengő döntési helyet épített volna
ugyanarra a kérdésre, más értékkel és más inkluzivitással. A bekötéshez ráadásul
`pDown`/`pUp` kellett volna a brief TILOS ZÓNÁJÁBAN élő fájlokból, így a kör
célja az `allowed_paths` tágítása nélkül teljesíthetetlen volt: **H3**, egy
teljes orchestrátor-session árán, még a dispatch ELŐTT.

Miért volt néma: az S9–S14 mind a brief és a JELEN fa VISZONYÁT méri (leltár,
típus-pin, gate-parancs, létező előtagok), tehát egy önmagában konzisztens, csak
ELAVULT brief mindegyiket kielégíti. A brief maga előírja a pre-flightot
(„olvasd újra … eltérésnél §0.0 revízió"), de ezt eddig kizárólag FEGYELEM
tartotta be — pontosan az a helyzet, amiért az S12 is megszületett: gépi őr kell
rá, nem fegyelem.

A predikátum KÉT jelet mér, mert az E14-R10-et a második fogta volna meg: a
szerződés ÚJ FÁJLKÉNT érkezett (`strum_prediction.dart`), nem a brief által
megnevezett fájlok módosításaként.

A korpuszon mérve (`main @ cc936bde`, `--all --level strict`): 89 leletes
briefből **33** kap S15-öt — köztük az E14-R11…R16, vagyis ugyanannak a
2026-08-20-i előre-írás-hullámnak a többi tagja: ezek ma mind ugyanabba a H3-ba
futnának bele. A szabály `strict`, `done` körre néma, és mérés hiányában (nincs
git, sekély klón, ismeretlen SHA) is néma; a CI-kapu `--open --level base`
(`.github/workflows/router-ci.yml`), tehát ez sosem vált pirosra egy lezárt kört
— mérve: a `base` szint a javítás után is „nincs lelet".

A teszt VÉGIG fixture-eken mér (eldobható git-repók), egyetlen élő-fa állapotot
sem olvas — így az L612 csapdájába nem eshet: nem pinneli sem a javított kör
munkájának hiányát, sem a meglétét.
"""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
BRIEF_NAME = "e14-r10-direction-abstention-hotfix.md"
OWNED = "lib/features/live/engine/dsp/live_pipeline.dart"
NAMED = "lib/features/live/engine/dsp/strum_direction_classifier.dart"
OWN_TEST = "test/features/live/strum_direction_gate_test.dart"
# A szerződés, ami az E14-R04-gyel ÚJ fájlként landolt, és amiről a brief nem tud.
LANDED = "lib/features/live/domain/recognition/strum_prediction.dart"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _git(repo: Path, *arguments: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *arguments],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def _brief_text(base_sha: str | None) -> str:
    base = f"kód olvasva: `main @ {base_sha}`" if base_sha else "kód olvasva: a jelen fa"
    return f"""# E14-R10 — Azonnali direction abstention hotfix

- **Státusz:** PREPARED (előre megírva 2026-08-20, {base})

**STOP-protokoll:** scope-ütközésnél állj meg.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "{OWNED}",
  "{OWN_TEST}",
  "docs/rounds/{BRIEF_NAME}",
]
gate_tests = ["{OWN_TEST}"]
native_gate = false
```

## 2. Jelenlegi állapot — mért tények

- `{NAMED}` — a confidence egy rögzített létra, a kör ezt NEM írja át.

## 7. A mérce

```bash
tools/round-gate.sh {OWN_TEST}
```

## 9. Kör-jelzés

`done` csak review + CI + merge után.
"""


def _make_repo(directory: Path, *, status: str = "pending") -> Path:
    """Egy eldobható git-repó a brief BÁZIS állapotával, egy commitban."""
    (directory / "docs" / "rounds").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / ".ai").mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    (directory / "docs" / "execution" / "pipeline-queue.tsv").write_text(
        f"E14-R10\tdocs/rounds/{BRIEF_NAME}\tsonnet-impl\t0362\t{status}\n",
        encoding="utf-8",
    )
    for relative in (OWNED, NAMED, OWN_TEST):
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("void main() {}\n", encoding="utf-8")
    (directory / "docs" / "rounds" / BRIEF_NAME).write_text(
        _brief_text("PLACEHOLDER"), encoding="utf-8"
    )
    _git(directory, "init", "-q", "-b", "main")
    _git(directory, "config", "user.email", "heal@example.invalid")
    _git(directory, "config", "user.name", "heal")
    _git(directory, "add", "-A")
    _git(directory, "commit", "-qm", "bázis")
    return directory


def _write_brief(repo: Path, base_sha: str | None) -> Path:
    path = repo / "docs" / "rounds" / BRIEF_NAME
    path.write_text(_brief_text(base_sha), encoding="utf-8")
    return path


def _lint(repo: Path, base_sha: str | None):
    path = _write_brief(repo, base_sha)
    return brief_lint.lint_text(path.read_text(encoding="utf-8"), path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _message(findings, code: str) -> str:
    return next(item["message"] for item in findings if item["code"] == code)


class BriefBaseShaDriftTest(unittest.TestCase):
    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def _commit(self, repo: Path, message: str) -> None:
        _git(repo, "add", "-A")
        _git(repo, "commit", "-qm", message)

    def test_a_modified_referenced_file_is_a_finding(self) -> None:
        repo = self._repo()
        base = _git(repo, "rev-parse", "HEAD")
        (repo / NAMED).write_text("void main() { /* r170 kalibráció */ }\n", encoding="utf-8")
        self._commit(repo, "a létra elmozdult")

        findings = _lint(repo, base)
        self.assertIn(
            "S15",
            _codes(findings),
            "a brief §2 »mért tények« szakasza egy azóta MEGVÁLTOZOTT fájlra "
            "hivatkozik, és ez némán maradt",
        )
        self.assertIn(NAMED, _message(findings, "S15"))

    def test_a_new_file_under_the_feature_root_is_a_finding(self) -> None:
        """Az E14-R10 valódi alakja: a szerződés ÚJ FÁJLKÉNT landolt.

        A brief egyetlen megnevezett fájlja sem változott — mégis megszületett
        ugyanannak a döntésnek egy merge-elt, versengő helye.
        """
        repo = self._repo()
        base = _git(repo, "rev-parse", "HEAD")
        landed = repo / LANDED
        landed.parent.mkdir(parents=True, exist_ok=True)
        landed.write_text(
            "const double uncertainMarginThreshold = 0.05;\n", encoding="utf-8"
        )
        self._commit(repo, "ADR 0505 szerződés")

        findings = _lint(repo, base)
        self.assertIn("S15", _codes(findings))
        message = _message(findings, "S15")
        self.assertIn(LANDED, message)
        self.assertIn("ÚJ fájl landolt", message)

    def test_an_unmoved_base_clears_the_finding(self) -> None:
        repo = self._repo()
        base = _git(repo, "rev-parse", "HEAD")
        (repo / "docs" / "irrelevans.md").write_text("a fán kívül\n", encoding="utf-8")
        self._commit(repo, "a kör felületén kívüli commit")

        findings = _lint(repo, base)
        self.assertNotIn(
            "S15",
            _codes(findings),
            "a kör felületét NEM érintő commit nem lehet lelet — különben a "
            "szabály minden briefre zajt ad, és a pre-flight megtanulja átlapozni",
        )

    def test_a_done_round_is_never_flagged_retroactively(self) -> None:
        repo = self._repo(status="done")
        base = _git(repo, "rev-parse", "HEAD")
        (repo / NAMED).write_text("void main() { /* később */ }\n", encoding="utf-8")
        self._commit(repo, "a lezárt kör után jött")

        findings = _lint(repo, base)
        self.assertNotIn("S15", _codes(findings))

    def test_an_unknown_sha_is_silent_not_a_crash(self) -> None:
        """Sekély klón / idegen SHA: »nem tudom megmérni« ≠ »van lelet«."""
        repo = self._repo()
        findings = _lint(repo, "deadbee")
        self.assertNotIn("S15", _codes(findings))

    def test_a_brief_without_a_base_sha_is_silent(self) -> None:
        repo = self._repo()
        base = _git(repo, "rev-parse", "HEAD")
        (repo / NAMED).write_text("void main() { /* elmozdult */ }\n", encoding="utf-8")
        self._commit(repo, "drift")

        findings = _lint(repo, None)
        self.assertNotIn(
            "S15",
            _codes(findings),
            "bázis-SHA nélkül nincs mihez mérni — a szabály ilyenkor néma",
        )

    def test_the_finding_is_strict_so_the_ci_gate_can_not_turn_red(self) -> None:
        """A CI `--open --level base`-t futtat: az S15 sosem viheti pirosra."""
        repo = self._repo()
        base = _git(repo, "rev-parse", "HEAD")
        (repo / NAMED).write_text("void main() { /* elmozdult */ }\n", encoding="utf-8")
        self._commit(repo, "drift")

        findings = _lint(repo, base)
        levels = {item["level"] for item in findings if item["code"] == "S15"}
        self.assertEqual({"strict"}, levels)


if __name__ == "__main__":
    unittest.main()
