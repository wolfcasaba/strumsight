"""S11/S14 — a képernyő-cserét ÚTVONAL-SZINTEN is mérni kell.

MÉRT vakfolt (E16-R02 / 3. H3, 2026-09-03, `.pipeline/halt-detail-E16-R02.md`
§3). A kör az `/profile/progress` útvonalat kötötte volna át a legacy
`ProgressScreen`-ről a `ProgressDashboardScreen`-re, és ezt a cserét egy
briefen KÍVÜL élő teszt pinnelte (`test/features/today/hub_navigation_test.dart`
:247, shell-ON routeren, `find.byType(ProgressScreen)`). Pont ez az S11
lelet-osztálya — a `brief-lint` mégis „nincs lelet"-et adott, és a kör
harmadszor is H3-ban állt meg.

A mért ok: az `owned_existing_screens()` a kör által átírható képernyők
halmazát KIZÁRÓLAG az `allowed_paths`-beli `*_screen.dart` fájlokból és
`lib/…/` könyvtár-előtagokból vezette le. Az E16-R02 listáján egyik sincs
(`sed -n '/```ai-router/,/```/p' <brief> | grep -cE '_screen\\.dart"|lib/[^"]*/"'`
→ **0**), ezért a halmaz ÜRES lett, és az S11 meg az S14 strukturálisan NÉMA
maradt. A csere ugyanis nem fájl-szinten történik: a képernyő forrásfájlja
érintetlen (sőt, a kör TILOS zónájában van), csak az `app_router.dart`
`GoRoute.builder`-e mutat máshová.

## A bemenet RÖGZÍTETT pillanatkép (ADR 0112 önjavító kör, 4. H3, 2026-09-03)

A guard eredetileg az ÉLŐ fát és az ÉLŐ briefet olvasta — és ezzel a saját köre
MUNKÁJÁNAK HIÁNYÁT pinnelte. Ettől a kör **sikere** vitte pirosra a Router CI-t:
a kör terméke hibátlan volt (célzott kapu 21/21 zöld, Full Gate zöld a
`c2b1362a` SHA-n), mégis a saját őre zárta ki a merge-ből. Három cella bukott
(`test_the_outside_pin_is_named_by_the_rule`,
`test_the_revised_brief_leaves_no_route_level_pin_open`,
`test_the_rule_is_silent_for_routes_the_brief_never_names`), és a további kettő
ugyanezen az élen állt.

A javítás: a szabály-viselkedést mérő cellák a `fixtures/e16_r02_route_level_swap/`
alatti, szó szerint másolt halt-pillanatból dolgoznak
(`origin/main @ 4fffa3f1`, ahol ez a fájl mérve zöld volt). A fixture eredete,
előállítása és a „miért nem gyengítés" mérése: a fixture `PROVENANCE.md`-je.

Ez a teszt a halt tényleges adatával mér — nem kitalált fixture-rel —, és a
`brief-lint` javítása előtt piros.
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "tests" / "fixtures" / "e16_r02_route_level_swap"
BRIEF_RELATIVE = "docs/rounds/e16-r02-progress-projection-and-router-placeholders.md"
ROUTER = "lib/app/routing/app_router.dart"
SWAPPED_SCREEN = "lib/features/progress/screens/progress_screen.dart"

# A halt §1/§2 táblájában MÉRT pin-halmaz. Az első három a `/progress` →
# `/profile/progress` láncon jut a képernyőhöz (ezeket a cserének mérnie kell),
# a másik kettő a routertől függetlenül építi (`home: ProgressScreen()`, illetve
# a képernyő saját unit-tesztje) — azokat egy builder-átkötés nem érinti.
ROUTE_PINS = (
    "test/app/offline_network_guard_test.dart",
    "test/app/routing/app_router_test.dart",
    "test/features/today/hub_navigation_test.dart",
)
NON_ROUTE_PINS = (
    "test/core/screen_size_guard_test.dart",
    "test/features/progress/progress_screen_test.dart",
)

# A router import-jaiból a `_router_screen_files()` KIZÁRÓLAG az útvonalat
# használja; a tartalmat sosem olvassa, csak az `is_file()`-t nézi.
SCREEN_IMPORT_PREFIX = "package:strumsight/"


def _brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", ROOT / "tools" / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _materialise_fixture(destination: Path) -> None:
    """A `.txt` pillanatképeket az EREDETI fájlnevekre írja ki.

    A képernyő-fájlokat a fixture routerének saját import-listájából, gépiesen
    hozza létre (üres fájlként) — kitalált tartalom nincs benne.
    """
    for source in sorted(FIXTURE.rglob("*.txt")):
        relative = source.relative_to(FIXTURE).as_posix()
        assert relative.endswith(".txt")
        target = destination / relative[: -len(".txt")]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())

    router_text = (destination / ROUTER).read_text(encoding="utf-8")
    lint = _brief_lint()
    for match in lint.SCREEN_IMPORT.finditer(router_text):
        uri = match.group("uri")
        # Ugyanaz a feloldás, amit a `_router_screen_files()` végez — a fixture
        # nem tippel, a router saját import-alakját követi.
        if uri.startswith(SCREEN_IMPORT_PREFIX):
            screen = destination / "lib" / uri[len(SCREEN_IMPORT_PREFIX) :]
        elif uri.startswith("package:") or uri.startswith("dart:"):
            continue
        else:
            screen = (destination / ROUTER).parent / uri
        if screen.exists():
            continue
        screen.parent.mkdir(parents=True, exist_ok=True)
        screen.touch()


class RouteLevelScreenSwapTest(unittest.TestCase):
    """A halt-pillanat rögzített fáján mér — ld. az osztály-doksit."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._workspace = tempfile.TemporaryDirectory()
        cls.repo = Path(cls._workspace.name)
        _materialise_fixture(cls.repo)
        cls.brief = cls.repo / BRIEF_RELATIVE

    @classmethod
    def tearDownClass(cls) -> None:
        cls._workspace.cleanup()

    def setUp(self) -> None:
        self.lint = _brief_lint()
        self.text = self.brief.read_text(encoding="utf-8")
        self.allowed = list(load_brief_metadata(self.brief).allowed_paths)
        # A halt pillanatában érvényes lista: a pinnelő tesztek MÉG nincsenek
        # rajta — ezt az állapotot kell a lintnek kimondania.
        self.pre_revision = [
            path for path in self.allowed if not any(path == pin for pin in ROUTE_PINS)
        ]

    def test_the_fixture_is_the_measured_halt_moment(self) -> None:
        """Ha a pillanatkép elcsúszik, a többi cella mérése értelmét veszti."""
        self.assertTrue(
            (self.repo / ROUTER).is_file() and (self.repo / BRIEF_RELATIVE).is_file(),
            "a fixture materializálása nem írta ki a router forrását és a briefet",
        )
        self.assertIn(
            "const ProgressScreen()",
            (self.repo / ROUTER).read_text(encoding="utf-8"),
            "a halt-pillanat premisszája, hogy a router MÉG a legacy képernyőt "
            "építi; ha a pillanatkép ezt nem hordozza, újra kell mérni, nem "
            "kikapcsolni (PROVENANCE.md)",
        )
        for pin in ROUTE_PINS + NON_ROUTE_PINS:
            self.assertTrue(
                (self.repo / pin).is_file(),
                f"a pillanatképből hiányzik a MÉRT pin: {pin}",
            )

    def test_the_replaced_screen_is_in_scope_through_the_router(self) -> None:
        screens = self.lint.owned_existing_screens(self.repo, self.pre_revision, self.text)

        self.assertIn(
            SWAPPED_SCREEN,
            screens,
            "a kör az `app_router.dart` buildert köti át a `/profile/progress` "
            "útvonalon, tehát a legacy képernyő a csere hatókörében van — a "
            "fájl-tulajdonlásból ez sosem látszik (a fájl a TILOS zónában van)",
        )

    def test_the_outside_pin_is_named_by_the_rule(self) -> None:
        screens = self.lint.owned_existing_screens(self.repo, self.pre_revision, self.text)
        require = self.lint._route_pin_requirement(
            self.lint.route_level_swapped_screens(self.repo, self.pre_revision, self.text),
            self.lint.file_owned_screens(self.repo, self.pre_revision),
        )

        pins = self.lint.outside_screen_pins(
            self.repo, screens, self.pre_revision, [], require
        )

        self.assertEqual(
            pins.get(SWAPPED_SCREEN),
            sorted(ROUTE_PINS),
            "az S11 PONTOSAN azokat a briefen kívüli teszteket sorolja, "
            "amelyek az átkötött útvonalon jutnak a képernyőhöz",
        )

    def test_pins_that_never_consult_the_router_stay_out(self) -> None:
        screens = self.lint.owned_existing_screens(self.repo, self.pre_revision, self.text)
        require = self.lint._route_pin_requirement(
            self.lint.route_level_swapped_screens(self.repo, self.pre_revision, self.text),
            self.lint.file_owned_screens(self.repo, self.pre_revision),
        )

        listed = self.lint.outside_screen_pins(
            self.repo, screens, self.pre_revision, [], require
        ).get(SWAPPED_SCREEN, [])

        for pin in NON_ROUTE_PINS:
            self.assertNotIn(
                pin,
                listed,
                f"{pin} a képernyőt közvetlenül építi, egy `GoRoute.builder` "
                "átkötése nem viszi pirosra — felsorolni hamis riasztás",
            )

    def test_the_rule_is_silent_when_the_router_is_out_of_scope(self) -> None:
        without_router = [path for path in self.allowed if path != ROUTER]

        self.assertEqual(
            self.lint.route_level_swapped_screens(self.repo, without_router, self.text),
            {},
            "a router forrása nélkül a kör egyetlen buildert sem tud átkötni",
        )

    def test_the_rule_is_silent_for_routes_the_brief_never_names(self) -> None:
        swapped = self.lint.route_level_swapped_screens(self.repo, self.allowed, self.text)

        self.assertEqual(
            sorted(swapped),
            [SWAPPED_SCREEN],
            "a router 45 képernyőt köt be; a brief által MEGNEVEZETT útvonalak "
            "szűrője nélkül a lelet használhatatlan zaj lenne",
        )

    def test_file_level_ownership_keeps_working_without_a_brief_text(self) -> None:
        """A `brief_text` nélküli, eredeti ág változatlan (nincs regresszió)."""
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            screen = "lib/features/tutor/presentation/screens/tutor_home_screen.dart"
            (repo / screen).parent.mkdir(parents=True)
            (repo / screen).write_text("class TutorHomeScreen {}\n", encoding="utf-8")

            self.assertEqual(self.lint.owned_existing_screens(repo, [screen]), [screen])

    def test_the_revised_brief_leaves_no_route_level_pin_open(self) -> None:
        """A lint javítása és a brief revíziója EGYÜTT zárja a halt-ot."""
        findings = self.lint.lint_text(self.text, path=self.brief, repo=self.repo)
        screen_findings = [
            finding for finding in findings if finding["code"] in {"S11", "S14"}
        ]

        self.assertEqual(
            screen_findings,
            [],
            "a §0.0.J revízió után minden útvonal-szintű pin a kör "
            "`allowed_paths`-án ÉS `gate_tests`-én van",
        )


if __name__ == "__main__":
    unittest.main()
