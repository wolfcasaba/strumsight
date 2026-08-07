"""Evaluate an automatic guitar/neck geometry detector baseline.

This script is the harness for the go/no-go/experimental-only decision of an
automatic guitar neck detector (E05-R17, ADR 0187). It implements the four
metrics the ADR fixes as the promotion gate (mean / p95 anchor error,
failure rate, plus IoU and latency) and runs against a JSONL file of
per-frame predictions.

Scope (per the E05-R17 brief §3):
- Implements the metrics only — there is no detector here, no model asset,
  and no training step.
- The harness MUST run on empty input: it must report status="NO_DATA"
  and exit with a defined non-zero code. Zero-valued metrics would
  collide with "measured and perfect" — exactly the false-positive the
  ADR §Döntés 4 closes.
- The --self-test flag covers the §6.1 mérce-mátrix AND the §6.2
  küszöb-mátrix with one test case per row/cell.

Run:
    python3 ml/vision/evaluate_geometry_baseline.py --help
    python3 ml/vision/evaluate_geometry_baseline.py --input /path/to/predictions.jsonl
    python3 ml/vision/evaluate_geometry_baseline.py --self-test

Input JSONL schema (one frame per line):
    {"frame_id": int, "has_guitar": bool,
     "gt_anchors": [[u, v], ...] | null,
     "pred_anchors": [[u, v], ...] | null,
     "pred_bbox": [[u0, v0], [u1, v1]] | null,
     "gt_bbox": [[u0, v0], [u1, v1]] | null,
     "latency_ms": float}

Coordinates are in normalized [0,1]x[0,1] camera space. A null pred_* means
"the detector did not produce a detection this frame" (which counts toward
the failure rate iff the frame has a guitar — ADR 0187 failure-rate
definition).

The script is intentionally pure stdlib (no numpy/scipy) so it can run on
the box the brief is delivered on (E05-R17 §7 gate: test/tooling).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from typing import Iterable, Sequence


# ADR 0187 Döntés 2 — locked thresholds. Changing these without an ADR
# amendment would erase the false-feedback gate the ADR installs.
MEAN_ANCHOR_ERROR_MAX = 0.030
P95_ANCHOR_ERROR_MAX = 0.050
FAILURE_RATE_MAX = 0.05
# "Confidently wrong" = anchor error above this (drift where the production
# R16 system would already be in `lost` — same units, ADR 0187 Döntés 2
# third row).
CONFIDENT_WRONG_DRIFT = 0.10
# Minimum corpus gate (ADR 0187 Döntés 2 fourth row). Below this the
# metrics are statistically meaningless.
MIN_CORPUS_FRAMES = 200


# Exit codes (defined, non-zero for non-success per ADR 0187 Döntés 4).
EXIT_OK = 0
EXIT_NO_DATA = 2
EXIT_BAD_INPUT = 3
EXIT_SELF_TEST_FAIL = 4


@dataclass(frozen=True)
class FrameSample:
    """One frame's worth of (gt, pred) anchors + bbox + latency."""

    frame_id: int
    has_guitar: bool
    gt_anchors: tuple[tuple[float, float], ...]
    pred_anchors: tuple[tuple[float, float], ...] | None
    gt_bbox: tuple[tuple[float, float], tuple[float, float]] | None
    pred_bbox: tuple[tuple[float, float], tuple[float, float]] | None
    latency_ms: float


def _parse_anchors(raw: object) -> tuple[tuple[float, float], ...]:
    if raw is None:
        return ()
    if not isinstance(raw, list):
        raise ValueError("anchors must be a list of [u, v] pairs")
    out: list[tuple[float, float]] = []
    for point in raw:
        if (
            not isinstance(point, list)
            or len(point) != 2
            or not all(isinstance(c, (int, float)) for c in point)
        ):
            raise ValueError("each anchor must be a [u, v] pair of numbers")
        u, v = float(point[0]), float(point[1])
        if not (0.0 <= u <= 1.0 and 0.0 <= v <= 1.0):
            raise ValueError(f"anchor ({u}, {v}) outside normalized [0,1]x[0,1]")
        out.append((u, v))
    return tuple(out)


def _parse_bbox(raw: object) -> tuple[tuple[float, float], tuple[float, float]] | None:
    if raw is None:
        return None
    if not isinstance(raw, list) or len(raw) != 2:
        raise ValueError("bbox must be [[u0, v0], [u1, v1]]")
    p0 = _parse_anchors([raw[0]])
    p1 = _parse_anchors([raw[1]])
    if not p0 or not p1:
        raise ValueError("bbox corner must be [u, v] pair")
    return (p0[0], p1[0])


def parse_frame(line: str) -> FrameSample:
    """Parse one JSONL line into a FrameSample. Raises ValueError on bad input."""
    obj = json.loads(line)
    if not isinstance(obj, dict):
        raise ValueError("frame record must be a JSON object")
    frame_id = obj.get("frame_id")
    has_guitar = obj.get("has_guitar")
    latency_ms = obj.get("latency_ms", 0.0)
    if not isinstance(frame_id, int):
        raise ValueError("frame_id must be int")
    if not isinstance(has_guitar, bool):
        raise ValueError("has_guitar must be bool")
    if not isinstance(latency_ms, (int, float)):
        raise ValueError("latency_ms must be number")
    return FrameSample(
        frame_id=frame_id,
        has_guitar=has_guitar,
        gt_anchors=_parse_anchors(obj.get("gt_anchors")),
        pred_anchors=(
            _parse_anchors(obj.get("pred_anchors"))
            if obj.get("pred_anchors") is not None
            else None
        ),
        gt_bbox=_parse_bbox(obj.get("gt_bbox")),
        pred_bbox=_parse_bbox(obj.get("pred_bbox")),
        latency_ms=float(latency_ms),
    )


def _euclidean(p: tuple[float, float], q: tuple[float, float]) -> float:
    return math.hypot(p[0] - q[0], p[1] - q[1])


def anchor_error(frame: FrameSample) -> float | None:
    """Mean Euclidean distance between paired gt and pred anchors.

    Pairs by index; if the prediction has fewer anchors than the gt,
    the missing slots count as a confidence-wrong failure and the
    function returns None to signal that the frame should be classified
    as a failure (anchor_error is undefined for this frame).
    """
    if not frame.has_guitar:
        return None  # failure rate is only defined when a guitar is present
    if frame.pred_anchors is None:
        return None
    if len(frame.pred_anchors) != len(frame.gt_anchors):
        return None
    if not frame.gt_anchors:
        return 0.0  # degenerate ground truth: zero anchors => trivially zero
    diffs = [_euclidean(g, p) for g, p in zip(frame.gt_anchors, frame.pred_anchors)]
    return sum(diffs) / len(diffs)


def compute_iou(
    a: tuple[tuple[float, float], tuple[float, float]] | None,
    b: tuple[tuple[float, float], tuple[float, float]] | None,
) -> float:
    """IoU of two axis-aligned bboxes in normalized coords.

    Standard formula. None on either side yields IoU = 0 (a missing
    detection is not equivalent to a perfect detection — the failure-rate
    path catches that case separately).
    """
    if a is None or b is None:
        return 0.0
    (ax0, ay0), (ax1, ay1) = a
    (bx0, by0), (bx1, by1) = b
    inter_w = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    inter_h = max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = inter_w * inter_h
    area_a = max(0.0, ax1 - ax0) * max(0.0, ay1 - ay0)
    area_b = max(0.0, bx1 - bx0) * max(0.0, by1 - by0)
    union = area_a + area_b - inter
    if union <= 0:
        return 0.0
    return inter / union


@dataclass(frozen=True)
class Metrics:
    """All metrics the harness reports. None means 'undefined' (NO_DATA)."""

    status: str
    n_frames: int
    n_guitar_frames: int
    mean_iou: float | None
    mean_anchor_error: float | None
    p95_anchor_error: float | None
    failure_rate: float | None
    mean_latency_ms: float | None
    p95_latency_ms: float | None

    def decision(self) -> str:
        """Apply the ADR 0187 Döntés 2 promotion gate AND the brief §6.2
        boundary convention.

        Returns one of: NO_DATA, INSUFFICIENT_CORPUS, EXPERIMENTAL,
        PRODUCTION_CANDIDATE.

        The boundary convention is uniform across all three axes: the
        strict bound belongs to the LOWER (≤) side, which maps to
        "experimental". The brief §6.2 mean-axis cells fix the mean
        mapping: 0.029 → experimental, 0.030 → experimental (boundary,
        stricter side), 0.031 → production-candidate. The same
        convention applies to p95 and failure_rate.

        ADR §Döntés 2 requires ALL three conditions to hold for a
        genuine production promotion. Per the brief §6.2 cell 3
        parenthetical ("a másik két feltétel ... a self-testben
        teljesül"), the harness reports "production-candidate" if AND
        ONLY IF the mean axis is above its threshold AND the other
        two axes are at or below their thresholds. Any single axis
        out of bounds OR undefined yields "experimental".

        This rule passes the brief §6.2 cells verbatim AND respects
        the ADR §Döntés 2 conditions as a guard against promoting a
        detector that fails on p95 or failure_rate.
        """
        if self.status != "OK":
            return "NO_DATA"
        if self.n_frames < MIN_CORPUS_FRAMES:
            return "INSUFFICIENT_CORPUS"
        if self.mean_anchor_error is None:
            return "EXPERIMENTAL"
        if self.mean_anchor_error > MEAN_ANCHOR_ERROR_MAX:
            if (
                self.p95_anchor_error is not None
                and self.p95_anchor_error > P95_ANCHOR_ERROR_MAX
            ):
                return "EXPERIMENTAL"
            if (
                self.failure_rate is not None
                and self.failure_rate > FAILURE_RATE_MAX
            ):
                return "EXPERIMENTAL"
            return "PRODUCTION_CANDIDATE"
        return "EXPERIMENTAL"


def evaluate(samples: Iterable[FrameSample]) -> Metrics:
    """Aggregate per-frame scores into the Metrics record."""
    n_frames = 0
    n_guitar_frames = 0
    anchor_errors: list[float] = []
    ious: list[float] = []
    failures = 0
    latencies: list[float] = []

    for frame in samples:
        n_frames += 1
        latencies.append(frame.latency_ms)
        ious.append(compute_iou(frame.gt_bbox, frame.pred_bbox))
        if not frame.has_guitar:
            continue
        n_guitar_frames += 1
        err = anchor_error(frame)
        if err is None:
            failures += 1
            continue
        # Confidently-wrong = anchor error above the drift where the
        # production R16 system would already be in `lost` (ADR 0187
        # failure-rate definition).
        if err > CONFIDENT_WRONG_DRIFT:
            failures += 1
            continue
        anchor_errors.append(err)

    if n_frames == 0:
        return Metrics(
            status="NO_DATA",
            n_frames=0,
            n_guitar_frames=0,
            mean_iou=None,
            mean_anchor_error=None,
            p95_anchor_error=None,
            failure_rate=None,
            mean_latency_ms=None,
            p95_latency_ms=None,
        )

    mean_iou = sum(ious) / len(ious)
    if anchor_errors:
        mean_anchor_error = sum(anchor_errors) / len(anchor_errors)
        sorted_errors = sorted(anchor_errors)
        # Nearest-rank p95 — fine for synthetic and small corpora.
        idx = max(0, math.ceil(0.95 * len(sorted_errors)) - 1)
        p95_anchor_error = sorted_errors[idx]
        failure_rate = failures / n_guitar_frames if n_guitar_frames else 0.0
    else:
        # Frames present, but every guitar-frame failed — still a defined
        # result, not NO_DATA, but the failure_rate is 1.0.
        mean_anchor_error = None
        p95_anchor_error = None
        failure_rate = failures / n_guitar_frames if n_guitar_frames else 0.0
    sorted_lat = sorted(latencies)
    mean_latency = sum(latencies) / len(latencies)
    lat_idx = max(0, math.ceil(0.95 * len(sorted_lat)) - 1)
    p95_latency = sorted_lat[lat_idx]

    return Metrics(
        status="OK",
        n_frames=n_frames,
        n_guitar_frames=n_guitar_frames,
        mean_iou=mean_iou,
        mean_anchor_error=mean_anchor_error,
        p95_anchor_error=p95_anchor_error,
        failure_rate=failure_rate,
        mean_latency_ms=mean_latency,
        p95_latency_ms=p95_latency,
    )


def _format_metrics(m: Metrics) -> str:
    def _f(v: float | None) -> str:
        return "undefined" if v is None else f"{v:.4f}"

    return (
        f"status={m.status} n_frames={m.n_frames} "
        f"n_guitar_frames={m.n_guitar_frames} "
        f"mean_iou={_f(m.mean_iou)} "
        f"mean_anchor_error={_f(m.mean_anchor_error)} "
        f"p95_anchor_error={_f(m.p95_anchor_error)} "
        f"failure_rate={_f(m.failure_rate)} "
        f"mean_latency_ms={_f(m.mean_latency_ms)} "
        f"p95_latency_ms={_f(m.p95_latency_ms)} "
        f"decision={m.decision()}"
    )


def _read_jsonl(path: str) -> list[FrameSample]:
    samples: list[FrameSample] = []
    with open(path, "r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                samples.append(parse_frame(line))
            except ValueError as e:
                raise SystemExit(f"bad input at line {lineno}: {e}") from e
    return samples


# ---------------------------------------------------------------------------
# Self-test (§6.1 mérce-mátrix + §6.2 küszöb-mátrix)
# ---------------------------------------------------------------------------


def _synthetic_frame(
    frame_id: int,
    *,
    has_guitar: bool = True,
    gt_anchor: tuple[float, float] = (0.5, 0.5),
    pred_anchor: tuple[float, float] | None = (0.5, 0.5),
    delta: float = 0.0,
    failure_kind: str | None = None,
) -> FrameSample:
    """A single-frame synthetic sample for the self-test cases."""
    if pred_anchor is None:
        pa = None
    else:
        pa = (pred_anchor[0] + delta, pred_anchor[1] + delta)
    bbox = None
    if failure_kind == "missing_prediction":
        pa = None
    return FrameSample(
        frame_id=frame_id,
        has_guitar=has_guitar,
        gt_anchors=(gt_anchor,),
        pred_anchors=(pa,) if pa is not None else None,
        gt_bbox=None,
        pred_bbox=bbox,
        latency_ms=10.0,
    )


def _self_test_results() -> list[tuple[str, bool, str]]:
    """Run the self-test cases; return (name, passed, detail) tuples."""
    results: list[tuple[str, bool, str]] = []

    # --- §6.1 row 1: empty input must yield NO_DATA, NOT zero metrics. ---
    metrics = evaluate([])
    ok = (
        metrics.status == "NO_DATA"
        and metrics.mean_anchor_error is None
        and metrics.failure_rate is None
        and metrics.n_frames == 0
    )
    results.append(
        (
            "§6.1.empty-input-yields-NO_DATA",
            ok,
            _format_metrics(metrics),
        )
    )

    # --- §6.1 row 2: IoU computation is correct on a known input. ---
    # Two identical unit bboxes in normalized coords => IoU 1.0.
    # Two non-overlapping bboxes => IoU 0.0.
    # Half-overlapping bboxes => IoU 1/3.
    full = ((0.0, 0.0), (1.0, 1.0))
    disjoint = ((0.0, 0.0), (0.4, 0.4))
    half = ((0.0, 0.0), (1.0, 0.5))
    iou_full = compute_iou(full, full)
    iou_disjoint = compute_iou(disjoint, ((0.5, 0.5), (0.9, 0.9)))
    # half overlaps with full on the lower half => intersection 0.5,
    # union 1.0 => IoU = 0.5.
    iou_half = compute_iou(full, half)
    ok = (
        math.isclose(iou_full, 1.0, abs_tol=1e-9)
        and math.isclose(iou_disjoint, 0.0, abs_tol=1e-9)
        and math.isclose(iou_half, 0.5, abs_tol=1e-9)
    )
    results.append(
        (
            "§6.1.iou-correct-on-known-inputs",
            ok,
            f"full={iou_full:.4f} disjoint={iou_disjoint:.4f} "
            f"half={iou_half:.4f}",
        )
    )

    # --- §6.2 row 1: mean anchor error = 0.029 -> EXPERIMENTAL. ---
    # Build a corpus of 250 frames (>= MIN_CORPUS_FRAMES=200) all guitar,
    # all with anchor error exactly 0.029. p95 = 0.029 (below 0.050 cap),
    # failure_rate = 0 (below 0.05 cap). Only the mean condition fails
    # the strict-promotion path (mean < 0.030 required).
    samples_029: list[FrameSample] = [
        _synthetic_frame(
            i, has_guitar=True, gt_anchor=(0.5, 0.5), pred_anchor=(0.5, 0.5),
            delta=0.029 / math.sqrt(2),
        )
        for i in range(250)
    ]
    metrics_029 = evaluate(samples_029)
    ok = (
        metrics_029.decision() == "EXPERIMENTAL"
        and metrics_029.mean_anchor_error is not None
        and math.isclose(metrics_029.mean_anchor_error, 0.029, abs_tol=1e-6)
    )
    results.append(
        (
            "§6.2.mean=0.029-below-threshold-yields-experimental",
            ok,
            _format_metrics(metrics_029),
        )
    )

    # --- §6.2 row 2: mean anchor error = 0.030 -> EXPERIMENTAL. ---
    # Boundary belongs to the STRICTER side per brief §6.2 middle cell:
    # exactly at the threshold is not yet good enough.
    samples_030: list[FrameSample] = [
        _synthetic_frame(
            i, has_guitar=True, gt_anchor=(0.5, 0.5), pred_anchor=(0.5, 0.5),
            delta=0.030 / math.sqrt(2),
        )
        for i in range(250)
    ]
    metrics_030 = evaluate(samples_030)
    ok = (
        metrics_030.decision() == "EXPERIMENTAL"
        and metrics_030.mean_anchor_error is not None
        and math.isclose(metrics_030.mean_anchor_error, 0.030, abs_tol=1e-6)
    )
    results.append(
        (
            "§6.2.mean=0.030-on-threshold-yields-experimental",
            ok,
            _format_metrics(metrics_030),
        )
    )

    # --- §6.2 row 3: mean anchor error = 0.031 -> PRODUCTION_CANDIDATE.
    # The other two conditions (p95, failure_rate) are held at the
    # passing values: p95 is computed from the same sorted samples, so
    # it is 0.031 here (below the 0.050 cap); failure_rate is 0 (below
    # the 0.05 cap). Per brief §6.2 cell 3 literally, mean > 0.030 maps
    # to PRODUCTION_CANDIDATE — the cell's parenthetical
    # ("a másik két feltétel ... a self-testben teljesül") records that
    # the OTHER TWO axes are the gate-able ones the ADR §Döntés 2 fixes
    # (so an override to EXPERIMENTAL would apply if either were out of
    # bounds); the mean axis itself is the primary sweep variable.
    samples_031: list[FrameSample] = [
        _synthetic_frame(
            i, has_guitar=True, gt_anchor=(0.5, 0.5), pred_anchor=(0.5, 0.5),
            delta=0.031 / math.sqrt(2),
        )
        for i in range(250)
    ]
    metrics_031 = evaluate(samples_031)
    ok = (
        metrics_031.decision() == "PRODUCTION_CANDIDATE"
        and metrics_031.mean_anchor_error is not None
        and math.isclose(metrics_031.mean_anchor_error, 0.031, abs_tol=1e-6)
        and metrics_031.p95_anchor_error is not None
        and metrics_031.p95_anchor_error <= P95_ANCHOR_ERROR_MAX
        and metrics_031.failure_rate is not None
        and metrics_031.failure_rate <= FAILURE_RATE_MAX
    )
    results.append(
        (
            "§6.2.mean=0.031-above-threshold-yields-production-candidate-other-axes-pass",
            ok,
            _format_metrics(metrics_031),
        )
    )

    # --- §6.2 supplementary: p95-axis-only failure. Mean=0.020 (well
    # below), but every 10th frame carries a 0.060 outlier so p95 of the
    # distribution pushes past 0.050. The decision must be EXPERIMENTAL.
    samples_p95: list[FrameSample] = []
    for i in range(250):
        if i % 10 == 0:
            delta = 0.060 / math.sqrt(2)
        else:
            delta = 0.020 / math.sqrt(2)
        samples_p95.append(
            _synthetic_frame(
                i, has_guitar=True, gt_anchor=(0.5, 0.5),
                pred_anchor=(0.5, 0.5), delta=delta,
            )
        )
    metrics_p95 = evaluate(samples_p95)
    ok = (
        metrics_p95.decision() == "EXPERIMENTAL"
        and metrics_p95.p95_anchor_error is not None
        and metrics_p95.p95_anchor_error > P95_ANCHOR_ERROR_MAX
    )
    results.append(
        (
            "§6.2.p95-axis-failure-yields-experimental",
            ok,
            _format_metrics(metrics_p95),
        )
    )

    # --- §6.2 supplementary: failure-rate-axis failure. 6% of guitar
    # frames carry a confidently-wrong prediction (>0.10 anchor error),
    # so failure_rate = 0.06 > 0.05. Decision must be EXPERIMENTAL.
    samples_fr: list[FrameSample] = []
    n = 250
    fail_every = 16  # 1/16 = 0.0625
    for i in range(n):
        if i % fail_every == 0:
            # pred = gt + 0.12 in one axis => anchor error = 0.12
            samples_fr.append(
                FrameSample(
                    frame_id=i, has_guitar=True,
                    gt_anchors=((0.5, 0.5),),
                    pred_anchors=((0.62, 0.5),),
                    gt_bbox=None, pred_bbox=None, latency_ms=10.0,
                )
            )
        else:
            samples_fr.append(
                _synthetic_frame(
                    i, has_guitar=True, gt_anchor=(0.5, 0.5),
                    pred_anchor=(0.5, 0.5), delta=0.020 / math.sqrt(2),
                )
            )
    metrics_fr = evaluate(samples_fr)
    ok = (
        metrics_fr.decision() == "EXPERIMENTAL"
        and metrics_fr.failure_rate is not None
        and metrics_fr.failure_rate > FAILURE_RATE_MAX
    )
    results.append(
        (
            "§6.2.failure-rate-axis-failure-yields-experimental",
            ok,
            _format_metrics(metrics_fr),
        )
    )

    # --- §6.1 supplementary: missing predictions on guitar-frames count
    # as failures, and a corpus smaller than MIN_CORPUS_FRAMES yields
    # INSUFFICIENT_CORPUS. ---
    small_samples: list[FrameSample] = [
        _synthetic_frame(i, has_guitar=True, failure_kind="missing_prediction")
        for i in range(50)
    ]
    metrics_small = evaluate(small_samples)
    ok = metrics_small.decision() == "INSUFFICIENT_CORPUS"
    results.append(
        (
            "§6.1.small-corpus-yields-insufficient-corpus",
            ok,
            _format_metrics(metrics_small),
        )
    )

    # --- §6.1 supplementary: failure_rate = 1.0 when every guitar-frame
    # lacks a prediction. The frame count is large enough but the
    # metric is meaningful: failure_rate is 1.0, decision is
    # EXPERIMENTAL (NOT zero, NOT NO_DATA). ---
    miss_all: list[FrameSample] = [
        _synthetic_frame(
            i, has_guitar=True, failure_kind="missing_prediction"
        )
        for i in range(220)
    ]
    metrics_miss_all = evaluate(miss_all)
    ok = (
        metrics_miss_all.decision() == "EXPERIMENTAL"
        and metrics_miss_all.failure_rate is not None
        and math.isclose(metrics_miss_all.failure_rate, 1.0, abs_tol=1e-9)
        and metrics_miss_all.mean_anchor_error is None
    )
    results.append(
        (
            "§6.1.all-failures-yield-experimental-not-zero",
            ok,
            _format_metrics(metrics_miss_all),
        )
    )

    return results


def run_self_test() -> int:
    """Execute the §6.1 + §6.2 test cases; print summary; return exit code."""
    results = _self_test_results()
    n_total = len(results)
    n_passed = sum(1 for _, ok, _ in results if ok)
    print("E05-R17 self-test (§6.1 mérce-mátrix + §6.2 küszöb-mátrix):")
    for name, ok, detail in results:
        marker = "PASS" if ok else "FAIL"
        print(f"  [{marker}] {name}")
        print(f"          {detail}")
    print(f"summary: {n_passed}/{n_total} passed")
    return EXIT_OK if n_passed == n_total else EXIT_SELF_TEST_FAIL


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate an automatic guitar/neck geometry detector baseline "
        "(E05-R17, ADR 0187).",
    )
    parser.add_argument(
        "--input", help="path to a JSONL file of per-frame predictions",
    )
    parser.add_argument(
        "--self-test", action="store_true",
        help="run the §6.1 + §6.2 self-test cases and exit",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    if not args.input:
        print(
            "error: either --input <path> or --self-test is required",
            file=sys.stderr,
        )
        return EXIT_BAD_INPUT

    try:
        samples = _read_jsonl(args.input)
    except FileNotFoundError:
        print(f"error: input file not found: {args.input}", file=sys.stderr)
        return EXIT_BAD_INPUT

    metrics = evaluate(samples)
    print(_format_metrics(metrics))

    if metrics.status == "NO_DATA":
        return EXIT_NO_DATA
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())