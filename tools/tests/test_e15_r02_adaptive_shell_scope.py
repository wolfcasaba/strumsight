"""Regression guard for the E15-R02 self-heal (ADR 0112, halt H3, 2026-08-28).

MÉRT GYÖKÉROK. Az E15-R02 kör (`adaptiveShellEnabled: nonProd`) az
orchestrátor pre-flightjában állt meg, implementer-dispatch NÉLKÜL
(`.pipeline/HALTED`, `halt=H3`, `halted_at=2026-08-28T18:47:43+00:00`).

A `lib/app/config/app_config.dart` `appConfigProvider`-ének ALAPÉRTELMEZETT
értéke maga is `FeatureFlags.forEnvironment(AppEnvironment.development, …)`,
ezért a `forEnvironment` gyár egyetlen sorának átbillentése MINDEN olyan
widget-teszt viselkedését megváltoztatja, amely a valódi `StrumSightApp`-ot
pumpálja és nem írja felül az `appConfigProvider`-t: a belépési pont
`/live` → `/today`, és a tizenegy `legacyRedirects` él aktiválódik. A brief §4
`allowed_paths`-a ebből TIZENHAT tesztfájlt nem engedett, a lista tágítása
pedig nem orchestrátor-hatáskör (ADR 0087 §2) — innen a H3.

Az önjavító kör FÜGGETLENÜL reprodukálta a mérést (`main @ e65b1738` klón,
`tools/prepare-flutter-generated.sh` után, a flip egyetlen `sed`-del):

    ~/flutter/bin/flutter test --reporter compact      # a TELJES suite
    # flippel:      +7288 ~1 -68   (68 bukás, 24 fájlban)
    # flip nélkül:  +7341 ~1 -15   (15 bukás, 5 golden-fájlban)

A két futás különbsége a flag oksági hatósugara: **53 bukás 19 fájlban**. A
flip nélkül is piros 15 cella mind `Pixel test failed, 0.00%, 1px diff` alakú,
öt golden-fájlban — ez a MÉRT ARM↔x86 raszter-drift (L516, ADR 0426), a kapu
x86 architektúráján zöld, tehát NEM e kör hatása.

Ez az őr a VALÓDI, commitolt briefet hajtja a VALÓDI scope-auditon keresztül
(`tools.ai_router.security.audit_scope` — pontosan az a függvény, amit a
`tools/model-router.py` futtat a `sonnet-impl` körre), így a regresszió
mindkét irányban itt bukik meg először:

  * a 19 mért fájl mindegyike a kör scope-jában kell legyen (a halt oka
    megszűnt), és a lokális kapuban (`gate_tests`) is futnia kell — enélkül
    a törés csak az exact-SHA Full Gate-en derülne ki;
  * a nem érintett szomszédok VÁLTOZATLANUL scope-on kívül maradnak — a
    javítás pontosan a mért fájlokat engedi, nem a `test/features/live/`
    vagy a `test/features/settings/` KÖNYVTÁRAT (a blanket-tágítás ugyanaz
    a hiba lenne, csak fordított előjellel).

A predikátum a fa mérhető igazságához kötött: ha az `appConfigProvider`
alapértéke egyszer megszűnik a `forEnvironment`-ből jönni, a mért hatósugár
indoka elavul — azt a `MeasuredBlastRadiusPremiseTest` fogja pirosra váltani,
nem egy néma feltevés.
"""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.security import audit_scope, capture_workspace_manifest

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e15-r02-adaptive-shell-default-and-overflow-fixes.md"

# A MÉRT hatósugár: a `flutter test` két teljes futásának különbsége
# (2026-08-28, önjavító kör). Nem kitalált fixture — ezek a nyers futás
# bukó fájljai, a bukó cellák számával.
MEASURED_IMPACTED_TESTS: tuple[tuple[str, int], ...] = (
    ("test/features/live/live_stage_test.dart", 11),
    ("test/features/live/live_mic_release_test.dart", 6),
    ("test/features/settings/consent_center_test.dart", 5),
    ("test/features/live/live_screen_test.dart", 5),
    ("test/features/settings/settings_account_test.dart", 3),
    ("test/features/live/live_background_test.dart", 3),
    ("test/features/live/live_announcement_throttle_test.dart", 3),
    ("test/core/screen_size_guard_test.dart", 3),
    ("test/features/settings/settings_persistence_failure_test.dart", 2),
    ("test/features/live/live_lab_panel_test.dart", 2),
    ("test/app/routing/shell_lifecycle_test.dart", 2),
    ("test/widget_test.dart", 1),
    ("test/features/settings/lab_mode_toggle_test.dart", 1),
    ("test/features/library/library_test.dart", 1),
    ("test/features/analyze/cancel_on_leave_test.dart", 1),
    ("test/features/analyze/analyze_screen_test.dart", 1),
    ("test/features/live/expected_hint_cleared_on_live_test.dart", 1),
    ("test/app/navigation/adaptive_scaffold_test.dart", 1),
    ("test/app/routing/onboarding_first_win_test.dart", 1),
)

# A javítás NEM könyvtárat enged: ezek a mért fájlok közvetlen szomszédai,
# ugyanabban a könyvtárban, a flip után is zölden — scope-on kívül kell
# maradniuk.
SIBLINGS_OUT_OF_SCOPE = (
    "test/features/live/live_widgets_test.dart",
    "test/features/settings/settings_sync_test.dart",
    "test/app/routing/route_guards_test.dart",
)

# A D8 (ADR 0467) prózajavítás helye és a hozzá tartozó gépi mérce.
REGISTRY_SOURCE = "lib/core/feature_flags/feature_flag_registry.dart"
REGISTRY_AUDIT_TEST = "test/tooling/feature_flag_audit_test.dart"
# Az S11-maradék: az E15-R01 PNG-mentes variáns-mátrixa a `LiveScreen`-t
# méri, a kör pedig a `live_screen.dart`-ot írja át.
THEME_ADOPTION_TEST = "test/ui/goldens/e15_r01_theme_adoption_test.dart"


def _protected_paths() -> tuple[str, ...]:
    router_toml = (REPO_ROOT / ".ai" / "router.toml").read_text(encoding="utf-8")
    inside = False
    paths: list[str] = []
    for line in router_toml.splitlines():
        stripped = line.strip()
        if stripped.startswith("protected_paths"):
            inside = True
            continue
        if inside:
            if stripped.startswith("]"):
                break
            paths.append(stripped.strip('",'))
    return tuple(path for path in paths if path)


class E15R02ScopeCoversTheMeasuredBlastRadiusTest(unittest.TestCase):
    """A kör scope-ja lefedi a mért 19 fájlt — és csak azokat."""

    def _repo(self) -> tuple[Path, object]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "heal@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Heal Test"], cwd=root, check=True)
        (root / ".gitignore").write_text("build/\n", encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root, capture_workspace_manifest(root)

    def _audit(self, relative: str):
        root, baseline = self._repo()
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("// adapted to the /today entry location\n", encoding="utf-8")
        return audit_scope(
            root,
            allowed_paths=load_brief(BRIEF).metadata.allowed_paths,
            protected_paths=_protected_paths(),
            baseline=baseline,
        )

    def test_every_measured_impacted_test_is_in_scope(self) -> None:
        for relative, failures in MEASURED_IMPACTED_TESTS:
            with self.subTest(path=relative, failures=failures):
                audit = self._audit(relative)
                self.assertTrue(
                    audit.ok,
                    f"{relative} ({failures} mért bukás) az E15-R02 scope-ján KÍVÜL van "
                    f"— ez volt a H3 halt oka; violations={audit.violations}",
                )

    def test_the_registry_prose_fix_is_in_scope(self) -> None:
        """ADR 0467 D8: a `killSwitchPath` szövege a D1 után hamis lenne."""
        audit = self._audit(REGISTRY_SOURCE)
        self.assertTrue(audit.ok, f"violations={audit.violations}")

    def test_siblings_stay_out_of_scope(self) -> None:
        """A javítás a MÉRT fájlokat engedi, nem a könyvtárukat."""
        for relative in SIBLINGS_OUT_OF_SCOPE:
            with self.subTest(path=relative):
                audit = self._audit(relative)
                self.assertFalse(
                    audit.ok,
                    f"{relative} bekerült a scope-ba — a javítás könyvtárat engedett, "
                    "nem a mért fájlokat",
                )
                self.assertIn(f"path outside allowed scope: {relative}", audit.violations)


class E15R02GateRunsTheMeasuredTestsTest(unittest.TestCase):
    """A lokális kapu FUTTATJA is, amit a scope enged.

    Csak `allowed_paths` kevés: a javítás bizonyítéka a kör kapuja, és az
    E13-R16 mért ára pontosan az volt, hogy a törés csak a Full Gate-en
    derült ki (`S10`/`S12` ugyanezt a rést zárja a brief-linten).
    """

    @staticmethod
    def _gate_tests() -> tuple[str, ...]:
        return tuple(load_brief(BRIEF).metadata.gate_tests)

    def test_every_measured_impacted_test_is_in_the_gate(self) -> None:
        gate = self._gate_tests()
        for relative, _ in MEASURED_IMPACTED_TESTS:
            with self.subTest(path=relative):
                self.assertTrue(
                    any(relative == entry or relative.startswith(entry) for entry in gate),
                    f"{relative} nincs a `gate_tests`-ben — a kör nem futtatná a mércéjét",
                )

    def test_the_s11_leftover_and_the_flag_audit_are_in_the_gate(self) -> None:
        gate = self._gate_tests()
        for relative in (THEME_ADOPTION_TEST, REGISTRY_AUDIT_TEST):
            with self.subTest(path=relative):
                self.assertIn(relative, gate)

    def test_the_gate_command_mirrors_the_gate_tests(self) -> None:
        """A §7 parancssor a FUTTATHATÓ mérce (AGENTS.md §12) — ne csússzon szét.

        Ugyanaz az invariáns, amit az `S12` brief-lint szabály őriz; itt a
        kör SAJÁT briefjére, a mért listával együtt.
        """
        text = BRIEF.read_text(encoding="utf-8")
        command = next(
            line for line in text.splitlines() if line.startswith("tools/round-gate.sh ")
        )
        arguments = command.split()[1:]
        self.assertEqual(list(self._gate_tests()), arguments)


class MeasuredBlastRadiusPremiseTest(unittest.TestCase):
    """A mért hatósugár PREMISSZÁI ma is állnak a fában.

    Ha ezek elmozdulnak, a fenti fájllista elavul — és jobb, ha ez itt válik
    pirosra, mint egy újabb H3 halton.
    """

    def test_the_app_config_default_comes_from_for_environment(self) -> None:
        source = (REPO_ROOT / "lib" / "app" / "config" / "app_config.dart").read_text(
            encoding="utf-8"
        )
        self.assertIn("FeatureFlags.forEnvironment(", source)
        self.assertIn("AppEnvironment.development", source)

    def test_the_flag_still_drives_the_entry_location(self) -> None:
        source = (REPO_ROOT / "lib" / "app" / "routing" / "app_router.dart").read_text(
            encoding="utf-8"
        )
        self.assertIn("adaptiveShellEnabled", source)
        self.assertIn("AppRoutes.today", source)

    def test_every_measured_test_file_exists(self) -> None:
        for relative, _ in MEASURED_IMPACTED_TESTS:
            with self.subTest(path=relative):
                self.assertTrue((REPO_ROOT / relative).is_file(), f"{relative} hiányzik a fából")

    def test_the_siblings_used_for_falsification_exist(self) -> None:
        for relative in SIBLINGS_OUT_OF_SCOPE:
            with self.subTest(path=relative):
                self.assertTrue((REPO_ROOT / relative).is_file(), f"{relative} hiányzik a fából")


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
