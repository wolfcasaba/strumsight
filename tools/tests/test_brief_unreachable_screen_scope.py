"""Az `S14` szabály — a MÉRT `unreachable` verdiktű képernyőt migráltató brief.

MÉRT GYÖKÉROK (E15-R07 / H2, 2026-08-29). Az `E15-R07` briefje a Practice
Generator hat képernyőjének Ch15 design-migrációját írta elő, két tényállítással
a §0.0-ban: „az `E15-R02` óta a Practice Generator flag BE van kapcsolva az
előnézeti/nem-production buildekben" és „a terv-képernyők a felhasználó útjába
kerültek". A kör pre-flightja MINDKETTŐT hamisnak mérte (`main @ c2c38014`):

  * `lib/app/config/feature_flags.dart:84` — a NEM-production profil is explicit
    `practiceGeneratorEnabled: false`; a fában sehol nincs `true` értékadás;
  * a hat képernyő TÍPUSÁRA nulla hivatkozás van a saját fájljukon kívül, és a
    `lib/app/routing/**` egyszer sem említi a feature-t.

A mérés nem volt új: az `E15-R03` (ADR 0471) MÁR elvégezte, és a merge-elt
`docs/ui/retirement-plan.md` §6 táblája mind a hatra `Reachable = no`,
`Verdict = unreachable`, `Owner round = —` sort ír, a §3.2 pedig kimondja:
„Neither is a Chapter 15 design-migration concern (design tokens are moot on a
screen nobody can open) … Owner: a future scoped round, unscheduled."

A brief tehát egy MÁR MEGHOZOTT, merge-elt döntéssel ütközött — a lánc H2-vel
állt meg, egy teljes orchestrátor-session árán, mielőtt egyetlen sor kód
megszületett volna. A hibaosztály ÁLTALÁNOS: minden Ch15 migrációs brief előre
lett megírva (2026-08-28, `main @ 4cb32eb0`), a visszavonási terv verdiktjei
viszont a sáv KÖZBEN landoltak — bármelyik előre megírt brief hivatkozhat olyan
képernyőre, amit a terv azóta `unreachable`-nek mért.

Az `S14` ezt a fa mérhető igazságához köti: a kör `allowed_paths`-ából
összegyűjti a MÁR LÉTEZŐ képernyőket, és leletet ad arra, amelyiket a merge-elt
visszavonási terv `unreachable`-nek méri — KIVÉVE, ha maga a brief kimondja a
verdiktet (a `unreachable` szó a szövegben), mert akkor a kör tudatosan az
elérhetetlen képernyőről szól (bekötés vagy visszavonás), nem vakon migrálja.
"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"

# A MÉRT eset magja, a `docs/ui/retirement-plan.md` §6 sorainak alakjával.
UNREACHABLE_SCREEN = (
    "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart"
)
UNREACHABLE_TYPE = "PlanSetupScreen"
REACHABLE_SCREEN = "lib/features/onboarding/screens/onboarding_screen.dart"
REACHABLE_TYPE = "OnboardingScreen"
OWN_TEST = "test/features/practice_generator/presentation/plan_setup_screen_test.dart"
BRIEF_NAME = "e15-r07-practice-generator-migration.md"
ROUND_ID = "E15-R07"

# A merge-elt terv MÉRT sorai (E15-R03, ADR 0471) — a `Verdict` az 5. oszlop.
RETIREMENT_PLAN = f"""# Legacy screen retirement plan

## 6. Full per-screen table (all 96, machine-measured)

| File | Type | Reachable | Gated | Verdict | Owner round | ADR | Note |
|---|---|---|---|---|---|---|---|
| `{UNREACHABLE_SCREEN}` | `{UNREACHABLE_TYPE}` | no | no | unreachable | — | — | \
Practice Generator has no route and no construction site anywhere in lib/. |
| `{REACHABLE_SCREEN}` | `{REACHABLE_TYPE}` | yes | no | migrate | {ROUND_ID} | — | \
Legacy, reachable — Ch15 design-system migration. |
"""


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


def _make_repo(directory: Path, *, status: str = "pending", plan: bool = True) -> Path:
    (directory / "docs" / "rounds").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "ui").mkdir(parents=True, exist_ok=True)
    (directory / ".ai").mkdir(parents=True, exist_ok=True)
    (directory / ".ai" / "router.toml").write_text(
        '[security]\nhigh_risk_path_fragments = ["auth"]\n', encoding="utf-8"
    )
    for screen, type_name in ((UNREACHABLE_SCREEN, UNREACHABLE_TYPE), (REACHABLE_SCREEN, REACHABLE_TYPE)):
        path = directory / screen
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"class {type_name} extends StatelessWidget {{}}\n", encoding="utf-8")

    own = directory / OWN_TEST
    own.parent.mkdir(parents=True, exist_ok=True)
    own.write_text("void main() {}\n", encoding="utf-8")

    if plan:
        (directory / "docs" / "ui" / "retirement-plan.md").write_text(
            RETIREMENT_PLAN, encoding="utf-8"
        )

    (directory / "docs" / "execution" / "pipeline-queue.tsv").write_text(
        f"{ROUND_ID}\tdocs/rounds/{BRIEF_NAME}\tsonnet-impl\tnincs\t{status}\n", encoding="utf-8"
    )
    return directory


def _brief_text(*, allowed_paths, names_the_verdict: bool = False) -> str:
    paths = "\n".join(f'  "{path}",' for path in [*allowed_paths, f"docs/rounds/{BRIEF_NAME}"])
    verdict_line = (
        "A terv szerint a batch képernyői `unreachable`-ek — a kör tárgya épp a "
        "bekötésük.\n"
        if names_the_verdict
        else ""
    )
    return f"""# {ROUND_ID} — Practice Generator képernyők migrálása

A mérce artefaktuma: `tools/round-gate.sh`.

{verdict_line}
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


class BriefUnreachableScreenScopeTest(unittest.TestCase):
    def _repo(self, **kwargs) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return _make_repo(Path(temporary.name), **kwargs)

    def test_scoping_an_unreachable_screen_is_a_finding(self) -> None:
        repo = self._repo()
        findings = _lint(repo, _brief_text(allowed_paths=(UNREACHABLE_SCREEN, OWN_TEST)))
        self.assertIn(
            "S14",
            _codes(findings),
            "a merge-elt terv `unreachable` verdiktje ellen dolgozó brief némán "
            "maradt — ez pontosan az E15-R07/H2 halt-osztálya, egy teljes "
            "orchestrátor-session árán",
        )
        message = _message(findings, "S14")
        self.assertIn(UNREACHABLE_SCREEN, message)
        self.assertNotIn(REACHABLE_SCREEN, message, "a `migrate` verdiktű képernyő nem lelet")

    def test_the_directory_prefix_form_is_measured_too(self) -> None:
        # A scope-audit szemantikája ELŐTAG, tehát a könyvtár-engedély is a
        # képernyőre szól (ugyanaz a mért vakfolt, mint az S9/S11 esetében).
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(allowed_paths=("lib/features/practice_generator/", OWN_TEST)),
        )
        self.assertIn("S14", _codes(findings))
        self.assertIn(UNREACHABLE_SCREEN, _message(findings, "S14"))

    def test_a_reachable_screen_alone_is_not_a_finding(self) -> None:
        repo = self._repo()
        findings = _lint(repo, _brief_text(allowed_paths=(REACHABLE_SCREEN, OWN_TEST)))
        self.assertNotIn("S14", _codes(findings))

    def test_a_brief_that_names_the_verdict_is_not_a_finding(self) -> None:
        # A kör tudatosan az elérhetetlen képernyőről szól (bekötés/visszavonás,
        # ADR 0471 D5/D7) — az `S14` a VAK migrációt fogja meg, nem a döntést.
        repo = self._repo()
        findings = _lint(
            repo,
            _brief_text(allowed_paths=(UNREACHABLE_SCREEN, OWN_TEST), names_the_verdict=True),
        )
        self.assertNotIn("S14", _codes(findings))

    def test_a_done_round_is_never_flagged_retroactively(self) -> None:
        repo = self._repo(status="done")
        findings = _lint(repo, _brief_text(allowed_paths=(UNREACHABLE_SCREEN, OWN_TEST)))
        self.assertNotIn(
            "S14",
            _codes(findings),
            "egy már merge-elt kör visszamenőleges riasztást kapott — ugyanaz a "
            "hamis-pozitív osztály, amit az S5/S7/S10/S11 `done` szűrője zár ki",
        )

    def test_without_the_retirement_plan_the_rule_is_silent(self) -> None:
        # A terv az `E15-R03`-ban született; ami előtte készült, arról nincs mit
        # mérni — a hiányzó forrás nem lehet lelet.
        repo = self._repo(plan=False)
        findings = _lint(repo, _brief_text(allowed_paths=(UNREACHABLE_SCREEN, OWN_TEST)))
        self.assertNotIn("S14", _codes(findings))


class RepositoryTruthTest(unittest.TestCase):
    """A VALÓDI repó invariánsai: a mért halt nem indulhat újra változatlanul.

    A H2 halt PONTOS alakja az volt, hogy a kör hatóköréből MINDEN képernyő
    `unreachable` — a körnek nulla végrehajtható tárgya maradt, és a feloldás
    egy emberi termékdöntésen múlt (ADR 0471 D5/D7). A RÉSZLEGES túl-scope
    (a batch nagyobb része `migrate`, egy-két sora `unreachable`) NEM ez az
    osztály: az a kör végrehajtható, csak a listáját kell szűkíteni — erre az
    `S14` `strict` lelete a pre-flight teendője, nem lánc-megállás.

    MÉRVE (`main @ c2c38014`, a 81 leletes brief korpuszán): az `S14` négy
    briefet talál — az `E15-R07` (6/6 `unreachable`, EZ volt a halt) és három
    RÉSZLEGES (`E15-R08`: 1, `E15-R10`: 3, `E15-R11`: 1 képernyő), amelyek
    végrehajthatók maradnak.
    """

    def _scoped_screens(self, brief_path: Path) -> list[str]:
        metadata = brief_lint.load_brief(brief_path).metadata
        return brief_lint.owned_existing_screens(ROOT, metadata.allowed_paths)

    def test_the_merged_retirement_plan_is_parseable(self) -> None:
        unreachable = brief_lint.unreachable_screens(ROOT)
        self.assertIn(
            UNREACHABLE_SCREEN,
            unreachable,
            "a merge-elt visszavonási terv §6 táblája nem parse-olható — az "
            "S14 forrása némán elnémulna",
        )

    def test_the_halted_round_is_not_dispatchable_unchanged(self) -> None:
        statuses = {
            round_id.upper(): status for round_id, _brief, status in brief_lint.queue_rows(ROOT)
        }
        self.assertNotIn(
            statuses.get(ROUND_ID, ""),
            {"pending", "prepared"},
            f"a(z) {ROUND_ID} sora újra végrehajtható, pedig a hatóköréből MINDEN "
            "képernyő `unreachable` — a lánc ugyanazzal a H2-vel állna meg "
            "(2026-08-29)",
        )

    def test_no_dispatchable_round_has_a_fully_unreachable_scope(self) -> None:
        unreachable = brief_lint.unreachable_screens(ROOT)
        self.assertTrue(unreachable, "nincs mit mérni: a terv nem adott `unreachable` sort")
        offenders: dict[str, list[str]] = {}
        for round_id, brief, status in brief_lint.queue_rows(ROOT):
            if status not in {"pending", "prepared"}:
                continue
            brief_path = ROOT / brief
            if not brief_path.is_file():
                continue
            try:
                screens = self._scoped_screens(brief_path)
            except Exception:  # noqa: BLE001 — a metaadat-hibát más teszt méri
                continue
            if screens and all(screen in unreachable for screen in screens):
                offenders[round_id] = screens
        self.assertEqual(
            {},
            offenders,
            "egy VÉGREHAJTHATÓ (pending/prepared) kör hatóköréből MINDEN képernyőt "
            "elérhetetlennek mér a merge-elt terv — a körnek nulla végrehajtható "
            "tárgya van, a lánc H2-vel áll meg rajta (E15-R07, 2026-08-29)",
        )


if __name__ == "__main__":
    unittest.main()
