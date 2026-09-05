"""Egy DÁTUMOZOTT jelentést nem őrizhet az ÉLŐ fából újramért szám (L613).

MÉRT gyökérok (E16-R02 / 4. H3, 2026-09-03, `.pipeline/halt-detail-E16-R02.md`).
A `docs/ui/chapter-15-completion-report.md` a saját fejlécében kimondja, hogy
mihez mérték: `**Measured against:** main @ 9ba54399 + this round's own tree`.
Az E15-R13 őre viszont az ÉLŐ fából számolta újra a várt értéket
(`ScreenReachability(Directory.current).render()`), és attól követelte meg a
dátumozott jelentés szám-egyezését:

    ❌ test/ui/goldens/e15_r13_full_variant_matrix_test.dart:3733
       A5 — completion-report guard … Expected: contains '73'

Az E16-R02 acceptance-kritériuma PONTOSAN két képernyő elérhetővé tétele
(`ProgressDashboardScreen`, `SkillDetailScreen`), tehát `reachableCount`
71 → 73: a kör **sikere** vitte pirosra a full-gate-et — egy olyan cellán,
amelynek MINDKÉT fájlja (a jelentés és az őrteszt) a kör TILOS zónájában van.
Ugyanaz a hibaosztály, mint az L612, csak a doc-konzisztencia felől.

A szabály ezért: ha egy teszt-`group` egy dátumozott pillanatkép-jelentést
olvas (`**Measured against:**` fejléc), akkor UGYANABBAN a group-ban nem
mérheti újra az élő fát. A várt számok rögzített pillanatképből jöjjenek
(itt: `test/fixtures/ui/e15_r13_completion_report_baseline.json`, provenance a
fixture-manifestben). Ez NEM gyengítés: az L588 tulajdonsága megmarad — a
számok továbbra is a jelentés SZÖVEGÉTŐL függetlenül állnak elő, tehát egy
némán TÖRÖLT állítás is bukik —, csak nem az élő fa mozdítja el őket. Az élő
fát az A1 completeness-group méri, amelynek invariánsa (mért elérhető halmaz
⊆ mátrix ∪ kizárási lista) a jogos növekedést túléli.

A szabály-VISELKEDÉST rögzített bemeneten mérjük (L612): a
`fixtures/e16_r02_dated_report_guard/` alatti négy `.txt` a valódi, szó
szerint másolt A5 (javítás előtti és utáni) és A1 group. A `test/` fát végigfutó
cella a KÖVETELT VÉGÁLLAPOTOT pinneli (nulla lelet), nem egy kör munkájának
hiányát — azt csak úgy lehet pirosra vinni, ha valaki újra bevezeti a
hibaosztályt.

MÁSODIK ELŐFORDULÁS — E17-R01 / H3 (2026-09-05, L614). A fenti szabály CSAK az
`X(Directory.current)` alakú élő-fa mérést látta, ezért az E16-R02 javítása a
reachability-cellát átvitte a rögzített pillanatképre, a DARABSZÁM-cellákat
viszont élőn hagyta:

    contains('${_screens.length}')                       # 72 → 73
    contains('$totalCells')   // _screens.length * … * 2 # 1152 → 1168
    contains('$grandTotal')   // totalCells + A1 + A5    # 1163 → 1179

Az E17-R01 acceptance-kritériuma a `FirstWinStageScreen` elérhetővé tétele,
tehát a mátrix EGGYEL nő — ugyanaz a hibaosztály, csak nem a fából, hanem a
teszt-fájl ÉLŐ kollekcióiból (`_screens`, `_excludedCells`,
`_ViewportProfile.values`) származó várt értéken keresztül. Az E17 sáv mind a
14 köre növeli a reachability-t, tehát körönként visszatért volna.

A kibővített szabály ezért az ÉRTÉK EREDETÉT nézi: egy dátumozott jelentést
olvasó group-ban a `contains(...)`-be interpolált VÁRT ÉRTÉK csak RÖGZÍTETT
pillanatképből (`test/fixtures/**`-ból olvasott érték) vagy literálból jöhet.
Nem érinti a `normalizedReport.contains(normalizedName)` alakú cellát: ott
nincs interpolált várt szám, és a mögötte álló `_excludedCells` lista a saját
szabálya szerint CSAK ZSUGORODHAT (L180) — zsugorodáskor a cella zöld marad.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tools" / "tests" / "fixtures" / "e16_r02_dated_report_guard"

# Egy jelentés akkor DÁTUMOZOTT PILLANATKÉP, ha maga mondja meg, milyen fához
# mérték. (`docs/sdd/program-completion-report.md` szándékosan NEM ilyen: ott a
# fejléc kimondja, hogy a mátrix a queue ÉLŐ állapotát tükrözi.)
DATED_HEADER = "**Measured against:**"

# `ScreenReachability(Directory.current)`, `UiInventory(Directory.current)`, …
LIVE_MEASUREMENT = re.compile(r"\b[A-Z][A-Za-z0-9_]*\(\s*Directory\.current\s*\)")

GROUP_CALL = re.compile(r"\bgroup\s*\(")


def mask_strings_and_comments(source: str) -> str:
    """A karakterláncok és kommentek TARTALMÁT szóközre cseréli.

    A hossz és a sortörések változatlanok, ezért a maszkolt szöveg indexei
    egy az egyben ráillenek az eredetire: a zárójel-párosítás így nem akad meg
    egy string-beli `(`-en, a doc-hivatkozást viszont az EREDETI szövegben
    lehet keresni ugyanazon a tartományon.
    """
    out = list(source)
    length = len(source)
    index = 0
    while index < length:
        char = source[index]
        if char == "/" and source.startswith("//", index):
            end = source.find("\n", index)
            end = length if end == -1 else end
            for position in range(index, end):
                out[position] = " "
            index = end
            continue
        if char == "/" and source.startswith("/*", index):
            end = source.find("*/", index + 2)
            end = length if end == -1 else end + 2
            for position in range(index, end):
                if out[position] != "\n":
                    out[position] = " "
            index = end
            continue
        if char in "'\"":
            raw = index > 0 and source[index - 1] == "r"
            triple = source[index : index + 3] in ("'''", '"""')
            delimiter = source[index : index + 3] if triple else char
            body = index + len(delimiter)
            cursor = body
            while cursor < length:
                if not raw and source[cursor] == "\\":
                    cursor += 2
                    continue
                if source.startswith(delimiter, cursor):
                    break
                if not triple and source[cursor] == "\n":
                    break
                cursor += 1
            for position in range(body, min(cursor, length)):
                if out[position] != "\n":
                    out[position] = " "
            index = min(cursor + len(delimiter), length)
            continue
        index += 1
    return "".join(out)


def group_blocks(masked: str) -> list[tuple[int, int]]:
    """Minden `group(...)` hívás [kezdet, vég) tartománya a maszkolt szövegben."""
    blocks: list[tuple[int, int]] = []
    for match in GROUP_CALL.finditer(masked):
        depth = 0
        cursor = match.end() - 1
        while cursor < len(masked):
            if masked[cursor] == "(":
                depth += 1
            elif masked[cursor] == ")":
                depth -= 1
                if depth == 0:
                    blocks.append((match.start(), cursor + 1))
                    break
            cursor += 1
    return blocks


def live_tree_pins(source: str, dated_doc_paths: set[str]) -> list[str]:
    """A `source` azon élő-fa mérései, amelyek dátumozott jelentést őriznek.

    Csak a LEGBELSŐ befoglaló group számít: egy A1-szerű group élő mérése nem
    válik lelet-té attól, hogy egy MÁSIK group ugyanabban a fájlban jelentést
    olvas.
    """
    masked = mask_strings_and_comments(source)
    blocks = group_blocks(masked)
    findings: list[str] = []
    for match in LIVE_MEASUREMENT.finditer(masked):
        enclosing = [b for b in blocks if b[0] <= match.start() < b[1]]
        if not enclosing:
            continue
        start, end = min(enclosing, key=lambda b: b[1] - b[0])
        block = source[start:end]
        for doc in sorted(dated_doc_paths):
            if doc in block:
                line = source.count("\n", 0, match.start()) + 1
                findings.append(f"{line}: {match.group(0)} guards {doc}")
    return findings


# `contains('${matrix.screenCount}')`, `contains('$grandTotal')`
CONTAINS_CALL = re.compile(r"\bcontains\s*\(")
# `${...}` és `$ident` a Dart string-interpolációban
INTERPOLATION = re.compile(r"\$\{([^{}]*)\}|\$([A-Za-z_]\w*)")
# Egy kifejezés GYÖKÉR-azonosítói: a pont utáni tagnevek nem számítanak
# (`matrix.screenCount` gyökere `matrix`).
ROOT_IDENTIFIER = re.compile(r"(?<![\w.$])([A-Za-z_]\w*)")
# `final totalCells = …;`, `const a1CellCount = 5;`, `var x = …;`
LOCAL_DECLARATION = re.compile(
    r"\b(?:final|const|var)\s+(?:[\w<>,\s?\[\]]+?\s+)?(\w+)\s*=\s*([^;]*);"
)
# `for (final name in excludedScreenNames)`
LOOP_DECLARATION = re.compile(r"\bfor\s*\(\s*(?:final|var)\s+(\w+)\s+in\s+([^)]*)\)")
# `const _baselinePath =\n    'test/fixtures/…';`
FILE_LEVEL_PATH_CONST = re.compile(
    r"^const\s+(\w+)\s*=\s*\n?\s*'([^']*)'\s*;", re.MULTILINE
)
RECORDED_FIXTURE_PREFIX = "test/fixtures/"


def recorded_path_constants(source: str) -> set[str]:
    """A fájl-szintű konstansok, amelyek RÖGZÍTETT fixture-útvonalat tartanak."""
    return {
        name
        for name, value in FILE_LEVEL_PATH_CONST.findall(source)
        if value.startswith(RECORDED_FIXTURE_PREFIX)
    }


def _declarations(masked_block: str) -> dict[str, str]:
    """A blokk lokális deklarációi: név → a jobb oldal (maszkolt) szövege."""
    declarations = {
        name: rhs for name, rhs in LOCAL_DECLARATION.findall(masked_block)
    }
    declarations.update(dict(LOOP_DECLARATION.findall(masked_block)))
    return declarations


def _live_roots(
    expression: str,
    declarations: dict[str, str],
    recorded: set[str],
    seen: frozenset[str] = frozenset(),
) -> set[str]:
    """A kifejezés azon gyökerei, amelyek NEM rögzített pillanatképből jönnek.

    Egy lokális RÖGZÍTETT, ha a jobb oldala bárhol hivatkozik rögzített
    fixture-re: `_CompletionReportBaseline.read(_baselinePath)` értéke a
    pillanatkép, akárhány tagon keresztül olvassák tovább.
    """
    live: set[str] = set()
    for name in ROOT_IDENTIFIER.findall(expression):
        if name in recorded or name in seen:
            continue
        if name in declarations:
            nested = ROOT_IDENTIFIER.findall(declarations[name])
            if any(root in recorded for root in nested):
                continue
            live |= _live_roots(
                declarations[name], declarations, recorded, seen | {name}
            )
            continue
        live.add(name)
    return live


def report_expectation_pins(
    source: str, dated_doc_paths: set[str], recorded: set[str] | None = None
) -> list[str]:
    """Az élő állapotból származó VÁRT ÉRTÉKEK egy dátumozott jelentés őrében.

    A `recorded` a fájl-szintű, rögzített-fixture-útvonalat tartó konstansok
    halmaza; group-részletet vizsgálva a hívó adja meg (a részletben nincsenek
    fájl-szintű deklarációk), teljes fájlnál magából a fájlból mérjük.
    """
    if recorded is None:
        recorded = recorded_path_constants(source)
    masked = mask_strings_and_comments(source)
    findings: list[str] = []
    for start, end in group_blocks(masked):
        block = source[start:end]
        if not any(doc in block for doc in dated_doc_paths):
            continue
        declarations = _declarations(masked[start:end])
        for call in CONTAINS_CALL.finditer(masked[start:end]):
            depth = 0
            cursor = call.end() - 1
            while cursor < end - start:
                if masked[start + cursor] == "(":
                    depth += 1
                elif masked[start + cursor] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                cursor += 1
            argument = block[call.end() : cursor]
            for braced, bare in INTERPOLATION.findall(argument):
                expression = braced or bare
                for root in sorted(
                    _live_roots(expression, declarations, recorded)
                ):
                    line = source.count("\n", 0, start + call.start()) + 1
                    findings.append(
                        f"{line}: contains('…${{{expression}}}…') expects a "
                        f"value derived from the live `{root}`"
                    )
    return findings


def dated_snapshot_docs(root: Path) -> set[str]:
    """A `docs/` alatti, saját bázisukat kimondó pillanatkép-jelentések."""
    return {
        path.relative_to(root).as_posix()
        for path in sorted((root / "docs").rglob("*.md"))
        if DATED_HEADER in path.read_text(encoding="utf-8")
    }


class DatedReportGuardRuleTest(unittest.TestCase):
    """A szabály-viselkedés RÖGZÍTETT bemeneten (L612)."""

    def test_the_live_tree_pin_is_flagged(self) -> None:
        source = (FIXTURE / "a5_guard_live_tree_pin.dart.txt").read_text(encoding="utf-8")
        findings = live_tree_pins(source, {"docs/ui/chapter-15-completion-report.md"})
        self.assertEqual(len(findings), 1, findings)
        self.assertIn("ScreenReachability(Directory.current)", findings[0])

    def test_the_recorded_baseline_form_is_clean(self) -> None:
        source = (FIXTURE / "a5_guard_recorded_baseline.dart.txt").read_text(encoding="utf-8")
        self.assertEqual(
            live_tree_pins(source, {"docs/ui/chapter-15-completion-report.md"}),
            [],
        )

    def test_a_live_measurement_without_a_dated_report_is_not_flagged(self) -> None:
        """Az A1 group ÉLŐ mérése jogos — a szabály nem tiltja a live mérést."""
        source = (FIXTURE / "a1_completeness_group.dart.txt").read_text(encoding="utf-8")
        self.assertIn("Directory.current", source)
        self.assertEqual(
            live_tree_pins(source, {"docs/ui/chapter-15-completion-report.md"}),
            [],
        )


class LiveExpectationRuleTest(unittest.TestCase):
    """A VÁRT ÉRTÉK eredetének szabálya RÖGZÍTETT bemeneten (L614)."""

    DOCS = {"docs/ui/chapter-15-completion-report.md"}
    RECORDED = {"_baselinePath"}

    def test_the_live_matrix_counts_are_flagged(self) -> None:
        """Az E16-R02 javítása utáni alak: a DARABSZÁM-cellák még élők."""
        source = (FIXTURE / "a5_guard_recorded_baseline.dart.txt").read_text(
            encoding="utf-8"
        )
        findings = report_expectation_pins(source, self.DOCS, self.RECORDED)
        roots = {finding.rsplit("`", 2)[1] for finding in findings}
        self.assertEqual(roots, {"_screens", "_ViewportProfile", "_excludedCells"}, findings)

    def test_the_recorded_matrix_counts_are_clean(self) -> None:
        source = (FIXTURE / "a5_guard_recorded_matrix_counts.dart.txt").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            report_expectation_pins(source, self.DOCS, self.RECORDED), []
        )

    def test_a_live_expectation_without_a_dated_report_is_not_flagged(self) -> None:
        """A szabály nem tiltja az élő állapotból származó várt értéket —
        csak DÁTUMOZOTT jelentés őrében."""
        source = (FIXTURE / "a1_completeness_group.dart.txt").read_text(
            encoding="utf-8"
        )
        self.assertEqual(report_expectation_pins(source, self.DOCS, self.RECORDED), [])

    def test_the_recorded_constant_is_measured_from_the_file(self) -> None:
        """Teljes fájlon a rögzített gyökereket magából a fájlból mérjük."""
        source = (
            ROOT / "test" / "ui" / "goldens" / "e15_r13_full_variant_matrix_test.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("_baselinePath", recorded_path_constants(source))


class DatedReportGuardTreeTest(unittest.TestCase):
    """A KÖVETELT VÉGÁLLAPOT az élő fán."""

    def test_the_chapter_completion_reports_are_recognised_as_dated(self) -> None:
        docs = dated_snapshot_docs(ROOT)
        self.assertIn("docs/ui/chapter-15-completion-report.md", docs)
        self.assertNotIn("docs/sdd/program-completion-report.md", docs)

    def test_no_dart_test_pins_a_dated_report_to_the_live_tree(self) -> None:
        docs = dated_snapshot_docs(ROOT)
        offenders: dict[str, list[str]] = {}
        for path in sorted((ROOT / "test").rglob("*.dart")):
            findings = live_tree_pins(path.read_text(encoding="utf-8"), docs)
            if findings:
                offenders[path.relative_to(ROOT).as_posix()] = findings
        self.assertEqual(
            offenders,
            {},
            "a dated snapshot report may only be guarded against a RECORDED "
            "measurement of its own base, never against the live tree (L613)",
        )

    def test_no_dart_test_expects_a_dated_report_to_cite_a_live_value(self) -> None:
        docs = dated_snapshot_docs(ROOT)
        offenders: dict[str, list[str]] = {}
        for path in sorted((ROOT / "test").rglob("*.dart")):
            findings = report_expectation_pins(
                path.read_text(encoding="utf-8"), docs
            )
            if findings:
                offenders[path.relative_to(ROOT).as_posix()] = findings
        self.assertEqual(
            offenders,
            {},
            "the value a dated snapshot report is required to cite must come "
            "from a RECORDED snapshot of its own base, never from the live "
            "matrix/tree state (L614)",
        )


if __name__ == "__main__":
    unittest.main()
