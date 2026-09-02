#!/usr/bin/env python3
"""Staged rollout decision-packet verifier (E12-R32).

Verifies `docs/release/staged-rollout-log.md` against the schema declared in
`docs/release/rollout-decision.md`, cross-checked against two other MEASURED
sources — `docs/release/blockers.md` (open P0/P1 rows) and
`docs/operations/slo.yaml` (the required metric set and the blocking verdict
set, ADR 0484 D3). Neither of the two is duplicated into this tool's own
source or into the schema document (round brief §0.0.1 P2) — both are read
fresh on every run.

Two independently-disciplined marker-block/table parsers per document,
following the `tool/release/verify_freeze.py` precedent: every non-header,
non-separator row inside a marker block is a REQUIRED data row, and a row
that does not match its table's column count is a `VerifyError` naming the
line — never a silently-dropped row (L566/L571/L573/L575). A marker block
that is missing or empty is itself a `VerifyError`.

Exit codes (frozen, `docs/release/contract-freeze.md` row 4 — the same three
codes `verify_freeze.py`/`verify_ga_scope.py`/`verify_beta_profile.py` use;
no fourth code):
  0  every check passed
  1  a validation rule failed (R2-R8 below)
  2  a usage/format error: a missing/malformed file, a missing or empty
     marker block, a table row that does not match the expected column
     count, an unrecognized `docs/operations/slo.yaml` line shape, or an
     `approved` decision row whose `observed_hours` cell does not parse as a
     number

Rule table (round brief §0.0.2 — the same table is mirrored in
`docs/release/rollout-decision.md` for human readers):
  R1  missing/empty marker block, malformed row, missing file           -> 2
  R2  empty cell; unknown decision/step/verdict/metric; a declared step
      without exactly one decision row; a duplicate (step, metric,
      cohort); a measured_value/verdict=unknown mismatch                -> 1
  R3  source not in {machine, manual}                                   -> 1
  R4  cohort cell is not exactly one known dimension                    -> 1
  R5  approved decision while blockers.md has an open P0/P1 row         -> 1
  R6  approved decision with observed_hours < min_observation_hours     -> 1
  R7  approved step with a blocking-verdict observation row, or missing
      a required slo.yaml metric row                                    -> 1
  R8  approved decision with an empty/TBD/`<...>` decision_maker or
      rollback_target                                                   -> 1

The rules bound to `approved` (R5-R8) deliberately do not fire for
`pending`/`held`/`rolled_back` rows — the shipped skeleton is `pending`-only
and stays green without loosening the bar (round brief §0.0.2).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DEFAULT_DECISION_PATH = Path("docs/release/rollout-decision.md")
DEFAULT_LOG_PATH = Path("docs/release/staged-rollout-log.md")
DEFAULT_BLOCKERS_PATH = Path("docs/release/blockers.md")
DEFAULT_SLO_PATH = Path("docs/operations/slo.yaml")

_KNOWN_STEPS = ("stage-1", "stage-5", "stage-20")
_KNOWN_DECISIONS = {"pending", "approved", "held", "rolled_back"}
_KNOWN_SOURCES = {"machine", "manual"}
_OPEN_BLOCKER_SEVERITIES = {"P0", "P1"}
_REQUIRED_HUMAN_GATE_SENTENCE = "A rollout-százalék állítása EMBERI művelet."
# The value part deliberately excludes ',' and ':' — a comma is how a
# careless author would smuggle a second dimension into one cell (e.g.
# "platform:android,build_mode:release"), and this pattern must reject that
# (round brief §0.0.1 P7 / A7): the dashboard never silently intersects
# dimensions.
_COHORT_PATTERN = re.compile(
    r"^(all|(?:platform|app_version|build_mode):[A-Za-z0-9_.+-]+)$"
)
_PLACEHOLDER_VALUES = {"", "TBD"}
_PLACEHOLDER_BRACKET = re.compile(r"^<.*>$")


class VerifyError(Exception):
    """A usage/format error (exit 2) — parsing could not even determine
    what to check, as opposed to a validation finding (exit 1)."""


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"file not found: {path}") from error


# ---------------------------------------------------------------------------
# Generic marker-block / table helpers (precedent: verify_freeze.py)
# ---------------------------------------------------------------------------


def _extract_block_lines(
    text: str, *, begin_marker: str, end_marker: str, path: Path
) -> list[tuple[int, str]]:
    lines = text.splitlines()
    begin_index = end_index = None
    for index, line in enumerate(lines):
        if begin_marker in line:
            begin_index = index
        elif end_marker in line and begin_index is not None:
            end_index = index
            break
    if begin_index is None or end_index is None:
        raise VerifyError(
            f"{path}: markers {begin_marker!r}/{end_marker!r} not found or out of order"
        )
    return [
        (line_number, line)
        for line_number, line in enumerate(
            lines[begin_index + 1 : end_index], start=begin_index + 2
        )
    ]


def _extract_table_lines(
    text: str, *, begin_marker: str, end_marker: str, path: Path
) -> list[tuple[int, str]]:
    rows = _extract_block_lines(
        text, begin_marker=begin_marker, end_marker=end_marker, path=path
    )
    return [
        (line_number, line)
        for line_number, line in rows
        if line.strip().startswith("|")
    ]


def _is_separator(stripped_line: str) -> bool:
    return set(stripped_line.replace("|", "").strip()) <= {"-", " "}


_BACKTICK_WRAPPED = re.compile(r"^`(?P<inner>[^`]*)`$")


def _unwrap_backticks(value: str) -> str:
    match = _BACKTICK_WRAPPED.match(value)
    return match.group("inner") if match else value


def _split_row(
    line: str, *, expected_cells: int, path: Path, line_number: int
) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        raise VerifyError(
            f"{path}:{line_number}: table row does not start/end with '|' — {line!r}"
        )
    parts = stripped.split("|")
    if len(parts) != expected_cells + 2 or parts[0].strip() or parts[-1].strip():
        raise VerifyError(
            f"{path}:{line_number}: expected {expected_cells} columns — {line!r}"
        )
    return [_unwrap_backticks(cell.strip()) for cell in parts[1:-1]]


def _parse_table_rows(
    rows: list[tuple[int, str]],
    *,
    expected_cells: int,
    path: Path,
    header_first_cell: str,
) -> list[tuple[int, list[str]]]:
    """Every non-separator, non-header `|`-row is a REQUIRED data row — a row
    whose column count does not match is a `VerifyError` naming the line,
    never a silently-dropped row (L566/L571/L573/L575)."""
    parsed: list[tuple[int, list[str]]] = []
    for line_number, line in rows:
        stripped = line.strip()
        if _is_separator(stripped):
            continue
        cells = _split_row(
            line, expected_cells=expected_cells, path=path, line_number=line_number
        )
        if cells[0].strip().lower() == header_first_cell:
            continue
        parsed.append((line_number, cells))
    return parsed


# ---------------------------------------------------------------------------
# docs/release/rollout-decision.md
# ---------------------------------------------------------------------------

_STEP_ROW = re.compile(
    r"^\|\s*`(?P<step>stage-1|stage-5|stage-20)`\s*\|\s*(?P<percent>\d+)\s*\|\s*"
    r"(?P<hours>\d+)\s*\|$"
)


def load_rollout_decision(path: Path) -> dict[str, dict]:
    text = _read(path)

    gate_rows = _extract_block_lines(
        text,
        begin_marker="<!-- human-gate:begin -->",
        end_marker="<!-- human-gate:end -->",
        path=path,
    )
    gate_text = "\n".join(line for _, line in gate_rows).strip()
    if not gate_text:
        raise VerifyError(f"{path}: human-gate marker block is empty")
    if _REQUIRED_HUMAN_GATE_SENTENCE not in gate_text:
        raise VerifyError(
            f"{path}: human-gate marker block does not contain the required "
            f"sentence {_REQUIRED_HUMAN_GATE_SENTENCE!r} (A5)"
        )

    step_rows = _extract_table_lines(
        text,
        begin_marker="<!-- rollout-steps:begin -->",
        end_marker="<!-- rollout-steps:end -->",
        path=path,
    )
    if not step_rows:
        raise VerifyError(f"{path}: rollout-steps marker block is empty")

    steps: dict[str, dict] = {}
    for line_number, line in step_rows:
        stripped = line.strip()
        if stripped.startswith("| step") or _is_separator(stripped):
            continue
        match = _STEP_ROW.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: rollout-steps row does not match the "
                f"expected shape — {line!r}"
            )
        step = match.group("step")
        if step in steps:
            raise VerifyError(
                f"{path}:{line_number}: step {step!r} listed more than once"
            )
        steps[step] = {
            "rollout_percent": int(match.group("percent")),
            "min_observation_hours": int(match.group("hours")),
        }

    missing = [step for step in _KNOWN_STEPS if step not in steps]
    if missing:
        raise VerifyError(f"{path}: rollout-steps table is missing step(s) {missing}")

    return steps


# ---------------------------------------------------------------------------
# docs/release/blockers.md — id -> severity (open P0/P1 detector)
# ---------------------------------------------------------------------------

_BLOCKER_ID_START = re.compile(r"^\|\s*R-[A-Z0-9-]+\s*\|")
_BLOCKER_ROW = re.compile(r"^\|\s*(?P<id>R-[A-Z0-9-]+)\s*\|\s*(?P<severity>P[0-4])\s*\|")


def load_blocker_severities(path: Path) -> dict[str, str]:
    text = _read(path)
    severities: dict[str, str] = {}
    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not _BLOCKER_ID_START.match(stripped):
            continue
        match = _BLOCKER_ROW.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: blocker row does not match the expected "
                f"shape — {line!r}"
            )
        severities[match.group("id")] = match.group("severity")
    return severities


# ---------------------------------------------------------------------------
# docs/operations/slo.yaml — hand-rolled, fail-closed line parser (no
# package:yaml on the fan; round brief §3 — an unrecognized line shape
# inside the `slos:` block is a VerifyError, never a silently-skipped line)
# ---------------------------------------------------------------------------

_BRACKET_LIST_LINE = re.compile(r"^(?P<key>[a-zA-Z_]+):\s*\[(?P<items>.*)\]\s*$")
_SLO_ITEM_START = re.compile(r"^- id:\s*(?P<id>\S+)\s*$")
_SLO_ATTR_LINE = re.compile(r"^(?P<key>[a-zA-Z_]+):\s*(?P<value>.*)$")


def _split_bracket_list(items: str) -> list[str]:
    return [item.strip() for item in items.split(",") if item.strip()]


def load_slo_schema(path: Path) -> dict:
    text = _read(path)
    lines = text.splitlines()

    verdict_values: list[str] | None = None
    blocking_verdicts: list[str] | None = None
    slos_index: int | None = None
    for index, line in enumerate(lines):
        stripped = line.strip()
        match = _BRACKET_LIST_LINE.match(stripped)
        if match is not None:
            if match.group("key") == "verdict_values":
                verdict_values = _split_bracket_list(match.group("items"))
            elif match.group("key") == "blocking_verdicts":
                blocking_verdicts = _split_bracket_list(match.group("items"))
            continue
        if stripped == "slos:":
            slos_index = index

    if verdict_values is None:
        raise VerifyError(f'{path}: no top-level "verdict_values: [...]" line found')
    if blocking_verdicts is None:
        raise VerifyError(f'{path}: no top-level "blocking_verdicts: [...]" line found')
    if slos_index is None:
        raise VerifyError(f'{path}: no top-level "slos:" key found')

    known_ids: set[str] = set()
    required_ids: set[str] = set()
    current_id: str | None = None
    current_required = False

    def _flush() -> None:
        if current_id is not None:
            known_ids.add(current_id)
            if current_required:
                required_ids.add(current_id)

    for line in lines[slos_index + 1 :]:
        if not line.strip():
            raise VerifyError(
                f"{path}: a blank line inside the slos: block is not a "
                "recognized shape"
            )
        if line.startswith("  - id:"):
            _flush()
            match = _SLO_ITEM_START.match(line.strip())
            if match is None:
                raise VerifyError(f"{path}: malformed slos item start — {line!r}")
            current_id = match.group("id")
            current_required = False
            continue
        if line.startswith("    "):
            match = _SLO_ATTR_LINE.match(line.strip())
            if match is None:
                raise VerifyError(f"{path}: malformed slos attribute line — {line!r}")
            if match.group("key") == "required":
                current_required = match.group("value").strip() == "true"
            continue
        raise VerifyError(
            f"{path}: unrecognized line shape inside the slos: block — {line!r}"
        )
    _flush()

    if not known_ids:
        raise VerifyError(f"{path}: slos: block has no entries")

    return {
        "verdict_values": set(verdict_values),
        "blocking_verdicts": set(blocking_verdicts),
        "known_ids": known_ids,
        "required_ids": required_ids,
    }


# ---------------------------------------------------------------------------
# docs/release/staged-rollout-log.md
# ---------------------------------------------------------------------------


def load_rollout_log(path: Path) -> dict:
    text = _read(path)

    decision_rows_raw = _extract_table_lines(
        text,
        begin_marker="<!-- rollout-decisions:begin -->",
        end_marker="<!-- rollout-decisions:end -->",
        path=path,
    )
    if not decision_rows_raw:
        raise VerifyError(f"{path}: rollout-decisions marker block is empty")
    decision_rows = _parse_table_rows(
        decision_rows_raw, expected_cells=7, path=path, header_first_cell="step"
    )
    if not decision_rows:
        raise VerifyError(f"{path}: rollout-decisions table has no data rows")

    observation_rows_raw = _extract_table_lines(
        text,
        begin_marker="<!-- rollout-observations:begin -->",
        end_marker="<!-- rollout-observations:end -->",
        path=path,
    )
    if not observation_rows_raw:
        raise VerifyError(f"{path}: rollout-observations marker block is empty")
    observation_rows = _parse_table_rows(
        observation_rows_raw, expected_cells=6, path=path, header_first_cell="step"
    )
    if not observation_rows:
        raise VerifyError(f"{path}: rollout-observations table has no data rows")

    return {"decision_rows": decision_rows, "observation_rows": observation_rows}


# ---------------------------------------------------------------------------
# Validation (R2 - R8)
# ---------------------------------------------------------------------------


def validate_decisions(
    decision_rows: list[tuple[int, list[str]]],
    *,
    steps: dict[str, dict],
    blocker_severities: dict[str, str],
) -> list[str]:
    findings: list[str] = []
    open_blockers = {
        blocker_id: severity
        for blocker_id, severity in blocker_severities.items()
        if severity in _OPEN_BLOCKER_SEVERITIES
    }
    rows_by_step: dict[str, list[int]] = {}

    for line_number, cells in decision_rows:
        (
            step,
            _window_start,
            _window_end,
            observed_hours,
            decision,
            decision_maker,
            rollback_target,
        ) = cells

        if any(cell == "" for cell in cells):
            findings.append(
                f"staged-rollout-log.md:{line_number}: empty cell in decision "
                f"row (R2) — {cells}"
            )

        if step not in steps:
            findings.append(
                f"staged-rollout-log.md:{line_number}: unknown step {step!r} — "
                "not declared in rollout-decision.md (R2)"
            )
        else:
            rows_by_step.setdefault(step, []).append(line_number)

        if decision not in _KNOWN_DECISIONS:
            findings.append(
                f"staged-rollout-log.md:{line_number}: unknown decision "
                f"{decision!r} — must be one of {sorted(_KNOWN_DECISIONS)} (R2)"
            )

        if decision != "approved":
            continue

        if open_blockers:
            findings.append(
                f"staged-rollout-log.md:{line_number}: step {step!r} approved "
                f"while blockers.md has open P0/P1 row(s) {sorted(open_blockers)} (R5)"
            )

        min_hours = steps.get(step, {}).get("min_observation_hours")
        if min_hours is not None:
            try:
                observed = float(observed_hours)
            except ValueError as error:
                raise VerifyError(
                    f"staged-rollout-log.md:{line_number}: approved decision has "
                    f"a non-numeric observed_hours {observed_hours!r}"
                ) from error
            if observed < min_hours:
                findings.append(
                    f"staged-rollout-log.md:{line_number}: step {step!r} "
                    f"approved with observed_hours {observed_hours!r} < "
                    f"min_observation_hours {min_hours} (R6)"
                )

        for field_name, value in (
            ("decision_maker", decision_maker),
            ("rollback_target", rollback_target),
        ):
            if value in _PLACEHOLDER_VALUES or _PLACEHOLDER_BRACKET.match(value):
                findings.append(
                    f"staged-rollout-log.md:{line_number}: step {step!r} "
                    f"approved with a placeholder {field_name} {value!r} (R8)"
                )

    for step in steps:
        count = len(rows_by_step.get(step, []))
        if count != 1:
            findings.append(
                f"staged-rollout-log.md: step {step!r} has {count} decision "
                "row(s), expected exactly 1 (R2)"
            )

    return findings


def validate_observations(
    observation_rows: list[tuple[int, list[str]]],
    *,
    steps: dict[str, dict],
    slo_schema: dict,
) -> tuple[list[str], dict[str, list[tuple[str, str, str]]]]:
    findings: list[str] = []
    seen_keys: set[tuple[str, str, str]] = set()
    rows_by_step: dict[str, list[tuple[str, str, str]]] = {}

    for line_number, cells in observation_rows:
        step, metric, cohort, source, verdict, measured_value = cells

        if any(cell == "" for cell in cells):
            findings.append(
                f"staged-rollout-log.md:{line_number}: empty cell in "
                f"observation row (R2) — {cells}"
            )

        if step not in steps:
            findings.append(
                f"staged-rollout-log.md:{line_number}: unknown step {step!r} (R2)"
            )

        if metric not in slo_schema["known_ids"]:
            findings.append(
                f"staged-rollout-log.md:{line_number}: unknown metric "
                f"{metric!r} — not declared in slo.yaml (R2)"
            )

        if source not in _KNOWN_SOURCES:
            findings.append(
                f"staged-rollout-log.md:{line_number}: source {source!r} must "
                f"be one of {sorted(_KNOWN_SOURCES)} (R3)"
            )

        if not _COHORT_PATTERN.match(cohort):
            findings.append(
                f"staged-rollout-log.md:{line_number}: cohort {cohort!r} is not "
                "exactly one known dimension (all / platform:<value> / "
                "app_version:<value> / build_mode:<value>) (R4/A7)"
            )

        if verdict not in slo_schema["verdict_values"]:
            findings.append(
                f"staged-rollout-log.md:{line_number}: unknown verdict "
                f"{verdict!r} (R2)"
            )
        elif verdict == "unknown":
            if measured_value != "n/a":
                findings.append(
                    f"staged-rollout-log.md:{line_number}: verdict is unknown "
                    f"but measured_value {measured_value!r} is not 'n/a' (R2)"
                )
        elif measured_value == "n/a":
            findings.append(
                f"staged-rollout-log.md:{line_number}: measured_value is "
                f"'n/a' but verdict is {verdict!r}, not unknown (R2)"
            )

        key = (step, metric, cohort)
        if key in seen_keys:
            findings.append(
                f"staged-rollout-log.md:{line_number}: duplicate "
                f"(step, metric, cohort) {key} (R2)"
            )
        seen_keys.add(key)

        rows_by_step.setdefault(step, []).append((metric, cohort, verdict))

    return findings, rows_by_step


def validate_approved_slo_coverage(
    decision_rows: list[tuple[int, list[str]]],
    rows_by_step: dict[str, list[tuple[str, str, str]]],
    slo_schema: dict,
) -> list[str]:
    findings: list[str] = []
    approved_steps = {cells[0] for _, cells in decision_rows if cells[4] == "approved"}
    for step in approved_steps:
        rows = rows_by_step.get(step, [])
        verdicts = {verdict for _, _, verdict in rows}
        blocking_hit = verdicts & slo_schema["blocking_verdicts"]
        if blocking_hit:
            findings.append(
                f"staged-rollout-log.md: approved step {step!r} has "
                f"observation row(s) with blocking verdict(s) "
                f"{sorted(blocking_hit)} (R7)"
            )
        covered_metrics = {metric for metric, _, _ in rows}
        missing_required = slo_schema["required_ids"] - covered_metrics
        if missing_required:
            findings.append(
                f"staged-rollout-log.md: approved step {step!r} is missing "
                "observation row(s) for required slo.yaml metric(s) "
                f"{sorted(missing_required)} (R7)"
            )
    return findings


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decision", type=Path, default=DEFAULT_DECISION_PATH)
    parser.add_argument("--log", type=Path, default=DEFAULT_LOG_PATH)
    parser.add_argument("--blockers", type=Path, default=DEFAULT_BLOCKERS_PATH)
    parser.add_argument("--slo", type=Path, default=DEFAULT_SLO_PATH)
    args = parser.parse_args(argv)

    try:
        steps = load_rollout_decision(args.decision)
        blocker_severities = load_blocker_severities(args.blockers)
        slo_schema = load_slo_schema(args.slo)
        log = load_rollout_log(args.log)

        findings: list[str] = []
        findings += validate_decisions(
            log["decision_rows"], steps=steps, blocker_severities=blocker_severities
        )
        observation_findings, rows_by_step = validate_observations(
            log["observation_rows"], steps=steps, slo_schema=slo_schema
        )
        findings += observation_findings
        findings += validate_approved_slo_coverage(
            log["decision_rows"], rows_by_step, slo_schema
        )
    except VerifyError as error:
        print(f"verify_rollout_decision: {error}", file=sys.stderr)
        return 2

    if findings:
        print(f"verify_rollout_decision: {len(findings)} finding(s):", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1

    print(
        f"verify_rollout_decision: ok — {len(log['decision_rows'])} decision "
        f"row(s), {len(log['observation_rows'])} observation row(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
