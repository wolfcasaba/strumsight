"""S16 — a GENERÁLT l10n-aggregátum a listán, a FORRÁS szegmens nem.

MÉRVE 2026-09-05 (E14-R13 / H3, ADR 0112 önjavító kör): a kör briefje a négy
ok-szöveghez `lib/l10n/app_{en,hu}.arb`-ot engedte. Ezek a
``tool/gen_l10n_segments.dart`` generált aggregátumai (ADR 0307 §4), a Live
kulcsok forrása a ``lib/l10n/base/app_<locale>.arb`` szegmens::

    grep -l '"liveWeakSignal"' lib/l10n/app_en.arb lib/l10n/base/app_en.arb
    #   mindkettő -> a base a FORRÁS, az app_en.arb a generált unió

A kör tehát a saját listáján belül nem tudott volna kulcsot felvenni; a
feloldás lista-TÁGÍTÁS, ami nem az orchestrátor hatásköre → H3 a dispatch előtt.

A szabály `strict` és `done` körre néma, mint az S13/S15 — a CI-kapu
``--level base``, tehát egy lezárt kört sosem vált pirosra.
"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "brief_lint_s16", REPO_ROOT / "tools" / "brief-lint.py"
)
brief_lint = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(brief_lint)


HEADER = """# E99-R99 — S16 fixture

- **Kör-azonosító:** `E99-R99`

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
%s
]
gate_tests = [
  "test/l10n/arb_parity_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

`tools/codex-signal.sh done "..."` — jelzés nélkül a kör bukott. Listán kívüli
fájl → `stopped`, és a kimenet a brief-revízió, nem a lista-tágítás.

## 6. Acceptance criteria

1. A kulcs mindkét locale-ban létezik. Falszifikáció: az `hu` kulcs törlésével
   a cella PIROS, visszaállítva ZÖLD.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/l10n/arb_parity_test.dart
```
"""


def _codes(paths: list[str]) -> set[str]:
    """A lint a LEMEZRŐL olvas (`load_brief`), ezért a fixture valódi fájl.

    A repón BELÜL kap helyet, mert a `lint_text` a brief útvonalát a repóhoz
    képest relativizálja; a `TemporaryDirectory` a futás végén eltakarítja.
    """
    text = HEADER % "\n".join(f'  "{item}",' for item in paths)
    with tempfile.TemporaryDirectory(dir=REPO_ROOT / "tools" / "tests") as tmp:
        fixture = Path(tmp) / "e99-r99-s16-fixture.md"
        fixture.write_text(text, encoding="utf-8")
        findings = brief_lint.lint_text(text, path=fixture, repo=REPO_ROOT)
    codes = {finding["code"] for finding in findings}
    assert "B1" not in codes, f"a fixture ai-router blokkja nem elemezhető: {findings}"
    return codes


class GeneratedL10nSourceScope(unittest.TestCase):
    def test_generated_aggregate_without_source_is_a_finding(self) -> None:
        """A MÉRT E14-R13 alak: csak az aggregátum, forrás nélkül."""
        codes = _codes(
            [
                "lib/l10n/app_en.arb",
                "lib/l10n/app_hu.arb",
                "docs/rounds/e99-r99-s16-fixture.md",
            ]
        )
        self.assertIn("S16", codes)

    def test_base_segment_alongside_the_aggregate_is_clean(self) -> None:
        """A javított alak: a FORRÁS is a listán, az aggregátum marad."""
        codes = _codes(
            [
                "lib/l10n/base/app_en.arb",
                "lib/l10n/base/app_hu.arb",
                "lib/l10n/app_en.arb",
                "lib/l10n/app_hu.arb",
                "docs/rounds/e99-r99-s16-fixture.md",
            ]
        )
        self.assertNotIn("S16", codes)

    def test_feature_fragment_counts_as_the_source(self) -> None:
        """A `lib/l10n/features/<feature>_<locale>.arb` ugyanúgy forrás."""
        codes = _codes(
            [
                "lib/l10n/features/live_en.arb",
                "lib/l10n/features/live_hu.arb",
                "lib/l10n/app_en.arb",
                "lib/l10n/app_hu.arb",
                "docs/rounds/e99-r99-s16-fixture.md",
            ]
        )
        self.assertNotIn("S16", codes)

    def test_partial_source_still_reports_the_orphan_locale(self) -> None:
        """Locale-onként mér: `en` forrása megvan, `hu`-é nincs → lelet."""
        codes = _codes(
            [
                "lib/l10n/base/app_en.arb",
                "lib/l10n/app_en.arb",
                "lib/l10n/app_hu.arb",
                "docs/rounds/e99-r99-s16-fixture.md",
            ]
        )
        self.assertIn("S16", codes)

    def test_no_generated_aggregate_is_silent(self) -> None:
        """Aki nem nyúl l10n-hez, arra a szabály néma."""
        codes = _codes(
            [
                "lib/features/live/screens/live_screen.dart",
                "docs/rounds/e99-r99-s16-fixture.md",
            ]
        )
        self.assertNotIn("S16", codes)

    def test_the_generated_paths_the_rule_matches_really_are_generated(self) -> None:
        """A szabály tárgya MÉRTEN generált fájl, nem feltételezés."""
        for locale in ("en", "hu"):
            aggregate = REPO_ROOT / "lib" / "l10n" / f"app_{locale}.arb"
            source = REPO_ROOT / "lib" / "l10n" / "base" / f"app_{locale}.arb"
            self.assertTrue(aggregate.is_file(), aggregate)
            self.assertTrue(source.is_file(), source)
            self.assertIsNotNone(
                brief_lint.GENERATED_ARB.fullmatch(f"lib/l10n/app_{locale}.arb")
            )
        generator = REPO_ROOT / "tool" / "gen_l10n_segments.dart"
        self.assertIn(
            "GENERATED-FILE-MARKER", generator.read_text(encoding="utf-8")[:200]
        )


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
