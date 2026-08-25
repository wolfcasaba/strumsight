"""E13-R17 H3 önjavítás (ADR 0112) — az `S10` shell-destination navigációs őr.

MÉRT GYÖKÉROK (2026-08-25). Az E13-R17 kör az orchestrátor pre-flightjában állt
meg, implementer-dispatch nélkül (`.pipeline/HALTED`, `halt=H3`). A brief §0.0/R3
azt állította, hogy nincs olyan keresztmetszeti teszt, amit a kör pirosra
váltana (*„nincs ilyen"*) — ez **mérve hamis**.

Az önjavító kör SAJÁT reprodukciója (`/tmp/ss-heal-probe-r17`, izolált klón,
`main @ 52df92b3`, `tools/prepare-flutter-generated.sh` után):

    $ ~/flutter/bin/flutter test test/app/navigation/
    00:07 +33: All tests passed!

    # a kör MAGVA szimulálva: a shell HÁROM destination-builderét
    # (`/today`, `/practice`, `/profile`) új hub-képernyőkre átkötve,
    # a `practiceEnabled` kaput VÁLTOZATLANUL hagyva
    $ ~/flutter/bin/flutter test test/app/navigation/
    00:06 +30 -3: Some tests failed.

A három piros cella:

  * `adaptive_scaffold_test.dart` — A1 *„the five destinations render their
    legacy adapter screens"* (`Found 0 widgets with type ProgressScreen`);
  * `adaptive_scaffold_test.dart` — A1 *„each destination path is registered
    exactly once: /practice resolves to the shelled adapter…"*;
  * `tab_state_restoration_test.dart` — *„pushing a sub-route, switching tabs,
    and switching back…"* (`PracticeHubScreen`).

Az őrök a kör `allowed_paths`-án KÍVÜL éltek, a felvételük pedig az
orchestrátornak TÁGÍTÁS, azaz H3 ([L478](../../docs/LESSONS.md)) — a kör
megállt, mielőtt egyetlen sor kód megszületett volna.

A DEFEKT SÁV-SZINTŰ (L482 osztály): a Ch13 sáv húsz hátralévő briefjéből EGY
sem sorolta fel a navigációs őrt, és három (R17, R23, R28) a routert is engedi.
Körönként javítva ez három külön H3 megállás.

A PREDIKÁTUM a fa mérhető igazságához kötött, nem tippelt: a szabály akkor lő,
ha az `allowed_paths` a `lib/app/routing/` forrását engedi (a destination-
builderek és a route-konstansok otthona), a navigációs őr LÉTEZIK a fában, a
kör pedig még nem `done`. MÉRVE a teljes brief-korpuszon (2026-08-25): 18 brief
engedi a routert, ebből 15 `done` — 13 közülük még az őr LÉTREJÖTTE (E13-R08)
előtt merge-elt —, és a szabály pontosan a 3 `pending` briefre lő: `e13-r17`,
`e13-r23`, `e13-r28`. **0 `done` kör** kap leletet.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"

NAV_GUARD_DIR = "test/app/navigation/"
NAV_GUARDS = (
    "test/app/navigation/adaptive_scaffold_test.dart",
    "test/app/navigation/tab_state_restoration_test.dart",
    "test/app/navigation/legacy_route_redirect_test.dart",
)
# A MÉRT eset: az E13-R17 briefjének (a halt pillanatában érvényes)
# `allowed_paths` sorai. Nem kitalált fixture — ezek a `52df92b3` SHA sorai,
# és pontosan ez a lista hiányolta a navigációs őrt.
E13_R17_BRIEF_NAME = "e13-r17-today-practice-profile-hubs.md"
E13_R17_ALLOWED = (
    "lib/features/today/",
    "lib/features/practice_hub/",
    "lib/features/profile_hub/",
    "lib/app/routing/",
    "test/features/today/today_hub_test.dart",
    "test/ui/ui_inventory_test.dart",
)
E13_R17_GATE = ("test/features/today/today_hub_test.dart", "test/ui/ui_inventory_test.dart")
# A MÁSODIK mért alak: a régebbi körök NEM könyvtárat, hanem fájlt engedtek a
# routerből (`e03-r15`, `e06-r25`, …) — a szabálynak erre is állnia kell.
ROUTER_FILE = "lib/app/routing/app_router.dart"
# A FALSZIFIKÁCIÓS eset: az E13-R16 (`done`) routert engedett, de nem
# destination-adaptert írt át — zölden ment át őr nélkül. A `done` szűrő tartja
# vissza a visszamenőleges riasztást.
# A HEAL (E13-R17, 2026-08-25) pillanatában MÉRT, routert engedő Ch13-körök.
# Történeti tény — a teszt a MÉG NYITOTT részhalmazára állít, nem a teljes
# listára, különben minden merge pirosra váltaná a `main`-t.
MEASURED_ROUTING_ROUNDS = (
    "e13-r17-today-practice-profile-hubs.md",
    "e13-r23-song-library-and-setlists.md",
    "e13-r28-unified-library.md",
)
E13_R16_BRIEF_NAME = "e13-r16-launch-and-onboarding.md"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _make_repo(directory: Path, *, guards: tuple[str, ...] = NAV_GUARDS, queue=()) -> Path:
    """Minimális repo-váz: a navigációs őrök a fában, a sor-fájl a státuszokkal."""
    (directory / "docs" / "rounds").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / ".ai").mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    for relative in (*guards, "test/features/today/today_hub_test.dart", "test/ui/ui_inventory_test.dart"):
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("", encoding="utf-8")
    rows = "\n".join(
        f"{round_id}\tdocs/rounds/{brief}\tsonnet-impl\tnincs\t{status}"
        for round_id, brief, status in queue
    )
    (directory / "docs" / "execution" / "pipeline-queue.tsv").write_text(
        rows + "\n" if rows else "", encoding="utf-8"
    )
    return directory


def _brief_text(*, allowed_paths, gate_tests, name=E13_R17_BRIEF_NAME, task="E13-R17") -> str:
    # SZÁNDÉKOSAN nincs `textwrap.dedent` — ugyanaz az ok, mint a
    # `test_brief_ui_inventory_scope.py`-ban: a dedent az interpoláció UTÁN fut,
    # és a beszúrt blokk elrontaná a kód-kerítés behúzását (a brief `B1`-gyel
    # bukna a vizsgált lelet helyett).
    paths = "\n".join(f'  "{path}",' for path in [*allowed_paths, f"docs/rounds/{name}"])
    gates = "[" + ", ".join(f'"{gate}"' for gate in gate_tests) + "]"
    return f"""# {task} — Today, Practice és Profile hubok

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


def _lint(repo: Path, text: str, name=E13_R17_BRIEF_NAME):
    path = repo / "docs" / "rounds" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return brief_lint.lint_text(text, path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _levels(findings, code: str) -> set[str]:
    return {item["level"] for item in findings if item["code"] == code}


def _message(findings, code: str) -> str:
    return next(item["message"] for item in findings if item["code"] == code)


class BriefNavGuardScopeTest(unittest.TestCase):
    """Az S10 mérce-mátrixa. Minden cella a MÉRT E13-R17 esetből származik."""

    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        kwargs.setdefault("queue", (("E13-R17", E13_R17_BRIEF_NAME, "pending"),))
        return _make_repo(Path(temporary.name), **kwargs)

    def test_routing_scope_without_nav_guard_is_a_strict_finding(self):
        """A MÉRT PIROS cella: az E13-R17 briefje a halt pillanatában."""
        repo = self._repo()
        findings = _lint(
            repo, _brief_text(allowed_paths=E13_R17_ALLOWED, gate_tests=E13_R17_GATE)
        )
        self.assertIn("S10", _codes(findings))
        # A szint `strict`: a router-ci a `base` szintet futtatja, tehát a 15
        # már merge-elt, routert engedő brief nem válik visszamenőleg
        # CI-pirossá (ugyanaz az elv, mint az S6/S7/S9 esetében).
        self.assertEqual({"strict"}, _levels(findings, "S10"))
        message = _message(findings, "S10")
        # A lelet NEVEZZE MEG a hiányzó őröket és a router-engedélyt — enélkül a
        # pre-flight teendő nem cselekvőképes.
        self.assertIn("lib/app/routing/", message)
        for guard in NAV_GUARDS:
            self.assertIn(guard, message)

    def test_guard_directory_on_both_lists_is_clean(self):
        """A ZÖLD cella: a `test/app/navigation/` KÖNYVTÁR mindkét listán.

        A router scope-auditja (`security.py::_matches`) előtagként illeszt,
        tehát a könyvtár-engedély a három őr-fájlra szól — a lintnek ugyanezt
        a szemantikát kell használnia, különben a saját mércéjétől eltérőt
        követelne.
        """
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=[*E13_R17_ALLOWED, NAV_GUARD_DIR],
                gate_tests=[*E13_R17_GATE, NAV_GUARD_DIR],
            ),
        )
        self.assertNotIn("S10", _codes(findings))

    def test_explicit_guard_files_on_both_lists_are_clean(self):
        """A fájlonkénti felsorolás ugyanúgy elfogadott, mint a könyvtár."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=[*E13_R17_ALLOWED, *NAV_GUARDS],
                gate_tests=[*E13_R17_GATE, *NAV_GUARDS],
            ),
        )
        self.assertNotIn("S10", _codes(findings))

    def test_allowed_paths_only_still_fires(self):
        """Csak `allowed_paths` kevés: a LOKÁLIS gate futtassa is az őrt.

        Enélkül a törés csak az exact-SHA Full Gate-en derül ki — az E13-R16
        mért ára pontosan ez volt (full-gate 32867296946, majd javító kör).
        """
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=[*E13_R17_ALLOWED, NAV_GUARD_DIR], gate_tests=E13_R17_GATE
            ),
        )
        self.assertIn("S10", _codes(findings))

    def test_gate_tests_only_still_fires(self):
        """Csak `gate_tests` kevés: az implementer hozzá sem nyúlhat az őrhöz.

        Ez a H3 pontos alakja — a mérce futna, de a javítása scope-sértés.
        """
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=E13_R17_ALLOWED, gate_tests=[*E13_R17_GATE, NAV_GUARD_DIR]
            ),
        )
        self.assertIn("S10", _codes(findings))

    def test_router_file_scope_also_fires(self):
        """A régebbi alak: fájlútvonal a routerből, nem könyvtár-előtag."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=("lib/features/today/", ROUTER_FILE), gate_tests=E13_R17_GATE
            ),
        )
        self.assertIn("S10", _codes(findings))
        self.assertIn(ROUTER_FILE, _message(findings, "S10"))

    def test_round_without_routing_scope_does_not_fire(self):
        """A FALSZIFIKÁCIÓS cella: routert nem engedő kör nem kap teendőt.

        Ez a Ch13 sáv többsége (17 brief a 20-ból): nem tudják átkötni a
        destination buildert, tehát a pinnelt típusok nem mozdulhatnak.
        """
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=("lib/features/tuner/", "lib/features/metronome/"),
                gate_tests=E13_R17_GATE,
            ),
        )
        self.assertNotIn("S10", _codes(findings))

    def test_lib_app_prefix_outside_routing_does_not_fire(self):
        """`lib/app/bootstrap/` NEM a router: az E13-R16 ilyet is engedett."""
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=("lib/app/bootstrap/", "lib/app/home_shell.dart"),
                gate_tests=E13_R17_GATE,
            ),
        )
        self.assertNotIn("S10", _codes(findings))

    def test_done_round_is_not_retroactively_flagged(self):
        """A MÉRT falszifikáció: a `done` kör briefje történelem, nem teendő.

        18 brief engedi a routert, ebből 15 `done` — és 13 még azelőtt
        merge-elt, hogy az E13-R08 a navigációs őröket megírta volna. Egy
        `done` körre adott lelet definíció szerint visszamenőleges riasztás.
        """
        repo = self._repo(queue=(("E13-R16", E13_R16_BRIEF_NAME, "done"),))
        findings = _lint(
            repo,
            _brief_text(
                allowed_paths=("lib/app/routing/", "lib/features/onboarding/"),
                gate_tests=E13_R17_GATE,
                name=E13_R16_BRIEF_NAME,
                task="E13-R16",
            ),
            name=E13_R16_BRIEF_NAME,
        )
        self.assertNotIn("S10", _codes(findings))

    def test_missing_guard_in_the_tree_does_not_fire(self):
        """Nemlétező őrt a szabály nem követel — a predikátum a fához kötött."""
        repo = self._repo(guards=())
        findings = _lint(
            repo, _brief_text(allowed_paths=E13_R17_ALLOWED, gate_tests=E13_R17_GATE)
        )
        self.assertNotIn("S10", _codes(findings))


class NavGuardPredicateMatchesTreeTest(unittest.TestCase):
    """A predikátum a VALÓDI őrökhöz van kötve, nem egy beégetett listához.

    Ha egy navigációs őr eltűnik vagy megszűnik típust pinnelni, ez a teszt
    pirosra vált — az `S10` különben némán elavulna, pontosan úgy, ahogy az
    `S9` a KÖNYVTÁR-előtagra vak maradt (L483).
    """

    def test_every_declared_guard_exists(self):
        for guard in brief_lint.NAV_GUARD_TESTS:
            self.assertTrue((ROOT / guard).is_file(), f"{guard} hiányzik a fából")

    def test_every_guard_pins_a_route_to_a_screen_type(self):
        """Mindegyik őr route → képernyő-TÍPUS állítást tartalmaz."""
        for guard in brief_lint.NAV_GUARD_TESTS:
            source = (ROOT / guard).read_text(encoding="utf-8")
            self.assertRegex(
                source,
                r"(find\.byType\(\w+Screen\)|AppRoutes\.\w+:\s*\w+Screen)",
                f"{guard} nem pinnel képernyő-típust — az S10 indoka elavult",
            )

    def test_the_router_source_directory_exists(self):
        self.assertTrue((ROOT / brief_lint.ROUTING_SOURCE_DIR).is_dir())

    def test_the_router_registers_the_shell_destinations(self):
        """A destination-builderek MA is a routerben élnek."""
        source = (ROOT / "lib" / "app" / "routing" / "app_router.dart").read_text(
            encoding="utf-8"
        )
        self.assertIn("StatefulShellBranch", source)
        self.assertIn("AppRoutes.today", source)


class RealBriefCorpusTest(unittest.TestCase):
    """A valódi korpusz MÉRT állítása — hamis riasztás nélkül."""

    @staticmethod
    def _status_map() -> dict[str, str]:
        status: dict[str, str] = {}
        for line in (
            (ROOT / "docs" / "execution" / "pipeline-queue.tsv")
            .read_text(encoding="utf-8")
            .splitlines()
        ):
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) >= 5:
                status[Path(columns[1]).name] = columns[4].strip()
        return status

    @staticmethod
    def _flagged() -> list[Path]:
        flagged = []
        for brief in sorted((ROOT / "docs" / "rounds").glob("*.md")):
            try:
                findings = brief_lint.lint_text(
                    brief.read_text(encoding="utf-8"), path=brief, repo=ROOT
                )
            except Exception:  # noqa: BLE001 — elemezhetetlen brief nem ennek a mércéje
                continue
            if "S10" in _codes(findings):
                flagged.append(brief)
        return flagged

    def test_no_done_round_is_flagged(self):
        """A fals-pozitív mérce a sor MERGE-ELT állapotához kötve."""
        status = self._status_map()
        offenders = [
            brief.name for brief in self._flagged() if status.get(brief.name) == "done"
        ]
        self.assertEqual([], offenders, "merge-elt kör kapott S10-et — visszamenőleges riasztás")

    def test_every_flagged_brief_really_allows_the_router(self):
        """Minden lelet mögött VALÓDI router-engedély áll."""
        for brief in self._flagged():
            metadata = brief_lint.load_brief(brief).metadata
            self.assertTrue(
                brief_lint.routing_scope_paths(metadata.allowed_paths),
                f"{brief.name} S10-et kapott router-engedély nélkül — hamis riasztás",
            )

    def test_the_ch13_routing_rounds_are_covered_after_the_heal(self):
        """A megállt sáv HÁROM routert engedő köre a javítás után tiszta.

        Ez a lelet-eltakarítás mércéje: a hibás mérőműszer javítása és a már
        kimért defekt eltakarítása két külön lépés (L483) — enélkül a halt
        csak korábbra kerülne, nem tűnne el.
        """
        status = self._status_map()
        pending_routing = []
        for brief in sorted((ROOT / "docs" / "rounds").glob("e13-r*.md")):
            if status.get(brief.name) == "done":
                continue
            try:
                metadata = brief_lint.load_brief(brief).metadata
            except Exception:  # noqa: BLE001
                continue
            if brief_lint.routing_scope_paths(metadata.allowed_paths):
                pending_routing.append(brief.name)
        # A HEAL pillanatában (2026-08-25, `main @ 52df92b3`) MÉRT három kör.
        # A lista TÖRTÉNETI tény, nem élő elvárás: ahogy egy kör merge-elődik,
        # kikerül a `pending_routing` halmazból. A korábbi, literál
        # egyenlőség-assert ezért BE VOLT ÉPÍTVE a saját bukásába — az E13-R17
        # merge-ekor (`4235f636` + a sor `done`-ra állítása) a `main` router-CI-je
        # pirosra váltott, és a driver „nem indul piros main fölé" szabálya
        # MEGÁLLÍTOTTA a láncot (chain.log, 2026-08-25T20:25:05). Egy mérce, ami
        # a lánc normál előrehaladásától bukik, nem mérce, hanem időzített akna.
        #
        # A VALÓDI invariáns az utolsó assert: EGYETLEN nyitott, routert engedő
        # Ch13-brief sem maradhat őr nélkül — ez merge-től független, és egy
        # ÚJONNAN felvett routert engedő kört is elkap. A trió-assert ezt
        # egészíti ki azzal, hogy a mért három kör közül a MÉG NYITOTTAK
        # továbbra is routert engedő körként látszanak (nem veszítették el a
        # jogosultságukat egy csendes brief-átíráskor).
        still_open = sorted(
            name for name in MEASURED_ROUTING_ROUNDS if status.get(name) != "done"
        )
        self.assertEqual(
            still_open,
            sorted(set(pending_routing) & set(MEASURED_ROUTING_ROUNDS)),
            "a HEAL-kor mért, MÉG NYITOTT routert engedő körök valamelyike "
            "elvesztette a router-engedélyét a briefjében",
        )
        self.assertEqual([], [brief.name for brief in self._flagged()])


if __name__ == "__main__":  # pragma: no cover
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
