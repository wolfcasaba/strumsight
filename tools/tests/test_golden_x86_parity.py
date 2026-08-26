"""A golden-mérés architektúra-paritásának őre (ADR 0426).

MÉRT gyökérok (E13-R17 és E13-R20, 2026-08-25/26). A goldeneket ez a box
(aarch64) veszi fel, a zöld kaput adó CI viszont `ubuntu-latest` = x86_64, és
a `LocalFileComparator` nulla toleranciájú. Ami a két ISA raszterizációja
között eltér, az a LOKÁLIS gate-ben MINDIG zöld és a CI-ban MINDIG piros:

  E13-R17: 4 cella, 5,60–11,71%   (CI run 32887590628)  -> 2 vak javító kör
  E13-R20: 3 cella, 0,00% (1/8/1px) (CI run 32918668534) -> 3 piros CI, H5 halt

Az L486 a saját lezárásában ki is mondta, miért nem készült hozzá őr:
„a hordozhatóság ELVBŐL nem mérhető ezen a boxon (a felvétel és a verifikáció
architektúrája különbözik)". Ez az ELVI korlát szűnt meg: a
`tools/golden-x86.sh` a golden-tesztet a CI-vel azonos Flutter-verzióval,
qemu-user amd64 emuláció alatt futtatja, tehát a felvétel és a verifikáció
architektúrája egybeesik.

Amit ez a teszt őriz — a három NÉMA szétcsúszás, ami visszahozná a halt-ot:

1. az eszköz eltűnik vagy nem futtatható;
2. a workflow-k Flutter-pinje szétcsúszik (vagy egymástól, vagy attól, amit az
   eszköz épít) — ekkor a lokális x86 mérés MÁS Flutter, tehát hamis zöld;
3. egy új golden-teszt-fájl kimarad az eszköz felderítéséből — ekkor a mérés
   nem fedi le, és a következő kör újra a CI-ban tudja meg.
"""

from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "golden-x86.sh"
DOCKERFILE = ROOT / "tools" / "docker" / "golden-x86.Dockerfile"
WORKFLOWS = ROOT / ".github" / "workflows"
TEST_DIR = ROOT / "test"

PIN = re.compile(r"flutter-version:\s*'([^']+)'")


def workflow_flutter_pins() -> dict[str, set[str]]:
    pins: dict[str, set[str]] = {}
    for path in sorted(WORKFLOWS.glob("*.yml")):
        found = set(PIN.findall(path.read_text(encoding="utf-8")))
        if found:
            pins[path.name] = found
    return pins


def golden_test_files() -> set[str]:
    """A ténylegesen MÉRT lista: minden `matchesGoldenFile`-t hívó teszt-fájl."""
    found = set()
    for path in TEST_DIR.rglob("*.dart"):
        if "matchesGoldenFile" in path.read_text(encoding="utf-8"):
            found.add(path.relative_to(ROOT).as_posix())
    return found


class GoldenX86ParityTest(unittest.TestCase):
    def test_the_instrument_exists_and_is_executable(self) -> None:
        self.assertTrue(SCRIPT.is_file(), "hiányzik a tools/golden-x86.sh")
        self.assertTrue(
            os.access(SCRIPT, os.X_OK), "a tools/golden-x86.sh nem futtatható"
        )
        self.assertTrue(DOCKERFILE.is_file(), "hiányzik a golden-x86 Dockerfile")

    def test_script_is_syntactically_valid(self) -> None:
        result = subprocess.run(
            ["bash", "-n", str(SCRIPT)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_every_workflow_pins_the_same_flutter_version(self) -> None:
        pins = workflow_flutter_pins()
        self.assertTrue(pins, "egyetlen workflow sem pinneli a Flutter-verziót")
        versions = {version for found in pins.values() for version in found}
        self.assertEqual(
            len(versions),
            1,
            f"a workflow-k Flutter-pinjei szétcsúsztak: {pins}",
        )

    def test_the_image_version_comes_from_the_workflow_pin(self) -> None:
        """A Dockerfile NEM rögzíthet saját verziót — build-argot kell kapnia."""
        text = DOCKERFILE.read_text(encoding="utf-8")
        self.assertIn("ARG FLUTTER_VERSION", text)
        self.assertNotRegex(
            text,
            r"ARG FLUTTER_VERSION\s*=",
            "a Dockerfile alapértelmezett verziója némán szétcsúszhatna a CI pinjétől",
        )
        script = SCRIPT.read_text(encoding="utf-8")
        self.assertIn(".github/workflows/", script)
        self.assertIn("FLUTTER_VERSION=$flutter_version", script)

    def test_discovery_covers_every_golden_test_file(self) -> None:
        """Az eszköz alapértelmezett felderítése fedje a MÉRT fájllistát."""
        measured = golden_test_files()
        self.assertTrue(measured, "nem található golden-teszt a test/ alatt")
        result = subprocess.run(
            ["grep", "-rl", "matchesGoldenFile", str(TEST_DIR), "--include=*.dart"],
            capture_output=True,
            text=True,
        )
        discovered = {
            Path(line).resolve().relative_to(ROOT).as_posix()
            for line in result.stdout.splitlines()
            if line.strip()
        }
        self.assertEqual(
            measured,
            discovered,
            "a golden-x86 felderítése nem fedi a tényleges golden-teszt-fájlokat",
        )

    def test_the_ch13_golden_bank_is_discovered(self) -> None:
        """A halt-ot okozó sáv horgonya: a Ch13 golden-készlet nem eshet ki.

        A MÉRT lista (`main @ 886cd5b6`) a `test/ui/goldens/` alatt az
        E13-R16…R19 négy fájlja; a felderítésnek mindegyiket meg kell találnia,
        különben pont az a sáv marad mérés nélkül, amelyik a halt-ot adta.
        """
        discovered = golden_test_files()
        ch13 = {
            path
            for path in discovered
            if path.startswith("test/ui/goldens/") and "_screens_golden_test" in path
        }
        self.assertGreaterEqual(
            len(ch13),
            4,
            f"a Ch13 golden-sáv nem teljes a felderítésben: {sorted(ch13)}",
        )


if __name__ == "__main__":
    unittest.main()
