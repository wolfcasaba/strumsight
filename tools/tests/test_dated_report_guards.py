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
`fixtures/e16_r02_dated_report_guard/` alatti három `.txt` a valódi, szó
szerint másolt A5 (javítás előtti és utáni) és A1 group. A `test/` fát végigfutó
cella a KÖVETELT VÉGÁLLAPOTOT pinneli (nulla lelet), nem egy kör munkájának
hiányát — azt csak úgy lehet pirosra vinni, ha valaki újra bevezeti a
hibaosztályt.
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


if __name__ == "__main__":
    unittest.main()
