"""Az `S11` szabály — az örökség-képernyőt PINNELŐ, briefen kívüli tesztek.

MÉRT GYÖKÉROK (2026-08-25). A Ch13 sáv az E13-R16-tal fordult át
komponens-építésből KÉPERNYŐ-MIGRÁCIÓBA, és a következő két kör ugyanabban az
osztályban állt meg:

  * **E13-R16 / F9** — a kör két új képernyője a `test/ui/ui_inventory_test.dart`
    egzakt `hasLength(79)` celláját 81-re mozdította; a fájl nem volt az
    `allowed_paths`-on → H3 (full-gate 32867296946 FAILURE);
  * **E13-R17 / H3** — a `test/app/navigation/` őrei TÍPUSRA pinnelik, melyik
    route melyik képernyőt rendereli; a kör a három hub-adaptert cserélte le →
    `flutter test test/app/navigation/` +33 → +30 -3, és a fájlok szintén a
    listán kívül éltek.

Mindkettőt külön HEAL-kör oldotta fel (PR #454, #455), külön `S9`/`S10`
szabállyal — utólag, esetenként. A hibaosztály viszont ÁLTALÁNOS: bármelyik
migrációs kör lecserélhet egy örökség-képernyőt, amit a fa más pontján élő
teszt a típusára pinnel, és a teszt felvétele az orchestrátornak TÁGÍTÁS
(L478), tehát a kör H3-ban áll meg, mielőtt egyetlen sor kód megszületne.

Az `S11` ezt a szabályt általánosítja, a fa mérhető igazságához kötve: a kör
`allowed_paths`-a alapján összegyűjti a MÁR LÉTEZŐ képernyőket, majd megkeresi
azokat a teszteket, amelyek a képernyő forrását IMPORTÁLJÁK **és** a típusát
NÉVEN NEVEZIK, de nincsenek a brief listáján.

MÉRVE a teljes, 343 elemű brief-korpuszon (`main @ b28bb1bf`): 8 lelet, mind
NYITOTT körön (6 `pending` Ch13-brief — R18, R19, R20, R21, R32, R35 —, 1
`prepared` Ch14 és 1 `PLANNING` GOV-brief), **0 `done` (merge-elt) kör**.
"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"

# A MÉRT eset magja: az E13-R19 (Tuner/Metronóm migráció) lecseréli a
# `tuner_screen.dart`-ot, amit a `test/ui/ui_baseline_screenshot_test.dart`
# IMPORTÁL — ott ez nem is assert-hiba lenne, hanem FORDÍTÁSI hiba.
LEGACY_SCREEN = "lib/features/tuner/screens/tuner_screen.dart"
LEGACY_TYPE = "TunerScreen"
OUTSIDE_GUARD = "test/ui/ui_baseline_screenshot_test.dart"
OWN_TEST = "test/features/tuner/tuner_ui_mapping_test.dart"
BRIEF_NAME = "e13-r19-tuner-and-metronome-ui.md"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _make_repo(directory: Path, *, status: str = "pending", guard_pins: bool = True) -> Path:
    (directory / "docs" / "rounds").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / ".ai").mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    screen = directory / LEGACY_SCREEN
    screen.parent.mkdir(parents=True, exist_ok=True)
    screen.write_text(f"class {LEGACY_TYPE} extends StatelessWidget {{}}\n", encoding="utf-8")

    # A KÍVÜL élő őr: importál ÉS típust nevez — pontosan a mért pinnelés alakja.
    guard = directory / OUTSIDE_GUARD
    guard.parent.mkdir(parents=True, exist_ok=True)
    guard.write_text(
        "import 'package:strumsight/features/tuner/screens/tuner_screen.dart';\n"
        + (f"void main() {{ find.byType({LEGACY_TYPE}); }}\n" if guard_pins else "void main() {}\n"),
        encoding="utf-8",
    )

    own = directory / OWN_TEST
    own.parent.mkdir(parents=True, exist_ok=True)
    own.write_text(
        "import 'package:strumsight/features/tuner/screens/tuner_screen.dart';\n"
        f"void main() {{ find.byType({LEGACY_TYPE}); }}\n",
        encoding="utf-8",
    )

    (directory / "docs" / "execution" / "pipeline-queue.tsv").write_text(
        f"E13-R19\tdocs/rounds/{BRIEF_NAME}\tsonnet-impl\tnincs\t{status}\n", encoding="utf-8"
    )
    return directory


def _brief_text(*, allowed_paths, gate_tests) -> str:
    paths = "\n".join(f'  "{path}",' for path in [*allowed_paths, f"docs/rounds/{BRIEF_NAME}"])
    gates = "[" + ", ".join(f'"{gate}"' for gate in gate_tests) + "]"
    return f"""# E13-R19 — Tuner és metronóm UI

A mérce artefaktuma: `tools/round-gate.sh`.

**STOP-protokoll:** scope-ütközésnél állj meg.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
{paths}
]
gate_tests = {gates}
native_gate = false
```

## 9. Kör-jelzés

`done` csak review + CI + merge után.
"""


def _lint(repo: Path, text: str):
    path = repo / "docs" / "rounds" / BRIEF_NAME
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return brief_lint.lint_text(text, path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _message(findings, code: str) -> str:
    return next(item["message"] for item in findings if item["code"] == code)


class BriefLegacyScreenPinScopeTest(unittest.TestCase):
    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def test_a_pinned_legacy_screen_without_the_guard_on_the_list_is_a_finding(self) -> None:
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(allowed_paths=(LEGACY_SCREEN, OWN_TEST), gate_tests=(OWN_TEST,)),
        )
        self.assertIn(
            "S11",
            _codes(findings),
            "a listán kívüli, TÍPUSRA pinnelő őr némán maradt — ez pontosan az "
            "E13-R16/F9 és E13-R17/H3 halt-osztálya, kör-megállással",
        )
        message = _message(findings, "S11")
        self.assertIn(OUTSIDE_GUARD, message)
        self.assertNotIn(OWN_TEST, message, "a briefen MÁR szereplő teszt nem lelet")

    def test_the_directory_prefix_form_is_measured_too(self) -> None:
        # Az S9 mért vakfoltja (E13-R16): a brief KÖNYVTÁRAT engedett, nem
        # fájlt. Az S11 predikátuma ezért a könyvtár alá bomlik le.
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(allowed_paths=("lib/features/tuner/", OWN_TEST), gate_tests=(OWN_TEST,)),
        )
        self.assertIn("S11", _codes(findings))
        self.assertIn(OUTSIDE_GUARD, _message(findings, "S11"))

    def test_listing_the_guard_on_both_lists_clears_the_finding(self) -> None:
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=(LEGACY_SCREEN, OWN_TEST, OUTSIDE_GUARD),
                gate_tests=(OWN_TEST, OUTSIDE_GUARD),
            ),
        )
        self.assertNotIn("S11", _codes(findings))

    def test_a_done_round_is_never_flagged_retroactively(self) -> None:
        repo = self._repo(status="done")
        findings = _lint(
            repo,
            _brief_text(allowed_paths=(LEGACY_SCREEN, OWN_TEST), gate_tests=(OWN_TEST,)),
        )
        self.assertNotIn(
            "S11",
            _codes(findings),
            "egy már merge-elt kör visszamenőleges riasztást kapott — ugyanaz a "
            "hamis-pozitív osztály, amit az S5/S7/S10 `done` szűrője zár ki",
        )

    def test_a_plain_import_without_the_type_name_is_not_a_pin(self) -> None:
        # A kettős feltétel hamis riasztás elleni fele: import önmagában (pl.
        # tranzitív behúzás) még nem pinnel TÍPUST.
        repo = self._repo(guard_pins=False)
        findings = _lint(
            repo,
            _brief_text(allowed_paths=(LEGACY_SCREEN, OWN_TEST), gate_tests=(OWN_TEST,)),
        )
        self.assertNotIn("S11", _codes(findings))

    def test_a_screen_that_does_not_exist_yet_is_not_a_pin(self) -> None:
        # A LÉTEZÉS-feltétel: nemlétező képernyőt senki nem pinnel, és az ÚJ
        # képernyő hatását az S9 méri, nem ez a szabály.
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=("lib/features/today/today_hub_screen.dart", OWN_TEST),
                gate_tests=(OWN_TEST,),
            ),
        )
        self.assertNotIn("S11", _codes(findings))


if __name__ == "__main__":
    unittest.main()
