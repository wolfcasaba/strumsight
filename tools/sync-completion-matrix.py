#!/usr/bin/env python3
"""Keep the §3 completion matrix's counts equal to the measured queue.

WHY THIS EXISTS (measured, E15-R09 / H5 self-heal, ADR 0112, 2026-09-03).
`docs/sdd/program-completion-report.md` §3 carries hand-written per-lane
done/pending/prepared/hold counts, and `test/tooling/program_completion_test.dart`
A1 pins them to strict equality against the LIVE
`docs/execution/pipeline-queue.tsv`. The report says so itself:

    "minden jövőbeli kör, amely egy queue-sort `pending` → `done`-ra vált
     (E14, E15, E16, E99 ...), PIROSRA váltja ezt a cellát, amíg a matrix
     megfelelő sora nem frissül"

and defers the fix to "egy KÖVETKEZŐ kör" (`docs/LESSONS.md` L590). It
detonated on the very first queue flip after that report merged: the E15-R08
merge (`e9691f74`) moved E15 from done=8/pending=6 to done=9/pending=5, main's
Full Gate went red (run 33704424852, 2 failing cells), and the round pipeline —
which refuses to start a round over a red `main` — stood still for 89 minutes
before the E15-R09 halt was even reached.

The measure is NOT weakened: A1 keeps its strict equality. What changes is that
the counts stop being hand-maintained. The driver runs `--write` in the same
place it flips a queue row (`tools/round-pipeline.sh`, merge branch), so the
report follows the queue mechanically instead of depending on an orchestrator
remembering to edit a markdown table.

Only the four count columns are touched. The `Riport-státusz` prose is
human-authored honesty (A2 reads it word-wise) and is never machine-written.

Usage:
    tools/sync-completion-matrix.py --check    # exit 1 on drift, print it
    tools/sync-completion-matrix.py --write    # rewrite the count cells
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
QUEUE_PATH = REPO_ROOT / "docs" / "execution" / "pipeline-queue.tsv"
REPORT_PATH = REPO_ROOT / "docs" / "sdd" / "program-completion-report.md"

# Identical to `_queueDataLinePattern` in test/tooling/program_completion_test.dart.
QUEUE_DATA_LINE = re.compile(r"^(E\d+)-R\d+\t.*\t([A-Za-z]+)$")

MATRIX_HEADER_PREFIX = "| Sáv |"
NO_QUEUE_ROWS = "—"
STATUS_COLUMNS = ("done", "pending", "prepared", "hold")
# Cell indices of done/pending/prepared/hold in the 9-column matrix row.
FIRST_COUNT_CELL = 3


def parse_queue_counts(tsv: str) -> dict[str, dict[str, int]]:
    """Count rows per queue prefix per status — the A1 measurement."""
    counts: dict[str, dict[str, int]] = {}
    for line in tsv.split("\n"):
        match = QUEUE_DATA_LINE.match(line.strip())
        if match is None:
            continue
        prefix, status = match.group(1), match.group(2)
        by_status = counts.setdefault(prefix, {})
        by_status[status] = by_status.get(status, 0) + 1
    return counts


def split_pipe_row(line: str) -> list[str]:
    trimmed = line.strip()
    if trimmed.startswith("|"):
        trimmed = trimmed[1:]
    if trimmed.endswith("|"):
        trimmed = trimmed[:-1]
    return [cell.strip() for cell in trimmed.split("|")]


def matrix_row_indices(lines: list[str]) -> list[int]:
    """Line indices of the §3 matrix data rows (header + separator skipped)."""
    header = next(
        (i for i, line in enumerate(lines) if line.strip().startswith(MATRIX_HEADER_PREFIX)),
        None,
    )
    if header is None:
        raise SystemExit(
            f"{REPORT_PATH}: no '{MATRIX_HEADER_PREFIX}' completion-matrix header found"
        )
    indices = []
    for i in range(header + 2, len(lines)):
        if not lines[i].strip().startswith("|"):
            break
        indices.append(i)
    return indices


def sync_report(report: str, counts: dict[str, dict[str, int]]) -> tuple[str, list[str]]:
    """Return the report with synced count cells, plus one line per change."""
    lines = report.split("\n")
    changes: list[str] = []
    for index in matrix_row_indices(lines):
        cells = split_pipe_row(lines[index])
        if len(cells) < 9:
            raise SystemExit(
                f"{REPORT_PATH}: completion-matrix row has {len(cells)} cell(s), "
                f'expected 9: "{lines[index]}"'
            )
        prefix = cells[2]
        if prefix == NO_QUEUE_ROWS:
            continue
        measured = counts.get(prefix, {})
        row_changed = False
        for offset, status in enumerate(STATUS_COLUMNS):
            cell = FIRST_COUNT_CELL + offset
            reported = cells[cell]
            expected = str(measured.get(status, 0))
            if reported != expected:
                changes.append(
                    f"{cells[0]} ({prefix}): reports {status}={reported}, "
                    f"queue measures {status}={expected}"
                )
                cells[cell] = expected
                row_changed = True
        if row_changed:
            lines[index] = "| " + " | ".join(cells) + " |"
    return "\n".join(lines), changes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report drift, exit 1")
    mode.add_argument("--write", action="store_true", help="rewrite the count cells")
    parser.add_argument("--queue", type=Path, default=QUEUE_PATH)
    parser.add_argument("--report", type=Path, default=REPORT_PATH)
    args = parser.parse_args(argv)

    counts = parse_queue_counts(args.queue.read_text(encoding="utf-8"))
    original = args.report.read_text(encoding="utf-8")
    synced, changes = sync_report(original, counts)

    if not changes:
        print("completion matrix is in sync with the queue")
        return 0

    for change in changes:
        print(change)

    if args.check:
        print(
            f"\n{len(changes)} drifted cell(s) — run: tools/sync-completion-matrix.py --write",
            file=sys.stderr,
        )
        return 1

    args.report.write_text(synced, encoding="utf-8")
    print(f"\n{len(changes)} cell(s) synced in {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
