#!/usr/bin/env python3
"""Benchmark-record regression comparator (E12-R14, ADR 0474).

Reads two benchmark-record documents — `--baseline` and `--candidate`,
both shaped `{"records": [...]}` per `tool/benchmarks/benchmark_record.dart`
(that Dart file is the single source of truth for the field list; this
module re-validates the same contract independently rather than trusting
the caller, because a JSON document can come from anywhere) — and reports,
for every `kind: "measured"` metric in the baseline, whether the candidate
regressed past the warn or fail threshold.

Only `kind: "measured"` records are ever compared (ADR 0474 D3): an
`upperBound`, `derivedContract` or `target` record is a documented number,
not a device measurement, and mixing it into a regression comparison would
fabricate a measurement that never happened. A baseline `measured` metric
missing from the candidate is reported `unknown`, never dropped from the
summary (ADR 0474 D5) — a report that is green because it did not measure
something is worse than a report that is red.

Regression direction is per-record (ADR 0474 D7): `lowerIsBetter` metrics
regress on increase, `higherIsBetter` metrics regress on decrease. There is
no default direction. The two-tier threshold — 5.0% warn, 10.0% fail, both
boundaries INCLUSIVE (ADR 0474 D6) — is fixed in this file, not a CLI flag:
a caller-supplied threshold would be exactly the "looser in CI" weakening
the ADR forbids.

Exit codes:
  0  every measured metric is known and no metric is a fail
  1  at least one measured metric is unknown (missing from the candidate)
     or regressed past the fail threshold
  2  usage or record-format error (missing/invalid metadata, ADR 0474 D1)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCHEMA_VERSION = 1

KINDS = {"measured", "upperBound", "derivedContract", "target"}
DIRECTIONS = {"lowerIsBetter", "higherIsBetter"}
DEVICE_IDS = {
    "pixel_6a",
    "pixel_7",
    "samsung_galaxy_a54",
    "xiaomi_redmi_note_12",
    "ci_host",
}

# Fixed in the record, not a CLI parameter (ADR 0474 D6): both boundaries
# are inclusive, so a delta exactly on the threshold already counts.
WARN_THRESHOLD = 0.05
FAIL_THRESHOLD = 0.10


class RecordFormatError(ValueError):
    """A benchmark-record document failed the ADR 0474 D1 contract."""


def _require_non_empty_string(record: dict, key: str, where: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value:
        raise RecordFormatError(f"{where}: missing or empty required field {key!r}")
    return value


def _require_int(record: dict, key: str, where: str) -> int:
    value = record.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise RecordFormatError(
            f"{where}: missing or non-integer required field {key!r}"
        )
    return value


def _require_number(record: dict, key: str, where: str) -> float:
    value = record.get(key)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise RecordFormatError(
            f"{where}: missing or non-numeric required field {key!r}"
        )
    return float(value)


def validate_record(record: object, where: str) -> dict:
    """Validates one record against the ADR 0474 D1/D2/D3/D7/D8 contract.

    Returns the record unchanged (as a dict) on success; raises
    `RecordFormatError` naming the first problem otherwise. There is no
    partially-valid record and no defaulted field.
    """
    if not isinstance(record, dict):
        raise RecordFormatError(f"{where}: record must be a JSON object")

    schema_version = _require_int(record, "schemaVersion", where)
    if schema_version != SCHEMA_VERSION:
        raise RecordFormatError(
            f"{where}: unsupported schemaVersion {schema_version} "
            f"(expected {SCHEMA_VERSION})"
        )

    kind = _require_non_empty_string(record, "kind", where)
    if kind not in KINDS:
        raise RecordFormatError(f"{where}: unknown kind {kind!r} (expected {KINDS})")

    direction = _require_non_empty_string(record, "direction", where)
    if direction not in DIRECTIONS:
        raise RecordFormatError(
            f"{where}: unknown direction {direction!r} (expected {DIRECTIONS})"
        )

    device_id = _require_non_empty_string(record, "deviceId", where)
    if device_id not in DEVICE_IDS:
        raise RecordFormatError(
            f"{where}: unknown deviceId {device_id!r} (expected {DEVICE_IDS})"
        )

    source = _require_non_empty_string(record, "source", where)
    if source.startswith("/") or (len(source) > 1 and source[1] == ":"):
        raise RecordFormatError(
            f"{where}: source must be a repository-relative path, got "
            f"absolute path {source!r}"
        )

    _require_non_empty_string(record, "buildSha", where)
    _require_non_empty_string(record, "metric", where)
    _require_non_empty_string(record, "unit", where)
    _require_non_empty_string(record, "timestamp", where)
    _require_number(record, "value", where)
    _require_int(record, "sampleCount", where)

    return record


def load_records(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    if not isinstance(document, dict):
        raise RecordFormatError(f"{path}: top-level document must be a JSON object")
    records = document.get("records")
    if not isinstance(records, list):
        raise RecordFormatError(f"{path}: document is missing the \"records\" array")
    return [
        validate_record(record, f"{path}[{index}]")
        for index, record in enumerate(records)
    ]


def classify(baseline_value: float, candidate_value: float, direction: str) -> tuple:
    """Returns (status, delta) where delta is the fraction of regression —
    positive means worse, per the metric's own direction (ADR 0474 D7).
    An improvement (delta <= 0) is always "pass", regardless of magnitude.
    """
    if direction == "lowerIsBetter":
        delta = (candidate_value - baseline_value) / baseline_value
    else:
        delta = (baseline_value - candidate_value) / baseline_value

    if delta >= FAIL_THRESHOLD:
        return "fail", delta
    if delta >= WARN_THRESHOLD:
        return "warn", delta
    return "pass", delta


def compare(baseline: list[dict], candidate: list[dict]) -> tuple:
    """Compares every `measured` baseline metric against the candidate.

    Returns (lines, exit_code). `unknown` (missing from the candidate) and
    `fail` both force a non-zero exit; `warn` and `pass` do not (ADR 0474
    D6: warn is a visible, non-blocking signal — fail is the gate).
    """
    candidate_measured = {
        record["metric"]: record
        for record in candidate
        if record["kind"] == "measured"
    }

    lines: list[str] = []
    blocking = False

    for record in baseline:
        if record["kind"] != "measured":
            continue
        metric = record["metric"]
        match = candidate_measured.get(metric)
        if match is None:
            lines.append(f"{metric}: status=unknown (missing from candidate)")
            blocking = True
            continue
        status, delta = classify(record["value"], match["value"], record["direction"])
        lines.append(
            f"{metric}: status={status} delta={delta:.6f} "
            f"baseline={record['value']!r} candidate={match['value']!r} "
            f"direction={record['direction']}"
        )
        if status == "fail":
            blocking = True

    return lines, (1 if blocking else 0)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    args = parser.parse_args(argv)

    try:
        baseline = load_records(args.baseline)
        candidate = load_records(args.candidate)
    except (RecordFormatError, OSError, json.JSONDecodeError) as error:
        print(f"compare_benchmarks: {error}", file=sys.stderr)
        return 2

    lines, exit_code = compare(baseline, candidate)
    for line in lines:
        print(line)

    measured_count = len(lines)
    warn_count = sum(1 for line in lines if "status=warn" in line)
    fail_count = sum(1 for line in lines if "status=fail" in line)
    unknown_count = sum(1 for line in lines if "status=unknown" in line)
    print(
        f"compare_benchmarks: {measured_count} measured metric(s) compared, "
        f"{warn_count} warn, {fail_count} fail, {unknown_count} unknown"
    )

    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
