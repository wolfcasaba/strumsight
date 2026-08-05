"""Engine-profile switcher tests (ADR 0140).

Az implementer-motorok kvótája külön-külön merül ki (a Terra 9%-on,
2026-08-05), ezért a váltásnak azonnalinak ÉS visszavonhatónak kell lennie.
A profilok egymás mellett élnek; a váltás egyetlen gitignore-olt fájl, nem
konfiguráció-átírás — így egyik motor beállítása sem vész el.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "engine-profile.sh"
REGISTRY = ROOT / "docs" / "execution" / "engine-registry.tsv"
DRIVER = ROOT / "tools" / "round-pipeline.sh"


def registry_rows():
    rows = []
    for line in REGISTRY.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip() or line.startswith("name\t"):
            continue
        rows.append(line.split("\t"))
    return rows


class RegistryTest(unittest.TestCase):
    def test_every_row_has_the_full_column_set(self) -> None:
        for row in registry_rows():
            with self.subTest(engine=row[0]):
                self.assertEqual(len(row), 14, f"{row[0]}: hibás oszlopszám")

    def test_reasoning_column_holds_a_supported_effort_or_the_neutral_dash(self) -> None:
        """ADR 0173: a gondolkodási szint MÉRT érték, nem tetszőleges string.

        A `-` semleges: a burkoló ilyenkor NEM ad át `model_reasoning_effort`-ot,
        tehát a provider defaultja marad — ez a visszakapcsolás útja is.
        """
        for row in registry_rows():
            with self.subTest(engine=row[0]):
                self.assertIn(row[12], ("-", "minimal", "low", "medium", "high"))

    def test_the_measured_engine_actually_gets_reasoning(self) -> None:
        # MÉRVE 2026-08-05: a Kilo-profil alatt a fejléc `reasoning effort: none`
        # volt; a füst-teszt igazolta, hogy a provider elfogadja a `medium`-ot.
        by_name = {row[0]: row for row in registry_rows()}
        self.assertEqual(by_name["qwen38-max"][12], "medium")

    def test_harness_is_one_of_the_two_supported_ones(self) -> None:
        for row in registry_rows():
            with self.subTest(engine=row[0]):
                self.assertIn(row[1], ("codex", "claude"))

    def test_numeric_fields_are_numbers(self) -> None:
        for row in registry_rows():
            with self.subTest(engine=row[0]):
                for index, label in ((6, "stall_min"), (7, "timeout_s"), (8, "ctx"), (9, "max_out")):
                    self.assertTrue(row[index].isdigit(), f"{row[0]}: {label}={row[index]}")

    def test_a_slow_engine_gets_a_raised_stall_guard(self) -> None:
        # MÉRT ok: a Qwen ~95 s alatt válaszol; a 12 perces alapértelmezéssel a
        # wrapper elakadás-őre a normál gondolkodást lőné ki hamis riasztásként.
        by_name = {row[0]: row for row in registry_rows()}
        self.assertGreaterEqual(int(by_name["qwen-plus"][6]), 20)

    def test_engine_names_are_unique(self) -> None:
        names = [row[0] for row in registry_rows()]
        self.assertEqual(len(names), len(set(names)))


class SwitcherTest(unittest.TestCase):
    """Hermetikus HOME-mal fut.

    MÉRT hiba (2026-08-05, CI): az első verzió a fejlesztői gép `~/.codex-kilo`
    könyvtárára támaszkodott, ezért a runneren elbukott — ugyanaz az
    ambiens-állapot osztály, mint a docs/LESSONS.md L118. A profilokat és a
    kulcsfájlokat ezért a teszt maga hozza létre egy ideiglenes HOME-ban.
    """

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        for row in registry_rows():
            config = row[2].replace("~/", "")
            (self.home / config).mkdir(parents=True, exist_ok=True)
            auth_file = row[5]
            if auth_file != "-":
                key_path = self.home / auth_file.replace("~/", "")
                key_path.parent.mkdir(parents=True, exist_ok=True)
                if key_path.suffix == ".json":
                    key_path.write_text('{"api_key": "fixture-key"}')
                else:
                    key_path.write_text("fixture-key\n")

    def run_script(self, *arguments, state=None):
        environment = dict(os.environ)
        environment["HOME"] = str(self.home)
        if state:
            environment["PIPELINE_STATE_DIR"] = str(state)
        return subprocess.run(
            ["bash", str(SCRIPT), *arguments],
            capture_output=True, text=True, env=environment, cwd=ROOT,
        )

    def test_a_missing_profile_is_refused_rather_than_silently_used(self) -> None:
        # A hiányzó profil NEM állítható be — különben a kör a modellhívásnál
        # halna meg, órákkal később, a kör közepén.
        import shutil

        shutil.rmtree(self.home / ".codex-kilo")
        with tempfile.TemporaryDirectory() as name:
            result = self.run_script("use", "qwen-plus", state=Path(name))

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HIÁNYZIK a profil", result.stderr)

    def test_use_then_clear_round_trips_without_touching_any_config(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)

            self.assertIn("nincs override", self.run_script("show", state=state).stdout)

            used = self.run_script("use", "qwen-plus", state=state)
            self.assertEqual(used.returncode, 0, used.stderr)
            self.assertEqual(self.run_script("show", state=state).stdout.strip(), "qwen-plus")

            switched = self.run_script("use", "terra", state=state)
            self.assertEqual(switched.returncode, 0, switched.stderr)
            self.assertEqual(self.run_script("show", state=state).stdout.strip(), "terra")

            cleared = self.run_script("clear", state=state)
            self.assertEqual(cleared.returncode, 0, cleared.stderr)
            self.assertIn("nincs override", self.run_script("show", state=state).stdout)

    def test_unknown_engine_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            result = self.run_script("use", "nincs-ilyen", state=Path(name))

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ismeretlen motor", result.stderr)

    def test_env_emits_the_harness_specific_variables(self) -> None:
        codex_env = self.run_script("env", "qwen-plus").stdout
        self.assertIn("CODEX_HOME=", codex_env)
        self.assertIn("ENGINE_MODEL=qwen/qwen3.7-plus", codex_env)
        self.assertIn("ENGINE_CONTEXT_WINDOW=", codex_env)

        claude_env = self.run_script("env", "minimax").stdout
        self.assertIn("CLAUDE_CONFIG_DIR=", claude_env)

    def test_env_never_prints_an_empty_credential_assignment(self) -> None:
        # Hiányzó kulcsfájl esetén inkább NE legyen sor, mint üres értékű —
        # az üres kulcs csendes 401-hez vezetne a kör közepén.
        for row in registry_rows():
            with self.subTest(engine=row[0]):
                for line in self.run_script("env", row[0]).stdout.splitlines():
                    if line.endswith("="):
                        self.fail(f"{row[0]}: üres értékű változó: {line}")


class DriverIntegrationTest(unittest.TestCase):
    def validate(self, engine: str) -> int:
        return subprocess.run(
            ["bash", str(DRIVER), "--validate-engine", engine],
            capture_output=True, text=True, cwd=ROOT,
        ).returncode

    def test_driver_accepts_every_registry_engine(self) -> None:
        for row in registry_rows():
            with self.subTest(engine=row[0]):
                self.assertEqual(self.validate(row[0]), 0)

    def test_driver_still_accepts_the_legacy_values(self) -> None:
        for engine in ("auto", "minimax", "codex"):
            with self.subTest(engine=engine):
                self.assertEqual(self.validate(engine), 0)

    def test_driver_stays_fail_closed_on_an_unknown_engine(self) -> None:
        self.assertNotEqual(self.validate("nincs-ilyen-motor"), 0)
        self.assertNotEqual(self.validate(""), 0)


if __name__ == "__main__":
    unittest.main()
