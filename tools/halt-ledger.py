#!/usr/bin/env python3
"""Report repeated halt classes and their machine-readable guard references."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


HALT_LINE = re.compile(r"^halt=(.+?)\s*$", re.MULTILINE)
ROUND_LINE = re.compile(r"^round=(.+?)\s*$", re.MULTILINE)
HALTED_AT_LINE = re.compile(r"^halted_at=(.+?)\s*$", re.MULTILINE)
LESSON_HEADING = re.compile(r"^##\s+L\d+\b.*$", re.MULTILINE)
GUARD_TEST_LINE = re.compile(r"^\s*\*\*Őrteszt:\*\*\s+(.+?)\s*$", re.MULTILINE)


@dataclass(frozen=True)
class HaltRecord:
    """A parsed halt record, retaining the record fields used by the ledger."""

    halt: str
    round_id: str | None
    halted_at: str | None


def _field_value(pattern: re.Pattern[str], text: str) -> str | None:
    match = pattern.search(text)
    return match.group(1).strip() if match else None


def read_halt_records(repo: Path) -> list[HaltRecord]:
    """Read halt records without changing the repository."""
    records: list[HaltRecord] = []
    for path in sorted((repo / ".pipeline").glob("halted-*.txt")):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        halt = _field_value(HALT_LINE, text)
        if halt:
            records.append(
                HaltRecord(
                    halt=halt,
                    round_id=_field_value(ROUND_LINE, text),
                    halted_at=_field_value(HALTED_AT_LINE, text),
                )
            )
    return records


def read_lessons(repo: Path) -> list[str]:
    """Split the lessons document into its numbered lesson sections."""
    try:
        text = (repo / "docs" / "LESSONS.md").read_text(encoding="utf-8")
    except OSError:
        return []
    headings = list(LESSON_HEADING.finditer(text))
    return [
        text[
            match.start(): headings[index + 1].start() if index + 1 < len(headings) else len(text)
        ]
        for index, match in enumerate(headings)
    ]


def _mentions_halt(text: str, halt: str) -> bool:
    return re.search(r"(?<!\w)" + re.escape(halt) + r"(?!\w)", text) is not None


def guard_tests_for(halt: str, lessons: Sequence[str]) -> list[str]:
    """Return the distinct guard references from lessons that mention this halt code."""
    guard_tests: list[str] = []
    for lesson in lessons:
        if not _mentions_halt(lesson, halt):
            continue
        for guard in GUARD_TEST_LINE.findall(lesson):
            if guard not in guard_tests:
                guard_tests.append(guard)
    return guard_tests


def build_report(repo: Path) -> list[dict[str, object]]:
    """Build the serialisable halt-class report."""
    counts = Counter(record.halt for record in read_halt_records(repo))
    lessons = read_lessons(repo)
    report: list[dict[str, object]] = []
    for halt in sorted(counts):
        guard_tests = guard_tests_for(halt, lessons)
        occurrences = counts[halt]
        warning = occurrences >= 2 and not guard_tests
        status = "fedett" if guard_tests else "hiányzik" if warning else "nem jelölt"
        report.append(
            {
                "halt": halt,
                "occurrences": occurrences,
                "guard_tests": guard_tests,
                "status": status,
                "warning": warning,
            }
        )
    return report


def format_markdown(report: Sequence[dict[str, object]]) -> str:
    """Render the serialisable report as a compact Markdown table."""
    lines = ["# Halt-főkönyv", ""]
    if not report:
        return "\n".join([*lines, "Nincs halt-rekord.", ""])
    lines.extend(
        [
            "| halt-osztály | előfordulás | hivatkozott őrteszt | állapot | figyelmeztetés |",
            "| --- | ---: | --- | --- | --- |",
        ]
    )
    for row in report:
        guards = ", ".join(row["guard_tests"]) or "—"
        warning = "igen" if row["warning"] else "nem"
        lines.append(
            f"| {row['halt']} | {row['occurrences']} | {guards} | {row['status']} | {warning} |"
        )
    return "\n".join([*lines, ""])


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="repository root")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    report = build_report(arguments.repo)
    if arguments.format == "json":
        print(json.dumps({"halt_classes": report}, ensure_ascii=False, indent=2))
    else:
        print(format_markdown(report), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
