"""E09-R24 H-NOSIGNAL önjavítás (ADR 0112) — az `S9` képernyő-leltár lelet.

MÉRT GYÖKÉROK (2026-08-24). Az E09-R24 orchestrátor-sessionje a 4 órás
abszolút időkorlátnál halt meg jelzés nélkül (`.pipeline/HALTED`,
`session-E09-R24-20260824T065506.log`). A napló időelemzése szerint a
240 percből ~60 percet EGYETLEN, elkerülhető újramunka vitt el:

  * 09:50:26–10:07:41 — `full-gate.yml` 32713670226 a `855db329` SHA-n
    **FAILURE**: `test/ui/ui_inventory_test.dart` `hasLength(76)` vs a
    tényleges 79 (a kör három új klub-képernyőt hozott);
  * ~10:08–10:10 — diagnózis + `§0.0c` brief-revízió a `main`-en (`863a8ac3`);
  * 10:10:41–10:24:25 — egy TELJES javító implementer-kör az egysoros
    szám-emelésért;
  * 10:24:50–10:42:30 — `full-gate.yml` 32716654207 újrafuttatás (success).

A kör ~4 óra 10 percet igényelt, 4 óra állt rendelkezésre. A halt oka tehát
nem kódhiba, hanem BRIEF-hiba: a dispatchelt `allowed_paths` (`b2cf3e35`)
három ÚJ `lib/features/**/*_screen.dart` fájlt engedett, de a determinisztikus
képernyő-leltár tesztjét nem — így az implementer nem is nyúlhatott hozzá.

Ez PRECEDENSES osztály, nem egyszeri baleset:

  * E08-R15/H3 — ugyanez, PR #383 `ae562c34`, 5442 zöld teszt mellett
    egyedül a leltárteszt bukott (`test_e08_r15_ui_inventory_scope.py`);
  * E09-R21 §0.0 — ugyanez pre-flightban elkapva (74→75);
  * E09-R24 — a kör saját commit-üzenete (`863a8ac3`) rögzíti: *„my own
    pre-flight missed applying it here despite having read that exact
    precedent"*.

A védelem eddig KÖRSPECIFIKUS, utólag írt regressziós tesztekben élt, tehát
a KÖVETKEZŐ kört nem védte. Az `S9` ezt teszi általánossá a `brief-lint.py`
pre-dispatch szintjén (`round-pipeline.sh` `write_brief_lint`), ahol a lelet
még a kör ELEJÉN, teendőlistaként javul — a lint saját fejléce pontosan erre
való: „a mért javító körök nagy része nem kódhiba, hanem BRIEF-hiba".

A PREDIKÁTUM a CI igazságához kötött, nem tippelt: a `tool/ui_inventory.dart`
a `lib/features/**` fát listázza, és a `_screen.dart` végű fájlokat számolja
(`screenPaths`). Az `S9` ezért PONTOSAN akkor lő, ha az `allowed_paths` olyan
`lib/features/**/*_screen.dart` útvonalat enged, ami a repóban MÉG NEM
LÉTEZIK (tehát a kör LÉTREHOZZA → a szám mozdul), és a
`test/ui/ui_inventory_test.dart` nem szerepel egyszerre az `allowed_paths`-ban
ÉS a `gate_tests`-ben.

A „még nem létezik" feltétel nem finomkodás, hanem a hamis riasztás elleni
mérce — a lint fejléce szerint „egy hamis riasztás rosszabb a hiányzó
ellenőrzésnél: leszoktat az olvasásáról". MÉRVE a teljes brief-korpuszon
(343 brief, 339 elemezhető):

  * a naiv „említ egy `_screen.dart`-ot" szabály **39 briefre** lőne, köztük
    36 MÁR ZÖLDEN MERGE-ELT körre — ezek a képernyőt MÓDOSÍTOTTÁK, nem
    hozták létre, tehát a leltár száma nem mozdult: mind hamis riasztás;
  * a létezés-feltétellel a korpuszon **0 hamis riasztás** marad, és pontosan
    4 valódi lelet: `e09-r25`, `e09-r28`, `e09-r29`, `e10-r31` — mind
    `pending`, egyik sem futott le. Az `e09-r25` a sor KÖVETKEZŐ E09 köre,
    tehát ugyanez a halt egy körön belül visszatért volna.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"

INVENTORY_TEST = "test/ui/ui_inventory_test.dart"
# A MÉRT eset: az E09-R24 brief `b2cf3e35`-ös (dispatchelt) `allowed_paths`
# listájának három képernyője. Nem kitalált fixture — ezek a fájlok
# hiányoztak a `855db329` SHA-n bukott leltártesztből.
E09_R24_NEW_SCREENS = (
    "lib/features/community/presentation/screens/clubs/club_list_screen.dart",
    "lib/features/community/presentation/screens/clubs/club_detail_screen.dart",
    "lib/features/community/presentation/screens/clubs/club_member_management_screen.dart",
)
E09_R24_GATE_TEST = "test/features/community/presentation/clubs/club_list_screen_test.dart"

# A MÁSODIK MÉRT eset (E13-R16/H3, 2026-08-25): az `allowed_paths` KÖNYVTÁR-
# előtagot enged, nem fájlútvonalat. Ezek a brief tényleges sorai (`5c32fb23`),
# és ez a két képernyő az, amit a kör a könyvtár alá LÉTREHOZOTT — a leltár
# `hasLength(79)` állítása így lett 81 a `32867296946` CI-futáson.
E13_R16_PREFIX = "lib/features/onboarding/"
E13_R16_EXISTING_SCREEN = "lib/features/onboarding/screens/onboarding_screen.dart"
E13_R16_CREATED_SCREENS = (
    "lib/features/onboarding/screens/permission_primer_screen.dart",
    "lib/features/onboarding/screens/first_win_stage_screen.dart",
)
E13_R16_GATE_TEST = "test/features/onboarding/permission_primer_test.dart"
# Az E13-R17 valódi előtagja: a kör a feature-könyvtárat is LÉTREHOZZA, tehát a
# fáról semmit nem lehet róla mérni.
E13_R17_MISSING_PREFIX = "lib/features/today/"
# Falszifikáció — MÉRT `done` (merge-elt) körök könyvtár-előtagjai. Egyik alatt
# sincs `_screen.dart` a `main`-en, tehát a leltár száma nem mozdulhat:
# E09-R05 (`done`) és E99-R18 (`done`).
MERGED_SCREENLESS_PREFIXES = (
    "lib/features/community/domain/repositories/",
    "lib/features/practice_generator/public/",
)


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _make_repo(
    directory: Path,
    *,
    existing_screens: tuple[str, ...] = (),
    existing_dirs: tuple[str, ...] = (),
) -> Path:
    """Minimális repo-váz; az `existing_screens` a MÁR LÉTEZŐ képernyőket adja.

    Az `existing_dirs` a képernyőt NEM tartó, de LÉTEZŐ könyvtárakat adja — ez
    az a falszifikációs cella, ami a merge-elt körök könyvtár-előtagjait
    (`domain/`, `public/`) hamis riasztás nélkül hagyja.
    """
    (directory / "docs" / "rounds").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / ".ai").mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    for relative in (INVENTORY_TEST, E09_R24_GATE_TEST):
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("", encoding="utf-8")
    for relative in existing_screens:
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("class S {}\n", encoding="utf-8")
    for relative in existing_dirs:
        target = directory / relative
        target.mkdir(parents=True, exist_ok=True)
        # Nem üres a könyvtár: a valódi `domain/`/`public/` fák is tartanak
        # Dart-forrást — csak `_screen.dart` végűt nem.
        (target / "contract.dart").write_text("class C {}\n", encoding="utf-8")
    return directory


def _brief_text(*, allowed_paths, gate_tests, name="e09-r24-club-domain-membership-and-roles.md") -> str:
    # SZÁNDÉKOSAN nincs `textwrap.dedent`: a dedent az INTERPOLÁCIÓ UTÁN fut, és
    # a beszúrt többsoros `paths` blokk elrontaná a közös prefix számítását —
    # a kód-kerítés beljebb csúszna, a brief pedig `B1`-gyel (elemezhetetlen
    # ai-router blokk) bukna az S9 helyett. Ugyanezt a mintát követi a
    # `test_brief_risk_justification.py` `_base_brief` fixture-je is.
    paths = "\n".join(f'  "{path}",' for path in [*allowed_paths, f"docs/rounds/{name}"])
    gates = "[" + ", ".join(f'"{gate}"' for gate in gate_tests) + "]"
    return f"""# E09-R24 — Klub domain, tagság és szerepkörök

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


E13_R16_BRIEF_NAME = "e13-r16-launch-and-onboarding.md"


def _e13_r16_brief(*, allowed_paths, gate_tests) -> str:
    """Az E13-R16 briefjének alakja: KÖNYVTÁR-előtag az `allowed_paths`-on.

    A `_brief_text`-tel azonos okból nincs `dedent`, és a `B6` miatt a címsor
    kör-azonosítója a fájlnévvel egyezik.
    """
    paths = "\n".join(
        f'  "{path}",' for path in [*allowed_paths, f"docs/rounds/{E13_R16_BRIEF_NAME}"]
    )
    gates = "[" + ", ".join(f'"{gate}"' for gate in gate_tests) + "]"
    return f"""# E13-R16 — Launch, recovery és onboarding migráció

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


def _lint(repo: Path, text: str, name="e09-r24-club-domain-membership-and-roles.md"):
    path = repo / "docs" / "rounds" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return brief_lint.lint_text(text, path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _levels(findings, code: str) -> set[str]:
    return {item["level"] for item in findings if item["code"] == code}


class BriefUiInventoryScopeTest(unittest.TestCase):
    """Az S9 mérce-mátrixa. Minden cella a MÉRT E09-R24 esetből származik."""

    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def test_new_screens_without_inventory_scope_is_a_strict_finding(self):
        """A MÉRT PIROS cella: az E09-R24 dispatchelt briefje (`b2cf3e35`)."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=E09_R24_NEW_SCREENS,
                gate_tests=[E09_R24_GATE_TEST],
            ),
        )
        self.assertIn("S9", _codes(findings))
        # A `base` szint VÁLTOZATLAN: a 39 meglévő, korábban zölden merge-elt
        # brief nem válhat CI-pirossá visszamenőleg.
        self.assertEqual({"strict"}, _levels(findings, "S9"))
        message = next(item["message"] for item in findings if item["code"] == "S9")
        self.assertIn(INVENTORY_TEST, message)
        # A lelet NEVEZZE MEG a képernyőket — a pre-flight teendő különben
        # nem cselekvőképes.
        for screen in E09_R24_NEW_SCREENS:
            self.assertIn(screen, message)

    def test_revised_brief_is_clean(self):
        """A MÉRT ZÖLD cella: a `863a8ac3` revízió után a CI is zöld lett."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=[*E09_R24_NEW_SCREENS, INVENTORY_TEST],
                gate_tests=[E09_R24_GATE_TEST, INVENTORY_TEST],
            ),
        )
        self.assertNotIn("S9", _codes(findings))

    def test_existing_screen_does_not_fire(self):
        """Falszifikáció: MÓDOSÍTÁS nem mozdítja a leltár számát → nincs lelet.

        Ez az a cella, ami a 36 hamis riasztást megszünteti.
        """
        repo = self._repo(existing_screens=E09_R24_NEW_SCREENS)
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=E09_R24_NEW_SCREENS,
                gate_tests=[E09_R24_GATE_TEST],
            ),
        )
        self.assertNotIn("S9", _codes(findings))

    def test_allowed_path_without_gate_test_still_fires(self):
        """Csak `allowed_paths` kevés: a lokális gate futtassa is a leltárt.

        Enélkül a drift csak a ~17 perces CI-ben derül ki — pontosan az a
        költség, ami az E09-R24-et megölte.
        """
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=[*E09_R24_NEW_SCREENS, INVENTORY_TEST],
                gate_tests=[E09_R24_GATE_TEST],
            ),
        )
        self.assertIn("S9", _codes(findings))

    def test_round_without_screens_does_not_fire(self):
        """A leltárhoz nem nyúló kör nem kap teendőt."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=[
                    "lib/features/community/domain/club.dart",
                    "lib/features/community/presentation/widgets/club_tile.dart",
                ],
                gate_tests=[E09_R24_GATE_TEST],
            ),
        )
        self.assertNotIn("S9", _codes(findings))

    def test_screen_outside_lib_features_does_not_fire(self):
        """A `tool/ui_inventory.dart` KIZÁRÓLAG a `lib/features/**` fát listázza."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=["lib/core/widgets/splash_screen.dart"],
                gate_tests=[E09_R24_GATE_TEST],
            ),
        )
        self.assertNotIn("S9", _codes(findings))


class BriefUiInventoryDirectoryPrefixTest(unittest.TestCase):
    """Az S9 KÖNYVTÁR-előtag vakfoltja — MÉRVE az E13-R16/H3 halton (2026-08-25).

    Az eredeti predikátum kizárólag olyan `allowed_paths` elemet nézett, ami
    LITERÁLISAN `_screen.dart`-ra végződik. Az E13-R16 briefje viszont a
    `lib/features/onboarding/` KÖNYVTÁRAT engedte, és a két új képernyőt
    (`permission_primer_screen.dart`, `first_win_stage_screen.dart`) az alá
    hozta létre. Az S9 ezért NÉMA maradt — a `9acd14e5` sáv-szintű batch
    pre-flight commit-üzenete rögzíti is, hogy a `brief-lint.py --level strict`
    mind a 20 Ch13 briefen „nincs lelet" eredményt adott, miközben mind a 20
    ugyanezt a halált hordozta.

    A mért ár: `full-gate` 32867296946 FAILURE (6366 passed, 2 failed) — a
    `hasLength(79)` a tényleges 81 ellen —, majd H3 halt, mert a leltárteszt
    nem volt az `allowed_paths`-on, a felvétele pedig tágítás ([L478](../../docs/LESSONS.md)).
    """

    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def _lint16(self, repo: Path, *, allowed_paths, gate_tests):
        return _lint(
            repo,
            _e13_r16_brief(allowed_paths=allowed_paths, gate_tests=gate_tests),
            name=E13_R16_BRIEF_NAME,
        )

    def test_screen_holding_directory_prefix_is_a_strict_finding(self):
        """A MÉRT PIROS cella: az E13-R16 dispatchelt briefje (`5c32fb23`)."""
        repo = self._repo(existing_screens=(E13_R16_EXISTING_SCREEN,))
        findings = self._lint16(
            repo,
            allowed_paths=(E13_R16_PREFIX, "lib/app/bootstrap/"),
            gate_tests=[E13_R16_GATE_TEST],
        )
        self.assertIn("S9", _codes(findings))
        # A szint VÁLTOZATLANUL `strict`: a router-ci a `base` szintet futtatja,
        # tehát egyetlen meglévő brief sem válik visszamenőleg CI-pirossá.
        self.assertEqual({"strict"}, _levels(findings, "S9"))
        message = next(item["message"] for item in findings if item["code"] == "S9")
        self.assertIn(INVENTORY_TEST, message)
        # A lelet NEVEZZE MEG az előtagot — enélkül a teendő nem cselekvőképes.
        self.assertIn(E13_R16_PREFIX, message)

    def test_directory_prefix_brief_with_the_guard_is_clean(self):
        """A ZÖLD cella: a §0.0/R6 revízió mindkét listára felveszi a leltárt."""
        repo = self._repo(existing_screens=(E13_R16_EXISTING_SCREEN,))
        findings = self._lint16(
            repo,
            allowed_paths=(E13_R16_PREFIX, "lib/app/bootstrap/", INVENTORY_TEST),
            gate_tests=[E13_R16_GATE_TEST, INVENTORY_TEST],
        )
        self.assertNotIn("S9", _codes(findings))

    def test_directory_prefix_in_allowed_paths_only_still_fires(self):
        """Csak `allowed_paths` itt is kevés — a drift a lokális gate-en derüljön ki."""
        repo = self._repo(existing_screens=(E13_R16_EXISTING_SCREEN,))
        findings = self._lint16(
            repo,
            allowed_paths=(E13_R16_PREFIX, INVENTORY_TEST),
            gate_tests=[E13_R16_GATE_TEST],
        )
        self.assertIn("S9", _codes(findings))

    def test_not_yet_existing_feature_directory_fires(self):
        """Az E13-R17 valódi esete: a kör magát a feature-könyvtárat is létrehozza.

        A fáról ilyenkor semmit nem lehet mérni, ezért nem zárható ki, hogy
        képernyő kerül alá — és mérve mind a 19 hátralévő Ch13 kör ilyen.
        """
        repo = self._repo()
        findings = self._lint16(
            repo,
            allowed_paths=(E13_R17_MISSING_PREFIX,),
            gate_tests=[E13_R16_GATE_TEST],
        )
        self.assertIn("S9", _codes(findings))

    def test_existing_screenless_directory_prefix_does_not_fire(self):
        """A FALSZIFIKÁCIÓS cella: MÉRT `done` körök előtagjai nem riasztanak.

        `lib/features/community/domain/repositories/` (E09-R05, `done`) és
        `lib/features/practice_generator/public/` (E99-R18, `done`) LÉTEZIK, és
        egyetlen `_screen.dart` sincs alattuk — a leltár száma nem mozdulhat.
        Ez az a feltétel, ami a szabályt hamis riasztás nélkül tartja.
        """
        repo = self._repo(existing_dirs=MERGED_SCREENLESS_PREFIXES)
        findings = self._lint16(
            repo,
            allowed_paths=MERGED_SCREENLESS_PREFIXES,
            gate_tests=[E13_R16_GATE_TEST],
        )
        self.assertNotIn("S9", _codes(findings))

    def test_directory_prefix_outside_lib_features_does_not_fire(self):
        """A `tool/ui_inventory.dart` KIZÁRÓLAG a `lib/features/**` fát listázza.

        Az E13-R16 `lib/app/bootstrap/` alatt is hozott két képernyőt
        (`launch_screen.dart`, `recovery_screen.dart`) — a leltár ezeket
        MÉRVE nem számolta, a 79→81 mozgást csak a két onboarding-képernyő adta.
        """
        repo = self._repo()
        findings = self._lint16(
            repo,
            allowed_paths=("lib/app/bootstrap/", "lib/core/widgets/"),
            gate_tests=[E13_R16_GATE_TEST],
        )
        self.assertNotIn("S9", _codes(findings))


class UiInventoryPredicateMatchesCiTest(unittest.TestCase):
    """A predikátum a CI igazságához van kötve, nem tippelve.

    Ha a `tool/ui_inventory.dart` képernyő-szabálya valaha megváltozik, ez a
    teszt PIROSRA vált — az `S9` különben némán elavulna.
    """

    def test_ui_inventory_still_counts_lib_features_screen_dart(self):
        source = (ROOT / "tool" / "ui_inventory.dart").read_text(encoding="utf-8")
        self.assertIn("lib", source)
        self.assertIn("features", source)
        self.assertIn("_screen.dart", source)
        self.assertIn("screenPaths", source)

    def test_inventory_test_asserts_an_exact_screen_count(self):
        """A leltár EGZAKT számot állít — ezért mozdul minden új képernyőnél."""
        source = (ROOT / INVENTORY_TEST).read_text(encoding="utf-8")
        self.assertRegex(source, r"screenPaths,\s*hasLength\(\d+\)")


class RealBriefCorpusTest(unittest.TestCase):
    """A valódi korpusz MÉRT állítása — hamis riasztás nélkül."""

    def test_no_merged_round_is_retroactively_flagged(self):
        """A `main`-en LÉTEZŐ képernyőjű (tehát lefutott) körök tiszták.

        Ez a fals-pozitív mérce: a naiv szabály 39 briefre lőne, ebből 36
        már zölden merge-elt körre.
        """
        repo = ROOT
        flagged = []
        for brief in sorted((repo / "docs" / "rounds").glob("*.md")):
            try:
                text = brief.read_text(encoding="utf-8")
                findings = brief_lint.lint_text(text, path=brief, repo=repo)
            except Exception:  # noqa: BLE001 — elemezhetetlen brief nem ennek a mércéje
                continue
            if "S9" in _codes(findings):
                flagged.append(brief.name)
        # Minden lelet olyan körre mutasson, ami MÉG NEM futott le: a
        # képernyője ezért hiányzik a fából. Ez a `git ls-files` mércéje.
        tracked = set(
            subprocess.run(
                ["git", "-C", str(repo), "ls-files"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.split()
        )
        for name in flagged:
            brief = repo / "docs" / "rounds" / name
            metadata = brief_lint.load_brief(brief).metadata
            new_screens = [
                path
                for path in metadata.allowed_paths
                if path.startswith("lib/features/")
                and path.endswith("_screen.dart")
                and path not in tracked
            ]
            # A KÖNYVTÁR-előtag ugyanilyen valódi ok (E13-R16/H3): a kör a
            # könyvtár alá teszi az új képernyőt, fájlútvonal nélkül.
            screen_dirs = brief_lint.screen_capable_prefixes(repo, metadata.allowed_paths)
            self.assertTrue(
                new_screens or screen_dirs,
                f"{name} S9-at kapott, de sem új képernyőt nem hoz létre, sem "
                "képernyőt tartható könyvtárat nem enged — hamis riasztás",
            )

    def test_no_done_round_is_flagged(self):
        """A fals-pozitív mérce a sor MERGE-ELT állapotához kötve.

        A `docs/execution/pipeline-queue.tsv` `status` oszlopa a valódi igazság
        arról, hogy egy kör lefutott-e — a `git ls-files` csak közvetett jel. Ha
        egy `done` kör briefje S9-et kap, a szabály visszamenőleg riaszt, tehát
        hamis. MÉRVE 2026-08-25 a könyvtár-előtag kiterjesztés után: **0 `done`
        kör** — a 23 lelet mind `pending` (20, a teljes Ch13 sáv) vagy `hold` (3).
        """
        repo = ROOT
        status = {}
        for line in (repo / "docs" / "execution" / "pipeline-queue.tsv").read_text(
            encoding="utf-8"
        ).splitlines():
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) >= 5:
                status[Path(columns[1]).name] = columns[4].strip()
        offenders = []
        for brief in sorted((repo / "docs" / "rounds").glob("*.md")):
            if status.get(brief.name) != "done":
                continue
            try:
                findings = brief_lint.lint_text(
                    brief.read_text(encoding="utf-8"), path=brief, repo=repo
                )
            except Exception:  # noqa: BLE001 — elemezhetetlen brief nem ennek a mércéje
                continue
            if "S9" in _codes(findings):
                offenders.append(brief.name)
        self.assertEqual([], offenders, "merge-elt kör kapott S9-et — visszamenőleges riasztás")


if __name__ == "__main__":  # pragma: no cover
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
