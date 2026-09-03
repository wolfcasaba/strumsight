"""A titok-kaput a router-ci sávjában is mérni kell (ADR 0112 önjavító kör).

MÉRT GYÖKÉROK (2026-09-03, E15-R10 / H3): a `tool/ci/check_secrets.dart` az
EGÉSZ követett fát vizsgálja, de kizárólag a `.github/actions/flutter-gates`
composite 5. lépéseként fut, azt pedig csak a `build-apk.yml` és a
`full-gate.yml` hívja — mindkettő `workflow_dispatch`, tehát kör-dispatch
nélkül SOHA nem indul el magától. A `tools/**` útvonalra viszont a
`router-ci.yml` indul AUTOMATIKUSAN, és annak nincs titok-lépése.

Ezen a résen csúszott át a PR #544 (`ops/authenticated-git-fetch`, tools-only,
egyetlen zöld check: `router-ci`): a `main`-re került egy csupasz
provider-token literál a szkenner dokumentált mentesítő markere nélkül. Utána
MINDEN kör, amely az ADR 0086 §2 szerint beemeli a `main`-t, a `secrets`
lépésen bukott el, és mivel az a composite 5. lépése, a full-gate ÖSSZES
további lépése (l10n, asset, test, property, coverage) `skipped` lett — a
körök saját munkája meg sem lett mérve.

Ez a teszt a TÜNET helyett a HIBAOSZTÁLYT zárja: a router-ci saját
`pytest tools/tests` lépésében méri ugyanazt a provider-token szabályt azokon
az útvonalakon, amelyekre a router-ci automatikusan indul. A szabályt NEM
másolja le — a `tool/ci/check_secrets.dart` forrásából olvassa ki, így a két
oldal nem tud szétcsúszni; ha a Dart oldal alakja megváltozik, ez a teszt
PIROSRA vált (fail-closed), nem pedig némán zöldre.

A javítás helye azért itt van, mert a `.github/workflows/**` az ADR 0112 §3
abszolút tiltott zónája: a lefedettséget a `tools/**` oldalon kell
helyreállítani, és ez szigorúan BŐVÍTI a mércét, nem gyengíti.
"""

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCANNER = ROOT / "tool" / "ci" / "check_secrets.dart"

# A `router-ci.yml` automatikus trigger-útvonalai közül azok, amelyeket a Dart
# szkenner is vizsgál. A `.ai/**` szándékosan kimarad: az a szkenner saját
# skip-listáján (`_skippedDirectories`) van, tehát ott nincs mit mérni.
SCANNED_PREFIXES = ("tools/", "docs/execution/", "docs/rounds/")

# A szkenner `_skippedExtensions` listájának a fenti útvonalakon értelmes
# része; a többi kiterjesztés ezeken a prefixeken nem fordul elő.
SKIPPED_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg", ".pyc"}

# A szkenner `_maxScannedBytes` értéke: efölött a fájl adat, nem forrás.
MAX_SCANNED_BYTES = 1024 * 1024


def _scanner_source() -> str:
    return SCANNER.read_text(encoding="utf-8")


def _dart_string_const(source: str, name: str) -> str:
    """A Dart oldal egy `const String <name> = '...';` értékét adja vissza.

    A markereket azért olvassuk ki, és nem írjuk ide literálként, mert egy
    beírt marker-literál MAGÁT EZT A FÁJLT mentesítené a szkenner alól.
    """
    match = re.search(rf"const String {name}\b\s*=\s*'([^']+)'\s*;", source)
    if match is None:
        raise AssertionError(
            f"a(z) {name} marker-konstans nem olvasható ki a {SCANNER.name}-ből "
            "— a Dart oldal alakja megváltozott, a port frissítendő"
        )
    return match.group(1)


def _provider_token_pattern(source: str) -> "re.Pattern[str]":
    """A providerToken szabály regexét emeli ki a Dart forrásból.

    A Dart raw-string darabkák konkatenálva pontosan egy Python-kompatibilis
    mintát adnak (nem-fogó csoportok, karakterosztályok, `{n,}` kvantorok).
    """
    start = source.find("SecretIssueKind.providerToken")
    if start < 0:
        raise AssertionError(
            "a providerToken szabály nem található a szkennerben — a port frissítendő"
        )
    open_at = source.find("pattern: RegExp(", start)
    close_at = source.find("\n    ),", open_at)
    if open_at < 0 or close_at < 0:
        raise AssertionError(
            "a providerToken RegExp blokk nem határolható be — a port frissítendő"
        )
    fragments = re.findall(r"r'([^']*)'", source[open_at:close_at])
    if len(fragments) < 5:
        raise AssertionError(
            f"a providerToken minta csak {len(fragments)} darabkából állt össze "
            "— a Dart oldal alakja megváltozott, a port frissítendő"
        )
    return re.compile("".join(fragments))


def _tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z", *SCANNED_PREFIXES],
        capture_output=True,
        text=True,
        check=True,
    )
    return [path for path in result.stdout.split("\0") if path]


class ProviderTokenRuleExtractionTest(unittest.TestCase):
    """Fail-closed önteszt: a kiolvasott szabály tényleg él-e."""

    def setUp(self) -> None:
        self.source = _scanner_source()
        self.pattern = _provider_token_pattern(self.source)

    def test_extracted_pattern_matches_a_synthetic_token(self) -> None:
        # Darabokból építve, hogy EZ a fájl ne legyen maga is találat.
        synthetic = "ghp_" + "A" * 32
        self.assertIsNotNone(
            self.pattern.search(f'TOKEN = "{synthetic}"'),
            "a kiolvasott minta nem ismer fel egy szintetikus provider-tokent",
        )

    def test_extracted_pattern_ignores_ordinary_text(self) -> None:
        self.assertIsNone(
            self.pattern.search("a git fetch hitelesitve megy a credential helperrel"),
            "a kiolvasott minta hétköznapi szövegre is illeszkedik",
        )

    def test_markers_are_readable_from_the_scanner(self) -> None:
        line_marker = _dart_string_const(self.source, "allowMarker")
        file_marker = _dart_string_const(self.source, "allowFileMarker")
        self.assertIn("allow", line_marker)
        self.assertTrue(file_marker.startswith(line_marker))


class RouterPathSecretScanTest(unittest.TestCase):
    """A router-ci által AUTOMATIKUSAN lefedett útvonalak titok-mérése."""

    def test_router_triggered_paths_have_no_unmarked_provider_token(self) -> None:
        source = _scanner_source()
        pattern = _provider_token_pattern(source)
        line_marker = _dart_string_const(source, "allowMarker")
        file_marker = _dart_string_const(source, "allowFileMarker")

        tracked = _tracked_files()
        self.assertGreater(
            len(tracked), 0, "a git nem sorolt fel egyetlen követett fájlt sem"
        )

        findings: list[str] = []
        for relative in tracked:
            path = ROOT / relative
            if path.suffix in SKIPPED_SUFFIXES:
                continue
            if not path.exists():
                continue  # törölt, de még indexelt
            if path.stat().st_size > MAX_SCANNED_BYTES:
                continue
            try:
                contents = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue  # nem olvasható vagy nem UTF-8 — nem elemezhető
            if file_marker in contents:
                continue
            for number, line in enumerate(contents.split("\n"), start=1):
                if line_marker in line:
                    continue
                if pattern.search(line):
                    # A találat HELYE szerepel, az ÉRTÉKE soha.
                    findings.append(f"{relative}:{number}")

        self.assertEqual(
            [],
            findings,
            "jelöletlen provider-token literál a router-ci útvonalain: "
            f"{findings} — ha bizonyítottan nem titok, a szkenner saját "
            f"markere kerüljön a sor végére ('{line_marker}'), különben a "
            "titok eltávolítandó és rotálandó",
        )


if __name__ == "__main__":
    unittest.main()
