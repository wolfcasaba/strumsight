"""Evaluate privacy-safe Vision metric fixtures.

The harness consumes JSONL fixture summaries only; it never reads camera
frames. Each record has a metric result and may contain an evaluated negative
cue. It reports per-metric agreement plus the false-negative-cue rate that
gates a production-supported classification.

Run:
  python3 ml/vision/evaluate_vision_metrics.py --self-test
  python3 ml/vision/evaluate_vision_metrics.py --input /path/to/fixtures.jsonl

JSONL schema:
  {"fixture_id": "hand-001", "metric": "hand_tracking",
   "expected": true, "observed": true,
   "negative_cue_expected": false, "negative_cue_emitted": false}

`expected` and `observed` are boolean fixture outcomes for hand tracking,
quality, geometry, or a metric policy. A false negative cue is an emitted
negative cue where ground truth says no negative cue was warranted.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


# The benchmark target is zero false feedback. A 1% inclusive release cap is
# the strictest non-zero boundary that permits the required 0%/1%/2% matrix:
# at most one false cue in 100 independently reviewed fixtures. Above it, the
# metric remains experimental rather than moving the threshold after measuring.
FALSE_NEGATIVE_CUE_RATE_MAX = 0.01
FALSE_NEGATIVE_CUE_RATE_STEP = 0.01

EXIT_OK = 0
EXIT_NO_DATA = 2
EXIT_BAD_INPUT = 3
EXIT_SELF_TEST_FAIL = 4

_VALID_METRICS = frozenset(
    {"hand_tracking", "quality", "geometry", "metric_policy"}
)


@dataclass(frozen=True)
class Fixture:
    fixture_id: str
    metric: str
    expected: bool
    observed: bool
    negative_cue_expected: bool | None
    negative_cue_emitted: bool | None


@dataclass(frozen=True)
class MetricSummary:
    samples: int
    matching_outcomes: int
    agreement_rate: float


@dataclass(frozen=True)
class FalseFeedbackSummary:
    status: str
    cue_opportunities: int
    false_negative_cues: int
    false_negative_cue_rate: float | None
    classification: str


@dataclass(frozen=True)
class Evaluation:
    status: str
    sample_count: int
    metrics: dict[str, MetricSummary]
    false_feedback: FalseFeedbackSummary


def parse_fixture(line: str) -> Fixture:
    """Parse one JSONL fixture record and fail closed on an invalid shape."""
    try:
        raw = json.loads(line)
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON: {error.msg}") from error
    if not isinstance(raw, dict):
        raise ValueError("fixture must be a JSON object")

    fixture_id = raw.get("fixture_id")
    metric = raw.get("metric")
    expected = raw.get("expected")
    observed = raw.get("observed")
    if not isinstance(fixture_id, str) or not fixture_id.strip():
        raise ValueError("fixture_id must be a non-empty string")
    if metric not in _VALID_METRICS:
        raise ValueError(f"metric must be one of {sorted(_VALID_METRICS)}")
    if not isinstance(expected, bool) or not isinstance(observed, bool):
        raise ValueError("expected and observed must be booleans")

    cue_expected = raw.get("negative_cue_expected")
    cue_emitted = raw.get("negative_cue_emitted")
    if (cue_expected is None) != (cue_emitted is None):
        raise ValueError(
            "negative_cue_expected and negative_cue_emitted must appear together"
        )
    if cue_expected is not None and (
        not isinstance(cue_expected, bool) or not isinstance(cue_emitted, bool)
    ):
        raise ValueError("negative cue fields must be booleans")

    return Fixture(
        fixture_id=fixture_id,
        metric=metric,
        expected=expected,
        observed=observed,
        negative_cue_expected=cue_expected,
        negative_cue_emitted=cue_emitted,
    )


def evaluate(fixtures: Iterable[Fixture]) -> Evaluation:
    """Aggregate fixture outcomes without treating absent evidence as success."""
    records = list(fixtures)
    if not records:
        return Evaluation(
            status="NO_DATA",
            sample_count=0,
            metrics={},
            false_feedback=FalseFeedbackSummary(
                status="NO_DATA",
                cue_opportunities=0,
                false_negative_cues=0,
                false_negative_cue_rate=None,
                classification="experimental",
            ),
        )

    grouped: dict[str, list[Fixture]] = {}
    for record in records:
        grouped.setdefault(record.metric, []).append(record)
    metrics = {
        metric: MetricSummary(
            samples=len(group),
            matching_outcomes=sum(
                record.expected == record.observed for record in group
            ),
            agreement_rate=sum(
                record.expected == record.observed for record in group
            )
            / len(group),
        )
        for metric, group in sorted(grouped.items())
    }

    cue_records = [
        record for record in records if record.negative_cue_expected is not None
    ]
    false_cues = sum(
        record.negative_cue_emitted and not record.negative_cue_expected
        for record in cue_records
    )
    if not cue_records:
        false_feedback = FalseFeedbackSummary(
            status="NO_DATA",
            cue_opportunities=0,
            false_negative_cues=0,
            false_negative_cue_rate=None,
            classification="experimental",
        )
    else:
        rate = false_cues / len(cue_records)
        false_feedback = FalseFeedbackSummary(
            status="OK",
            cue_opportunities=len(cue_records),
            false_negative_cues=false_cues,
            false_negative_cue_rate=rate,
            classification=(
                "production-supported"
                if rate <= FALSE_NEGATIVE_CUE_RATE_MAX
                else "experimental"
            ),
        )
    return Evaluation(
        status="OK",
        sample_count=len(records),
        metrics=metrics,
        false_feedback=false_feedback,
    )


def _as_json(evaluation: Evaluation) -> str:
    return json.dumps(
        {
            "status": evaluation.status,
            "sample_count": evaluation.sample_count,
            "metrics": {
                name: asdict(summary)
                for name, summary in evaluation.metrics.items()
            },
            "false_feedback": asdict(evaluation.false_feedback),
        },
        sort_keys=True,
    )


def _read_jsonl(path: Path) -> list[Fixture]:
    records: list[Fixture] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            records.append(parse_fixture(line))
        except ValueError as error:
            raise ValueError(f"line {line_number}: {error}") from error
    return records


def _fixtures(false_cues: int, total: int = 100) -> list[Fixture]:
    return [
        Fixture(
            fixture_id=f"fixture-{index}",
            metric=("hand_tracking" if index % 3 == 0 else "quality"),
            expected=True,
            observed=True,
            negative_cue_expected=False,
            negative_cue_emitted=index < false_cues,
        )
        for index in range(total)
    ]


def self_test() -> bool:
    """Exercise no-data and the below/equal/above false-feedback matrix."""
    no_data = evaluate([])
    cases = (
        ("no-data", no_data.status == "NO_DATA", no_data),
        (
            "below-threshold",
            evaluate(_fixtures(0)).false_feedback.classification
            == "production-supported",
            evaluate(_fixtures(0)),
        ),
        (
            "inclusive-threshold",
            evaluate(_fixtures(1)).false_feedback.classification
            == "production-supported",
            evaluate(_fixtures(1)),
        ),
        (
            "above-threshold",
            evaluate(_fixtures(2)).false_feedback.classification == "experimental",
            evaluate(_fixtures(2)),
        ),
    )
    for name, passed, result in cases:
        print(f"self_test={name} passed={passed} {_as_json(result)}")
    return all(passed for _, passed, _ in cases)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="JSONL fixture-summary path")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return EXIT_OK if self_test() else EXIT_SELF_TEST_FAIL
    if args.input is None:
        parser.error("one of --input or --self-test is required")
    try:
        result = evaluate(_read_jsonl(args.input))
    except (OSError, ValueError) as error:
        print(f"bad input: {error}", file=sys.stderr)
        return EXIT_BAD_INPUT
    print(_as_json(result))
    return EXIT_NO_DATA if result.status == "NO_DATA" else EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
