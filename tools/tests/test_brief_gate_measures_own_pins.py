"""S14 — a briefen BELÜL élő pinnelő teszt a kör KAPUJÁN is fusson.

MÉRT eset (E15-R09, `docs/LESSONS.md` L593, 2026-09-03). A kör célzott gate-je
**17/17 zöld** volt, a review viszont a kapun kívüli, a migrált képernyőt
PINNELŐ harnesst lefuttatva 2 piros cellát mért — két piros CI-futás, `H5`
halt, ADR 0112 önjavítás. Az L593 „Hogyan alkalmazd" (1) pontja ezt mondja ki:

    a `gate_tests` a migrált képernyő ÖSSZES kipinnelt harnessét tartalmazza —
    mérd ki: `grep -rl "<ScreenName>" test/`, ne emlékezetből sorold.

Az S11 eddig csak az `allowed_paths`-on KÍVÜLI pineket mérte, és a listán
BELÜLIT szándékosan a brief-szerző mérlegelésére hagyta. Ez a teszt azt a rést
zárja: ami a kör hatókörében van ÉS pinnel, az a kör kapuján is fusson.
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", ROOT / "tools" / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class GateMeasuresOwnPinsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.lint = _brief_lint()

    def _fixture(self, directory: str) -> tuple[Path, str, str]:
        """Egy képernyő + az őt PINNELŐ teszt egy ideiglenes fában."""
        repo = Path(directory)
        screen = "lib/features/tutor/presentation/screens/tutor_home_screen.dart"
        pin = "test/features/tutor/presentation/tutor_home_screen_test.dart"
        (repo / screen).parent.mkdir(parents=True)
        (repo / pin).parent.mkdir(parents=True)
        (repo / screen).write_text("class TutorHomeScreen {}\n", encoding="utf-8")
        (repo / pin).write_text(
            "import 'package:strumsight/features/tutor/presentation/screens/"
            "tutor_home_screen.dart';\n"
            "void main() { find.byType(TutorHomeScreen); }\n",
            encoding="utf-8",
        )
        return repo, screen, pin

    def test_a_pinning_test_inside_the_brief_but_outside_the_gate_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo, screen, pin = self._fixture(directory)
            screens = self.lint.owned_existing_screens(repo, [screen])
            self.assertEqual(screens, [screen])
            unmeasured = self.lint.unmeasured_screen_pins(repo, screens, [screen, pin], [])
            self.assertEqual(unmeasured, {screen: [pin]})

    def test_the_same_test_inside_the_gate_is_silent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo, screen, pin = self._fixture(directory)
            screens = self.lint.owned_existing_screens(repo, [screen])
            self.assertEqual(
                self.lint.unmeasured_screen_pins(repo, screens, [screen, pin], [pin]), {}
            )

    def test_a_test_outside_the_brief_stays_an_s11_finding_not_an_s14_one(self) -> None:
        """A két szabály hatóköre DISZJUNKT — nem duplikálják egymás leletét."""
        with tempfile.TemporaryDirectory() as directory:
            repo, screen, pin = self._fixture(directory)
            screens = self.lint.owned_existing_screens(repo, [screen])
            self.assertEqual(
                self.lint.outside_screen_pins(repo, screens, [screen], []), {screen: [pin]}
            )
            self.assertEqual(self.lint.unmeasured_screen_pins(repo, screens, [screen], []), {})

    def test_a_bare_import_without_the_type_name_is_not_a_pin(self) -> None:
        """A hamis riasztás elleni kettős feltétel S14-en is él."""
        with tempfile.TemporaryDirectory() as directory:
            repo, screen, pin = self._fixture(directory)
            (repo / pin).write_text(
                "import 'package:strumsight/features/tutor/presentation/screens/"
                "tutor_home_screen.dart';\nvoid main() {}\n",
                encoding="utf-8",
            )
            screens = self.lint.owned_existing_screens(repo, [screen])
            self.assertEqual(self.lint.unmeasured_screen_pins(repo, screens, [screen, pin], []), {})

    def test_the_rule_is_registered_and_documented(self) -> None:
        source = (ROOT / "tools" / "brief-lint.py").read_text(encoding="utf-8")
        self.assertIn('"S14"', source)
        self.assertIn("L593", source)


if __name__ == "__main__":
    unittest.main()
