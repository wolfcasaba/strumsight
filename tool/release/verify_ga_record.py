#!/usr/bin/env python3
"""GA record verifier (E12-R33, round brief §0.0.1 P2-P5).

Validates `docs/release/ga-record.md` against MEASURED sources of truth —
never against a hand-typed copy baked into this tool:

  * `pubspec.yaml`, `assets/ml/model_manifest.json`,
    `assets/tutor_knowledge/manifest.json` — the same three declared inputs
    `tool/generate_release_manifest.dart` reads (round brief §0.0.1 P3).
    There is no static release-manifest file on the tree and this tool never
    invokes `dart run` — it recomputes each version field directly from
    these inputs every run (A2).
  * `docs/release/ga-scope.md`'s `<!-- ga-scope-capabilities:begin/end -->`
    block — the record's flag-profile snapshot must match it key-for-key
    (A3, round brief §0.0.1 P4).
  * `docs/release/staged-rollout-log.md` and `docs/release/blockers.md` — a
    record whose `ga_status` field is `ga` must be backed by every `stage-*`
    decision being `approved` and by zero open P0/P1 blocker rows (A7, round
    brief §0.0.1 P2 / §5.4). Neither source is duplicated into this tool;
    both are read fresh on every run.

Two independently-disciplined marker-block/table parsers, the
`tool/release/verify_rollout_decision.py` / `tool/release/verify_ga_scope.py`
precedent: every non-header, non-separator row inside a marker block is a
REQUIRED data row, and a row that does not match its table's column count is
a `VerifyError` naming the line — never a silently-dropped row. A marker
block that is missing or empty is itself a `VerifyError`.

Exit codes (the `docs/release/contract-freeze.md` row-4 convention, shared
by every `verify_*.py` tool on this tree — no fourth code):
  0  every check passed
  1  a validation rule failed (A1-A7 below)
  2  a usage/format error: a missing/malformed file, a missing or empty
     marker block, or a table/single-value row that does not match its
     expected shape

Rule table:
  A1  a required version/flag field is missing, duplicated, or carries an
      empty/TBD/`<...>` placeholder value                              -> 1
  A2  a recorded version field does not match the value recomputed from
      pubspec.yaml / the two asset manifests                           -> 1
  A3  the recorded flag-profile snapshot's key set or values do not match
      `docs/release/ga-scope.md`'s capability table                    -> 1
  A4  `rollback_target` is empty/TBD/`<...>` or does not resolve to an
      existing repo-relative path                                      -> 1
  A6  the record does not carry the required human-publish sentence      -> 1
  A7  `ga_status: ga` while a `staged-rollout-log.md` `stage-*` decision is
      not `approved`, or `blockers.md` has an open P0/P1 row            -> 1
  (an unknown `ga_status` value is also an A1-class finding)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

DEFAULT_RECORD_PATH = Path("docs/release/ga-record.md")
DEFAULT_PUBSPEC_PATH = Path("pubspec.yaml")
DEFAULT_ML_MANIFEST_PATH = Path("assets/ml/model_manifest.json")
DEFAULT_KNOWLEDGE_MANIFEST_PATH = Path("assets/tutor_knowledge/manifest.json")
DEFAULT_GA_SCOPE_PATH = Path("docs/release/ga-scope.md")
DEFAULT_ROLLOUT_LOG_PATH = Path("docs/release/staged-rollout-log.md")
DEFAULT_BLOCKERS_PATH = Path("docs/release/blockers.md")

_KNOWN_GA_STATUSES = {"not-yet", "in-progress", "ga"}
_KNOWN_STEPS = ("stage-1", "stage-5", "stage-20")
_OPEN_BLOCKER_SEVERITIES = {"P0", "P1"}
_PLACEHOLDER_VALUES = {"", "TBD"}
_PLACEHOLDER_BRACKET = re.compile(r"^<.*>$")
_REQUIRED_HUMAN_PUBLISH_SENTENCE = "A GA-közzététel EMBERI művelet."

_VERSION_FIELDS = (
    "app_version",
    "app_build_number",
    "ml_manifest_schema_version",
    "ml_manifest_sha256",
    "ml_model_count",
    "knowledge_manifest_schema_version",
    "knowledge_manifest_sha256",
    "knowledge_document_count",
)

_PUBSPEC_VERSION_LINE = re.compile(
    r"^version:\s*([0-9A-Za-z][0-9A-Za-z._-]*)\+([0-9]+)\s*$"
)


class VerifyError(Exception):
    """A usage/format error (exit 2) — parsing could not even determine
    what to check, as opposed to a validation finding (exit 1)."""


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"file not found: {path}") from error


# ---------------------------------------------------------------------------
# Generic marker-block / table helpers (precedent: verify_rollout_decision.py)
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
    if not rows or not any(line.strip() for _, line in rows):
        raise VerifyError(
            f"{path}: {begin_marker!r}/{end_marker!r} marker block is empty"
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
    never a silently-dropped row."""
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


def _extract_single_value(
    text: str, *, begin_marker: str, end_marker: str, path: Path, key: str
) -> str:
    lines = _extract_block_lines(
        text, begin_marker=begin_marker, end_marker=end_marker, path=path
    )
    content_lines = [(number, line) for number, line in lines if line.strip()]
    if len(content_lines) != 1:
        raise VerifyError(
            f"{path}: {begin_marker!r}/{end_marker!r} block must contain "
            f"exactly one non-blank line, found {len(content_lines)}"
        )
    line_number, line = content_lines[0]
    prefix = f"{key}:"
    stripped = line.strip()
    if not stripped.startswith(prefix):
        raise VerifyError(
            f"{path}:{line_number}: expected \"{key}: <value>\", got: {line!r}"
        )
    return stripped[len(prefix) :].strip()


# ---------------------------------------------------------------------------
# docs/release/ga-record.md
# ---------------------------------------------------------------------------


def load_ga_status(text: str, path: Path) -> str:
    return _extract_single_value(
        text,
        begin_marker="<!-- ga-status:begin -->",
        end_marker="<!-- ga-status:end -->",
        path=path,
        key="ga_status",
    )


def load_version_table(text: str, path: Path) -> dict[str, str]:
    rows = _extract_table_lines(
        text,
        begin_marker="<!-- ga-record-version:begin -->",
        end_marker="<!-- ga-record-version:end -->",
        path=path,
    )
    parsed = _parse_table_rows(
        rows, expected_cells=2, path=path, header_first_cell="field"
    )
    values: dict[str, str] = {}
    for line_number, (field, value) in parsed:
        if field in values:
            raise VerifyError(
                f"{path}:{line_number}: field {field!r} listed more than once"
            )
        values[field] = value
    return values


def load_flags_table(text: str, path: Path) -> dict[str, tuple[str, str]]:
    rows = _extract_table_lines(
        text,
        begin_marker="<!-- ga-record-flags:begin -->",
        end_marker="<!-- ga-record-flags:end -->",
        path=path,
    )
    parsed = _parse_table_rows(
        rows, expected_cells=3, path=path, header_first_cell="flag_key"
    )
    flags: dict[str, tuple[str, str]] = {}
    for line_number, (key, classification, production_default) in parsed:
        if key in flags:
            raise VerifyError(
                f"{path}:{line_number}: flag {key!r} listed more than once"
            )
        flags[key] = (classification, production_default)
    return flags


def load_rollback_target(text: str, path: Path) -> str:
    return _extract_single_value(
        text,
        begin_marker="<!-- ga-record-rollback:begin -->",
        end_marker="<!-- ga-record-rollback:end -->",
        path=path,
        key="rollback_target",
    )


# ---------------------------------------------------------------------------
# pubspec.yaml + the two asset manifests — the manifest's declared inputs
# (round brief §0.0.1 P3: no static release-manifest file, no `dart run`)
# ---------------------------------------------------------------------------


def parse_pubspec_version(text: str, path: Path) -> tuple[str, int]:
    for raw_line in text.split("\n"):
        line = raw_line.rstrip()
        if not line.startswith("version:"):
            continue
        match = _PUBSPEC_VERSION_LINE.match(line)
        if match is None:
            raise VerifyError(
                f"{path}: version line does not match <version>+<buildNumber>: "
                f"{line!r}"
            )
        return match.group(1), int(match.group(2))
    raise VerifyError(f'{path}: no top-level "version:" line found')


def _load_asset_manifest_facts(
    path: Path, *, schema_key: str, list_key: str
) -> dict[str, object]:
    try:
        raw_bytes = path.read_bytes()
    except FileNotFoundError as error:
        raise VerifyError(f"file not found: {path}") from error
    try:
        document = json.loads(raw_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerifyError(f"{path}: not valid JSON: {error}") from error
    if not isinstance(document, dict):
        raise VerifyError(f"{path}: does not decode to a JSON object")
    schema_version = document.get(schema_key)
    if not isinstance(schema_version, int):
        raise VerifyError(f'{path}: missing an integer "{schema_key}"')
    items = document.get(list_key)
    if not isinstance(items, list):
        raise VerifyError(f'{path}: missing a "{list_key}" list')
    return {
        "schema_version": schema_version,
        "count": len(items),
        "sha256": hashlib.sha256(raw_bytes).hexdigest(),
    }


def compute_expected_version(
    pubspec_path: Path, ml_manifest_path: Path, knowledge_manifest_path: Path
) -> dict[str, str]:
    pubspec_text = _read(pubspec_path)
    app_version, app_build_number = parse_pubspec_version(pubspec_text, pubspec_path)

    ml_facts = _load_asset_manifest_facts(
        ml_manifest_path, schema_key="schema_version", list_key="models"
    )
    knowledge_facts = _load_asset_manifest_facts(
        knowledge_manifest_path, schema_key="schemaVersion", list_key="documents"
    )

    return {
        "app_version": app_version,
        "app_build_number": str(app_build_number),
        "ml_manifest_schema_version": str(ml_facts["schema_version"]),
        "ml_manifest_sha256": str(ml_facts["sha256"]),
        "ml_model_count": str(ml_facts["count"]),
        "knowledge_manifest_schema_version": str(knowledge_facts["schema_version"]),
        "knowledge_manifest_sha256": str(knowledge_facts["sha256"]),
        "knowledge_document_count": str(knowledge_facts["count"]),
    }


# ---------------------------------------------------------------------------
# docs/release/ga-scope.md — capability classification + production_default
# ---------------------------------------------------------------------------

# `| `flagKey` | `classification` | `productionDefault` | `evidence/path` | free-text note |`
_CAPABILITY_ROW = re.compile(
    r"^\|\s*`(?P<key>[^`]+)`\s*\|\s*`(?P<classification>[^`]+)`\s*\|\s*"
    r"`(?P<production_default>[^`]+)`\s*\|\s*`(?P<evidence>[^`]+)`\s*\|\s*"
    r"(?P<note>.*?)\s*\|\s*$"
)


def load_ga_scope_flags(path: Path) -> dict[str, tuple[str, str]]:
    text = _read(path)
    rows = _extract_table_lines(
        text,
        begin_marker="<!-- ga-scope-capabilities:begin -->",
        end_marker="<!-- ga-scope-capabilities:end -->",
        path=path,
    )
    flags: dict[str, tuple[str, str]] = {}
    for line_number, line in rows:
        stripped = line.strip()
        if stripped.startswith("| flag_key") or _is_separator(stripped):
            continue
        match = _CAPABILITY_ROW.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: capability row does not match the "
                f"expected shape — {line!r}"
            )
        key = match.group("key")
        if key in flags:
            raise VerifyError(
                f"{path}:{line_number}: capability {key!r} listed more than once"
            )
        flags[key] = (match.group("classification"), match.group("production_default"))
    return flags


# ---------------------------------------------------------------------------
# docs/release/staged-rollout-log.md — stage-* decisions only
# ---------------------------------------------------------------------------


def load_stage_decisions(path: Path) -> dict[str, str]:
    text = _read(path)
    rows = _extract_table_lines(
        text,
        begin_marker="<!-- rollout-decisions:begin -->",
        end_marker="<!-- rollout-decisions:end -->",
        path=path,
    )
    parsed = _parse_table_rows(
        rows, expected_cells=7, path=path, header_first_cell="step"
    )
    decisions: dict[str, str] = {}
    for line_number, cells in parsed:
        step, _window_start, _window_end, _observed_hours, decision, _maker, _rollback = (
            cells
        )
        if step in decisions:
            raise VerifyError(
                f"{path}:{line_number}: step {step!r} listed more than once"
            )
        decisions[step] = decision
    return decisions


# ---------------------------------------------------------------------------
# docs/release/blockers.md — id -> severity (open P0/P1 detector)
# ---------------------------------------------------------------------------

_BLOCKER_ID_START = re.compile(r"^\|\s*R-[A-Z0-9-]+\s*\|")
_BLOCKER_ROW = re.compile(r"^\|\s*(?P<id>R-[A-Z0-9-]+)\s*\|\s*(?P<severity>P[0-4])\s*\|")


def load_open_blockers(path: Path) -> list[str]:
    text = _read(path)
    ids: list[str] = []
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
        if match.group("severity") in _OPEN_BLOCKER_SEVERITIES:
            ids.append(match.group("id"))
    return ids


# ---------------------------------------------------------------------------
# Validation (A1 - A7)
# ---------------------------------------------------------------------------


def validate_ga_status(ga_status: str) -> list[str]:
    if ga_status not in _KNOWN_GA_STATUSES:
        return [
            f"ga-record.md: unknown ga_status {ga_status!r} — must be one of "
            f"{sorted(_KNOWN_GA_STATUSES)} (A1)"
        ]
    return []


def validate_version(
    recorded: dict[str, str], expected: dict[str, str]
) -> list[str]:
    findings: list[str] = []

    missing = [field for field in _VERSION_FIELDS if field not in recorded]
    if missing:
        findings.append(f"ga-record.md: missing version field(s) {missing} (A1)")

    extra = sorted(set(recorded) - set(_VERSION_FIELDS))
    if extra:
        findings.append(f"ga-record.md: unrecognized version field(s) {extra} (A1)")

    for field in _VERSION_FIELDS:
        if field not in recorded:
            continue
        value = recorded[field]
        if value in _PLACEHOLDER_VALUES or _PLACEHOLDER_BRACKET.match(value):
            findings.append(
                f"ga-record.md: version field {field!r} has a placeholder "
                f"value {value!r} (A1)"
            )
            continue
        if value != expected[field]:
            findings.append(
                f"ga-record.md: version field {field!r} is {value!r}, but the "
                f"value recomputed from pubspec.yaml/the asset manifests is "
                f"{expected[field]!r} (A2)"
            )

    return findings


def validate_flags(
    recorded: dict[str, tuple[str, str]], expected: dict[str, tuple[str, str]]
) -> list[str]:
    findings: list[str] = []

    missing = sorted(set(expected) - set(recorded))
    for key in missing:
        findings.append(
            f"ga-record.md: flag {key!r} is in ga-scope.md but missing from the "
            "record's flag-profile snapshot (A3)"
        )

    extra = sorted(set(recorded) - set(expected))
    for key in extra:
        findings.append(
            f"ga-record.md: flag {key!r} is in the record's flag-profile "
            "snapshot but not in ga-scope.md (A3)"
        )

    for key in sorted(set(recorded) & set(expected)):
        recorded_classification, recorded_default = recorded[key]
        expected_classification, expected_default = expected[key]
        if recorded_classification in _PLACEHOLDER_VALUES or recorded_default in _PLACEHOLDER_VALUES:
            findings.append(
                f"ga-record.md: flag {key!r} has an empty classification/"
                "production_default cell (A1)"
            )
            continue
        if (recorded_classification, recorded_default) != (
            expected_classification,
            expected_default,
        ):
            findings.append(
                f"ga-record.md: flag {key!r} snapshot is "
                f"{(recorded_classification, recorded_default)!r}, but "
                f"ga-scope.md classifies it as "
                f"{(expected_classification, expected_default)!r} (A3)"
            )

    return findings


def validate_rollback(rollback_target: str) -> list[str]:
    if rollback_target in _PLACEHOLDER_VALUES or _PLACEHOLDER_BRACKET.match(
        rollback_target
    ):
        return [
            f"ga-record.md: rollback_target has a placeholder value "
            f"{rollback_target!r} (A4)"
        ]
    if not Path(rollback_target).exists():
        return [
            f"ga-record.md: rollback_target {rollback_target!r} does not "
            "resolve to an existing path on this tree (A4)"
        ]
    return []


def validate_human_publish_sentence(text: str) -> list[str]:
    if _REQUIRED_HUMAN_PUBLISH_SENTENCE not in text:
        return [
            "ga-record.md: does not contain the required sentence "
            f"{_REQUIRED_HUMAN_PUBLISH_SENTENCE!r} (A6)"
        ]
    return []


def validate_ga_status_gate(
    ga_status: str, stage_decisions: dict[str, str], open_blockers: list[str]
) -> list[str]:
    if ga_status != "ga":
        return []

    findings: list[str] = []
    non_approved = [
        step for step in _KNOWN_STEPS if stage_decisions.get(step) != "approved"
    ]
    if non_approved:
        findings.append(
            "ga-record.md: ga_status is 'ga' but staged-rollout-log.md step(s) "
            f"{non_approved} are not 'approved' (A7)"
        )
    if open_blockers:
        findings.append(
            "ga-record.md: ga_status is 'ga' but blockers.md has open P0/P1 "
            f"row(s) {sorted(open_blockers)} (A7)"
        )
    return findings


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", type=Path, default=DEFAULT_RECORD_PATH)
    parser.add_argument("--pubspec", type=Path, default=DEFAULT_PUBSPEC_PATH)
    parser.add_argument("--ml-manifest", type=Path, default=DEFAULT_ML_MANIFEST_PATH)
    parser.add_argument(
        "--knowledge-manifest", type=Path, default=DEFAULT_KNOWLEDGE_MANIFEST_PATH
    )
    parser.add_argument("--ga-scope", type=Path, default=DEFAULT_GA_SCOPE_PATH)
    parser.add_argument("--rollout-log", type=Path, default=DEFAULT_ROLLOUT_LOG_PATH)
    parser.add_argument("--blockers", type=Path, default=DEFAULT_BLOCKERS_PATH)
    args = parser.parse_args(argv)

    try:
        record_text = _read(args.record)
        ga_status = load_ga_status(record_text, args.record)
        recorded_version = load_version_table(record_text, args.record)
        recorded_flags = load_flags_table(record_text, args.record)
        rollback_target = load_rollback_target(record_text, args.record)

        expected_version = compute_expected_version(
            args.pubspec, args.ml_manifest, args.knowledge_manifest
        )
        expected_flags = load_ga_scope_flags(args.ga_scope)
        stage_decisions = load_stage_decisions(args.rollout_log)
        open_blockers = load_open_blockers(args.blockers)
    except VerifyError as error:
        print(f"verify_ga_record: {error}", file=sys.stderr)
        return 2

    findings: list[str] = []
    findings += validate_ga_status(ga_status)
    findings += validate_version(recorded_version, expected_version)
    findings += validate_flags(recorded_flags, expected_flags)
    findings += validate_rollback(rollback_target)
    findings += validate_human_publish_sentence(record_text)
    findings += validate_ga_status_gate(ga_status, stage_decisions, open_blockers)

    if findings:
        print(f"verify_ga_record: {len(findings)} finding(s):", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1

    print(
        f"verify_ga_record: ok — ga_status={ga_status}, "
        f"{len(recorded_flags)} flag(s), rollback_target={rollback_target!r}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
