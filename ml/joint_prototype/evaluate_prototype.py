"""E14-R18 joint streaming onset+direction prototype — evaluation (ADR 0517).

Loads the weights `train_prototype.py` wrote to --workdir, scans every TEST
recording's full audio at every 10 ms hop (a genuine streaming-style scan —
never cheating by only looking at already-known onset times), peak-picks
onset+direction events from the per-frame softmax, and compares the result
against the legacy two-stage pipeline's ANCHORED baseline manifest row
(ADR 0517 D6). Prints (and optionally writes) a JSON document conforming to
`evaluation/recognition/joint_io_schema.json`.

Two fail-closed gates run BEFORE anything is computed or printed
(ADR 0517 D2/D6 — a violation aborts with no document at all, never a
document with a wrong or missing number):
  1. corpus identity: this run's own ml/data/klangio corpus hash must match
     evaluation/recognition/baseline_manifest.json's corpusSha256 exactly;
  2. split identity: the train/test guitarist-id partition recomputed HERE
     (independently of whatever train_prototype.py's provenance claims) must
     be disjoint.

Usage (ONLY the TensorFlow-equipped interpreter can run this):

  /home/ubuntu/tf-venv/bin/python ml/joint_prototype/evaluate_prototype.py \\
      --workdir /tmp/e14r18-work

Optional flags: --data-dir, --baseline-manifest, --output (JSON destination,
default <workdir>/joint_io_document.json — repo-external per ADR 0517 D5).
"""
from __future__ import annotations

import argparse
import hashlib
import glob
import json
import os
import sys
import time
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
ML_ROOT = REPO_ROOT / "ml"
sys.path.insert(0, str(ML_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import features as F  # noqa: E402
from klangio import guitarist_of, parse_strums, recording_ids  # noqa: E402
from prepare_dataset import _read_wav  # noqa: E402
from train_prototype import (  # noqa: E402
    FRAMES,
    HOP_MS,
    LOOKAHEAD_FRAMES,
    LOOKAHEAD_MS,
    PRE_FRAMES,
    build_model,
    joint_window,
)

SCHEMA_VERSION = "1.0"
DEFAULT_BASELINE_MANIFEST = REPO_ROOT / "evaluation" / "recognition" / "baseline_manifest.json"
CORPUS_ID = "ml/data/klangio"

ONSET_TOLERANCE_S = 0.050
PEAK_MIN_GAP_S = 0.06
PEAK_THRESHOLD = 0.5

ONSET_ALPHA_THRESHOLD = 0.82
DIRECTION_ALPHA_THRESHOLD = 0.8


class CorpusHashMismatchError(ValueError):
    """The measured corpus hash does not match the anchored baseline
    manifest (ADR 0517 D6) — the run aborts with NO document written."""


class GuitaristLeakageError(ValueError):
    """The recomputed train/test guitarist-id split overlaps (ADR 0517 D2,
    fail-closed) — the run aborts with NO document written."""


def corpus_sha256(data_dir: str) -> str:
    """Identical algorithm to `tool/benchmarks/real_audio_dsp_baseline.dart
    ::_corpusChecksum` — sorted *.wav then sorted *.strums, each preceded by
    its own "<basename>\\n" — so this independently reproduces the SAME
    hash the merged baseline manifest was anchored with (measured 2026-09-05:
    reproduces 4880face...5827 exactly on the real corpus)."""
    strum_files = sorted(glob.glob(os.path.join(data_dir, "*.strums")))
    wav_files = sorted(glob.glob(os.path.join(data_dir, "*.wav")))
    digest = hashlib.sha256()
    for path in wav_files + strum_files:
        digest.update((os.path.basename(path) + "\n").encode("utf-8"))
        with open(path, "rb") as fh:
            digest.update(fh.read())
    return digest.hexdigest()


def check_corpus_matches_baseline(data_dir: str, baseline_manifest_path: Path):
    """Returns (measured_sha, baseline_document) or raises
    CorpusHashMismatchError. Never returns a mismatched pair silently."""
    measured = corpus_sha256(data_dir)
    with open(baseline_manifest_path) as fh:
        baseline = json.load(fh)
    anchored = baseline["corpus"]["corpusSha256"]
    if measured != anchored:
        raise CorpusHashMismatchError(
            f"corpus hash mismatch: {data_dir} hashes to {measured}, but "
            f"{baseline_manifest_path} anchors corpusSha256={anchored} — "
            "refusing to compare against a different corpus (ADR 0517 D6); "
            "no document written"
        )
    return measured, baseline


def recompute_split(data_dir: str, held_out_guitarist: str):
    """Independent recomputation of the train/test recording-id partition —
    does NOT trust train_prototype.py's provenance, only its
    `heldOutGuitarist` choice (ADR 0517 D2: the evaluate script re-derives
    and re-checks the split itself)."""
    all_ids = recording_ids(data_dir)
    train_recordings = sorted(r for r in all_ids if guitarist_of(r) != held_out_guitarist)
    test_recordings = sorted(r for r in all_ids if guitarist_of(r) == held_out_guitarist)
    return train_recordings, test_recordings


def assert_no_leakage(train_recordings, test_recordings, held_out_guitarist: str) -> None:
    train_guitarists = {guitarist_of(r) for r in train_recordings}
    test_guitarists = {guitarist_of(r) for r in test_recordings}
    recording_overlap = set(train_recordings) & set(test_recordings)
    guitarist_overlap = train_guitarists & test_guitarists
    if recording_overlap or guitarist_overlap or test_guitarists != {held_out_guitarist}:
        raise GuitaristLeakageError(
            f"guitarist/recording leakage detected: recording_overlap="
            f"{sorted(recording_overlap)}, guitarist_overlap="
            f"{sorted(guitarist_overlap)}, test_guitarists="
            f"{sorted(test_guitarists)} (expected only {held_out_guitarist!r})"
            " — aborting before any document is written (ADR 0517 D2)"
        )


def detect_events(model, mean, std, pcm):
    """Scans the FULL recording at every 10 ms hop with `joint_window` (the
    same causal+lookahead geometry training used), then peak-picks onset
    events from 1-P(no-event) — same local-maximum + minimum-gap discipline
    as `ml/features.py::spectral_flux_onsets`, applied to the model's own
    confidence instead of spectral flux. Returns a list of
    (time_s, 'down'|'up', confidence)."""
    n = 1 + max(0, (len(pcm) - F.N_FFT) // F.HOP)
    if n < 3:
        return []
    windows = np.stack([joint_window(pcm, i * F.HOP / F.SR) for i in range(n)])
    normalized = (windows - mean) / std
    probs = model.predict(normalized, verbose=0, batch_size=1024)
    onset_score = 1.0 - probs[:, 2]
    directions = probs[:, :2].argmax(axis=1)

    events = []
    min_gap = max(1, int(round(PEAK_MIN_GAP_S * F.SR / F.HOP)))
    last = -min_gap
    for i in range(1, n - 1):
        if (
            onset_score[i] > PEAK_THRESHOLD
            and onset_score[i] >= onset_score[i - 1]
            and onset_score[i] >= onset_score[i + 1]
            and i - last >= min_gap
        ):
            direction = "down" if directions[i] == 0 else "up"
            events.append((i * F.HOP / F.SR, direction, float(onset_score[i])))
            last = i
    return events


def match_events(expected, detected, tolerance_s=ONSET_TOLERANCE_S):
    """Greedy nearest-available one-to-one time matching within an inclusive
    tolerance — a documented simplification of the production Kuhn's-
    algorithm maximum-cardinality matcher
    (`lib/features/live/domain/evaluation/recognition_metrics.dart::
    _matchEvents`); adequate for a research prototype's own internal
    comparison, not claimed to be optimal. Returns a list of
    (expected_index, detected_index) pairs."""
    used_detected = set()
    matches = []
    for e_index, (e_time, _e_dir) in enumerate(expected):
        best_index, best_gap = None, None
        for d_index, (d_time, _d_dir, _conf) in enumerate(detected):
            if d_index in used_detected:
                continue
            gap = abs(d_time - e_time)
            if gap <= tolerance_s and (best_gap is None or gap < best_gap):
                best_index, best_gap = d_index, gap
        if best_index is not None:
            used_detected.add(best_index)
            matches.append((e_index, best_index))
    return matches


def evaluate_test_fold(model, mean, std, data_dir, test_recordings):
    all_expected = []  # (time_s, direction) — direction in {down, up}
    all_detected = []  # (time_s, direction, confidence)
    all_matches = []  # (expected_global_index, detected_global_index)
    for rid in test_recordings:
        with open(os.path.join(data_dir, f"recording_{rid}.strums")) as fh:
            events = parse_strums(fh.read())
        pcm = _read_wav(os.path.join(data_dir, f"recording_{rid}_phone.wav"))
        expected = [(t, direction) for t, direction, _chord in events if t * F.SR < len(pcm)]
        detected = detect_events(model, mean, std, pcm)
        matches = match_events(expected, detected)

        expected_offset = len(all_expected)
        detected_offset = len(all_detected)
        all_matches.extend((e + expected_offset, d + detected_offset) for e, d in matches)
        all_expected.extend(expected)
        all_detected.extend(detected)
    return all_expected, all_detected, all_matches


def onset_f1(expected, detected, matches):
    true_positives = len(matches)
    false_positives = len(detected) - true_positives
    false_negatives = len(expected) - true_positives
    precision = (
        true_positives / (true_positives + false_positives)
        if (true_positives + false_positives) > 0
        else None
    )
    recall = (
        true_positives / (true_positives + false_negatives)
        if (true_positives + false_negatives) > 0
        else None
    )
    f1 = (
        2 * precision * recall / (precision + recall)
        if precision and recall and (precision + recall) > 0
        else 0.0
    )
    n = true_positives + false_positives + false_negatives
    return f1, n, {
        "truePositives": true_positives,
        "falsePositives": false_positives,
        "falseNegatives": false_negatives,
        "precision": precision,
        "recall": recall,
    }


def direction_macro_f1(expected, detected, matches):
    """Same definition as the production Dart metric
    (`recognition_metrics.dart`'s `directionF1`, ADR 0509): per-class true
    positives come ONLY from time-matched pairs with agreeing direction, but
    false positives/negatives are counted over the FULL detected/expected
    populations for that class — a strum missed or falsely detected in time
    (never time-matched at all) still counts against its own class."""
    per_class = {}
    for label in ("down", "up"):
        true_positives = sum(
            1
            for e_index, d_index in matches
            if expected[e_index][1] == label and detected[d_index][1] == label
        )
        total_detected = sum(1 for _t, direction, _c in detected if direction == label)
        total_expected = sum(1 for _t, direction in expected if direction == label)
        false_positives = total_detected - true_positives
        false_negatives = total_expected - true_positives
        precision = (
            true_positives / (true_positives + false_positives)
            if (true_positives + false_positives) > 0
            else None
        )
        recall = (
            true_positives / (true_positives + false_negatives)
            if (true_positives + false_negatives) > 0
            else None
        )
        if precision is None and recall is None:
            f1 = None
        elif not precision or not recall or (precision + recall) == 0:
            f1 = 0.0
        else:
            f1 = 2 * precision * recall / (precision + recall)
        per_class[label] = {
            "f1": f1,
            "truePositives": true_positives,
            "falsePositives": false_positives,
            "falseNegatives": false_negatives,
        }
    values = [entry["f1"] for entry in per_class.values() if entry["f1"] is not None]
    macro = sum(values) / len(values) if values else None
    n = sum(1 for _t, direction in expected if direction in per_class) + sum(
        1 for _t, direction, _c in detected if direction in per_class
    )
    return macro, n, per_class


def compare_to_threshold(value: float, threshold: float) -> str:
    if value < threshold:
        return "below"
    if value == threshold:
        return "at"
    return "above"


def build_document(
    *,
    corpus_sha: str,
    baseline_manifest_path: Path,
    recording_count: int,
    held_out_guitarist: str,
    train_recording_count: int,
    test_recording_count: int,
    epochs_run: int,
    batch_size: int,
    seed: int,
    model_param_count: int,
    wall_clock_seconds: float,
    prototype_onset_f1: float,
    prototype_onset_n: int,
    prototype_direction_f1,
    prototype_direction_n: int,
    legacy_onset_f1: float,
    legacy_onset_n: int,
    legacy_manifest_relpath: str,
    generated_at: str,
) -> dict:
    onset_comparison = compare_to_threshold(prototype_onset_f1, ONSET_ALPHA_THRESHOLD)
    direction_value = prototype_direction_f1 if prototype_direction_f1 is not None else 0.0
    direction_comparison = compare_to_threshold(direction_value, DIRECTION_ALPHA_THRESHOLD)
    both_meet_or_exceed = onset_comparison in ("at", "above") and direction_comparison in (
        "at",
        "above",
    )
    decision = "go" if both_meet_or_exceed else "no-go"

    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": generated_at,
        "corpus": {
            "corpusId": CORPUS_ID,
            "corpusSha256": corpus_sha,
            "recordingCount": recording_count,
            "matchesBaselineManifest": True,
            "baselineManifestPath": legacy_manifest_relpath,
        },
        "lookahead": {
            "preFrames": PRE_FRAMES,
            "lookaheadFrames": LOOKAHEAD_FRAMES,
            "hopMs": HOP_MS,
            "lookaheadMs": LOOKAHEAD_MS,
            "causal": LOOKAHEAD_FRAMES == 0,
            "note": (
                f"{PRE_FRAMES * HOP_MS:.0f}ms causal context + "
                f"{LOOKAHEAD_MS:.0f}ms controlled lookahead "
                f"({FRAMES} frames total) — far below the legacy direction "
                "classifier's 120ms post-onset window (PRE=3/POST=12 "
                "frames, ml/features.py)."
            ),
        },
        "splitStrategy": {
            "method": "leave-one-guitarist-out",
            "heldOutGuitarist": held_out_guitarist,
            "trainRecordingCount": train_recording_count,
            "testRecordingCount": test_recording_count,
            "leakageCheckPassed": True,
            "leakageCheckMethod": (
                "evaluate_prototype.py::assert_no_leakage recomputed the "
                "guitarist-id partition independently of the training run's "
                "provenance and asserted the train/test guitarist-id sets "
                "are disjoint and the test set is exactly the held-out "
                "guitarist (ADR 0517 D2)."
            ),
        },
        "config": {
            "epochs": epochs_run,
            "batchSize": batch_size,
            "seed": seed,
            "modelParamCount": model_param_count,
            "wallClockSeconds": wall_clock_seconds,
        },
        "metrics": {
            "prototypeOnsetF1At50ms": {
                "value": prototype_onset_f1,
                "n": prototype_onset_n,
                "definition": {
                    "text": (
                        "Precision/recall/F1 of peak-picked joint-model "
                        "onset events (1-P(no-event) local maxima, >=60ms "
                        "apart) against expected onset events, matched "
                        "within an inclusive 50ms tolerance via greedy "
                        "nearest-available one-to-one matching, ignoring "
                        "predicted direction."
                    ),
                    "higherIsBetter": True,
                },
            },
            "prototypeDirectionMacroF1": {
                "value": direction_value,
                "n": prototype_direction_n,
                "definition": {
                    "text": (
                        "Macro-averaged per-direction (down/up) F1: "
                        "per-class true positives come only from "
                        "time-matched onset pairs whose expected and "
                        "detected direction both equal that class; false "
                        "positives/negatives are counted over the FULL "
                        "detected/expected populations for that class (same "
                        "definition as recognition_metrics.dart's "
                        "directionF1, ADR 0509)."
                    ),
                    "higherIsBetter": True,
                },
            },
            "prototypeAlgorithmicLatencyMs": {
                "value": LOOKAHEAD_MS,
                "n": 1,
                "definition": {
                    "text": (
                        "Algorithmic verdict latency: the model cannot "
                        "commit to a down/up/no-event verdict until it has "
                        "observed lookaheadFrames*hopMs of audio after the "
                        "candidate time — not a real-time on-device "
                        "measurement (no device clock was sampled)."
                    ),
                    "higherIsBetter": False,
                },
            },
            "legacyOnsetF1At50ms": {
                "value": legacy_onset_f1,
                "n": legacy_onset_n,
                "sourceFile": legacy_manifest_relpath,
                "definition": {
                    "text": (
                        "Legacy two-stage pipeline's SuperFlux onset "
                        "detector F1 at 50ms tolerance, anchored from the "
                        "merged baseline manifest (ADR 0354), same corpus "
                        "(hash-verified by this script before any number "
                        "was read)."
                    ),
                    "higherIsBetter": True,
                },
            },
            "legacyDirectionF1UpperBound": {
                "value": legacy_onset_f1,
                "n": legacy_onset_n,
                "sourceFile": legacy_manifest_relpath,
                "bound": "upper",
                "derivation": (
                    "The legacy end-to-end direction macro-F1 is not "
                    "measured on this corpus (baseline_manifest.json "
                    "metricBlocks.direction.status = not-measured). A "
                    "correct end-to-end direction call requires a "
                    "correctly time-matched onset first (TP_direction is a "
                    "subset of TP_onset), so end-to-end direction macro-F1 "
                    "cannot exceed onset F1 @50ms — this row restates that "
                    "onset F1 as an explicit ceiling, never a direction "
                    "measurement, and never grounds a claim that the "
                    "prototype beats the legacy pipeline on direction."
                ),
                "definition": {
                    "text": (
                        "Upper bound on the legacy pipeline's end-to-end "
                        "direction macro-F1, derived from its onset F1 "
                        "@50ms via the onset-precedes-direction inequality."
                    ),
                    "higherIsBetter": True,
                },
            },
        },
        "verdict": {
            "alphaThresholds": {
                "onsetF1At50ms": ONSET_ALPHA_THRESHOLD,
                "directionMacroF1": DIRECTION_ALPHA_THRESHOLD,
            },
            "onsetF1Comparison": onset_comparison,
            "directionF1Comparison": direction_comparison,
            "decision": decision,
            "rationale": (
                f"onset F1 @50ms={prototype_onset_f1:.4f} is {onset_comparison} "
                f"the {ONSET_ALPHA_THRESHOLD} Alpha gate; direction macro-F1="
                f"{direction_value:.4f} is {direction_comparison} the "
                f"{DIRECTION_ALPHA_THRESHOLD} Alpha gate. Decision is \"go\" "
                "iff BOTH meet or exceed their threshold (ADR 0517 D4, "
                "inclusive boundary)."
            ),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--workdir", required=True, type=str)
    parser.add_argument("--data-dir", default=str(ML_ROOT / "data" / "klangio"))
    parser.add_argument(
        "--baseline-manifest", default=str(DEFAULT_BASELINE_MANIFEST), type=str
    )
    parser.add_argument("--output", default=None, type=str)
    args = parser.parse_args(argv)

    workdir = Path(args.workdir).expanduser().resolve()
    provenance_path = workdir / "joint_prototype_provenance.json"
    weights_path = workdir / "joint_prototype_weights.npz"
    if not provenance_path.is_file() or not weights_path.is_file():
        print(
            f"error: missing {provenance_path} or {weights_path} — run "
            "train_prototype.py --workdir <this workdir> first",
            file=sys.stderr,
        )
        return 1

    baseline_manifest_path = Path(args.baseline_manifest).resolve()
    try:
        corpus_sha, _baseline_doc = check_corpus_matches_baseline(
            args.data_dir, baseline_manifest_path
        )
    except CorpusHashMismatchError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    with open(provenance_path) as fh:
        provenance = json.load(fh)
    held_out_guitarist = provenance["heldOutGuitarist"]

    train_recordings, test_recordings = recompute_split(args.data_dir, held_out_guitarist)
    try:
        assert_no_leakage(train_recordings, test_recordings, held_out_guitarist)
    except GuitaristLeakageError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    import tensorflow as tf  # noqa: PLC0415,F401 — only the venv interpreter has this

    model = build_model(FRAMES, F.N_MELS, seed=provenance["seed"])
    weights_npz = np.load(weights_path)
    array_count = len(weights_npz.files) - 2  # minus mean/std
    model.set_weights([weights_npz[f"arr_{i}"] for i in range(array_count)])
    mean = weights_npz["mean"]
    std = weights_npz["std"]

    t0 = time.time()
    expected, detected, matches = evaluate_test_fold(
        model, mean, std, args.data_dir, test_recordings
    )
    eval_wall_clock = time.time() - t0
    print(
        f"scanned {len(test_recordings)} test recordings in "
        f"{eval_wall_clock:.1f}s — {len(expected)} expected events, "
        f"{len(detected)} detected events, {len(matches)} time-matched"
    )

    proto_onset_f1, proto_onset_n, onset_detail = onset_f1(expected, detected, matches)
    proto_direction_f1, proto_direction_n, direction_detail = direction_macro_f1(
        expected, detected, matches
    )
    print(f"onset_detail={onset_detail}")
    print(f"direction_detail={direction_detail}")

    with open(baseline_manifest_path) as fh:
        baseline = json.load(fh)
    legacy_metric = baseline["metricBlocks"]["onset"]["metrics"]["tolerance50000us.f1"]
    legacy_manifest_relpath = str(
        baseline_manifest_path.relative_to(REPO_ROOT)
    ).replace(os.sep, "/")

    document = build_document(
        corpus_sha=corpus_sha,
        baseline_manifest_path=baseline_manifest_path,
        recording_count=baseline["corpus"]["recordingCount"],
        held_out_guitarist=held_out_guitarist,
        train_recording_count=len(train_recordings),
        test_recording_count=len(test_recordings),
        epochs_run=provenance["epochsRun"],
        batch_size=provenance["batchSize"],
        seed=provenance["seed"],
        model_param_count=provenance["modelParamCount"],
        wall_clock_seconds=provenance["wallClockSeconds"],
        prototype_onset_f1=proto_onset_f1,
        prototype_onset_n=proto_onset_n,
        prototype_direction_f1=proto_direction_f1,
        prototype_direction_n=proto_direction_n,
        legacy_onset_f1=legacy_metric["value"],
        legacy_onset_n=legacy_metric["n"],
        legacy_manifest_relpath=legacy_manifest_relpath,
        generated_at=provenance.get("generatedAt", "unknown"),
    )

    output_path = (
        Path(args.output).expanduser().resolve()
        if args.output
        else workdir / "joint_io_document.json"
    )
    with open(output_path, "w") as fh:
        json.dump(document, fh, indent=2)
    print(f"wrote {output_path}")
    print(json.dumps(document, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
