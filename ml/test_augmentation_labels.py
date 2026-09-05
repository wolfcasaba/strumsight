"""E14-R19 (ADR 0525) tests: seeded, manifested, switchable augmentation.

Covers the round's acceptance criteria (round brief §6 / §6.1):
  1. whole-semitone, label-transposing pitch shift (±1/±3/±6 matrix, N.C.
     invariance, non-whole input -> TypeError) reusing the ALREADY-MERGED
     `chords.labels.transpose_class` (round brief R11/ADR 0525 D10) —
     this file does NOT reimplement the class arithmetic.
  2. the ±6 range boundary is INCLUSIVE (±5 ok, ±6 ok, ±7 -> ValueError).
  3. same seed -> bit-identical output; different seed -> different output,
     measured through the SHIPPED composed entry points (L631).
  4. every transform disabled -> output bit-identical to the raw input.
  5. the manifest contract: seed/transforms/classRatios required, a missing
     field is a typed error, in the Python validator (the Dart-side mirror
     lives in test/tooling/augmentation_manifest_test.dart, R8).
  6. "nem mert" (not measured) is never numeric 0, and never paired with an
     "accepted" status.
  7. the shipped composite recipe (r173) manifest entry is "rejected".
  8. regression: `augment_pcm` (existing, r173) is byte-for-byte unchanged
     for a pinned seed.

Run: `python3 -m pytest ml/test_augmentation_labels.py -q` (from repo root)
or `python3 -m pytest ml -q` (full ml regression, round brief §7).
"""
from __future__ import annotations

import copy
import hashlib

import numpy as np
import pytest

import augment as A
import features as F
from chords.labels import NO_CHORD, class_to_label, transpose_class

SR = F.SR


def _tone(freq=220.0, seconds=1.0, sr=SR):
    t = np.arange(int(seconds * sr)) / sr
    return (0.5 * np.sin(2 * np.pi * freq * t)).astype(np.float32)


# ---------------------------------------------------------------------------
# 1. Whole-semitone, label-transposing pitch shift (round brief AC1)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("semitones", [-6, -3, -1, 1, 3, 6])
def test_label_transpose_matrix_moves_class_by_exactly_n_semitones(semitones):
    pcm = _tone()
    onsets = np.array([0.1, 0.5])
    c_major = 1  # chords.labels: 1 = C major
    aug, ao, classes = A.transpose_pcm_and_chord_labels(
        pcm, onsets, [c_major, c_major], semitones)
    expected = transpose_class(c_major, semitones)
    assert np.all(classes == expected)
    assert len(ao) == len(onsets)
    assert np.all(np.isfinite(aug))


def test_label_transpose_uses_the_merged_transpose_class_not_a_reimplementation():
    # Cross-check against a hand-picked, independently-known mapping (A minor
    # -1 semitone -> G# minor) so this test would catch a parallel, silently
    # DIFFERENT class-math implementation (round brief R11).
    pcm = _tone()
    _aug, _ao, classes = A.transpose_pcm_and_chord_labels(pcm, [0.2], [22], -1)
    assert class_to_label(int(classes[0])) == "G#m"


def test_nc_class_is_invariant_under_label_transpose():
    pcm = _tone()
    for semitones in (-6, -3, 0, 3, 6):
        _aug, _ao, classes = A.transpose_pcm_and_chord_labels(
            pcm, [0.2], [NO_CHORD], semitones)
        assert classes[0] == NO_CHORD


def test_non_whole_semitone_raises_typeerror_not_silently_rounded():
    pcm = _tone()
    with pytest.raises(TypeError):
        A.transpose_pcm_and_chord_labels(pcm, [0.2], [1], 3.4)


def test_bool_semitone_is_rejected_as_a_typed_error():
    pcm = _tone()
    with pytest.raises(TypeError):
        A.transpose_pcm_and_chord_labels(pcm, [0.2], [1], True)


# ---------------------------------------------------------------------------
# 2. The ±6 boundary is INCLUSIVE (round brief AC2)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("semitones", [-5, 5])
def test_below_the_boundary_is_accepted(semitones):
    pcm = _tone()
    A.transpose_pcm_and_chord_labels(pcm, [0.2], [1], semitones)  # no raise


@pytest.mark.parametrize("semitones", [-6, 6])
def test_exactly_on_the_boundary_is_accepted_inclusive(semitones):
    pcm = _tone()
    A.transpose_pcm_and_chord_labels(pcm, [0.2], [1], semitones)  # no raise


@pytest.mark.parametrize("semitones", [-7, 7])
def test_above_the_boundary_is_a_typed_error(semitones):
    pcm = _tone()
    with pytest.raises(ValueError):
        A.transpose_pcm_and_chord_labels(pcm, [0.2], [1], semitones)


# ---------------------------------------------------------------------------
# 3. Determinism per seed, measured through the SHIPPED entry points (L631)
# ---------------------------------------------------------------------------

def test_random_label_transposing_shift_is_deterministic_per_seed():
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    classes = [1, 5]
    a1, o1, c1 = A.random_label_transposing_shift(
        pcm, onsets.copy(), classes, np.random.default_rng(11))
    a2, o2, c2 = A.random_label_transposing_shift(
        pcm, onsets.copy(), classes, np.random.default_rng(11))
    assert np.array_equal(a1, a2)
    assert np.array_equal(o1, o2)
    assert np.array_equal(c1, c2)

    a3, _o3, _c3 = A.random_label_transposing_shift(
        pcm, onsets.copy(), classes, np.random.default_rng(12))
    assert not (a1.shape == a3.shape and np.array_equal(a1, a3))


def test_augment_pcm_with_chord_labels_is_deterministic_per_seed():
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    classes = [1, 5]
    a1, o1, c1 = A.augment_pcm_with_chord_labels(
        pcm, onsets.copy(), classes, np.random.default_rng(21))
    a2, o2, c2 = A.augment_pcm_with_chord_labels(
        pcm, onsets.copy(), classes, np.random.default_rng(21))
    assert np.array_equal(a1, a2) and np.array_equal(o1, o2) and np.array_equal(c1, c2)

    a3, _o3, _c3 = A.augment_pcm_with_chord_labels(
        pcm, onsets.copy(), classes, np.random.default_rng(22))
    assert not (a1.shape == a3.shape and np.array_equal(a1, a3))


def test_augment_pcm_configurable_is_deterministic_per_seed():
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    a1, o1 = A.augment_pcm_configurable(pcm, onsets.copy(), np.random.default_rng(31))
    a2, o2 = A.augment_pcm_configurable(pcm, onsets.copy(), np.random.default_rng(31))
    assert np.array_equal(a1, a2) and np.array_equal(o1, o2)

    a3, _o3 = A.augment_pcm_configurable(pcm, onsets.copy(), np.random.default_rng(32))
    assert not (a1.shape == a3.shape and np.array_equal(a1, a3))


# ---------------------------------------------------------------------------
# 4. Every transform disabled -> bit-identical to the raw input (AC4)
# ---------------------------------------------------------------------------

_ALL_DISABLED = {name: {"enabled": False} for name in A.DEFAULT_TRANSFORM_CONFIG}


def test_configurable_augmentor_all_disabled_is_bit_identical_to_input():
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    out, out_onsets = A.augment_pcm_configurable(
        pcm, onsets.copy(), np.random.default_rng(1), config=_ALL_DISABLED)
    assert np.array_equal(out, pcm)
    assert np.array_equal(out_onsets, onsets)


def test_label_aware_augmentor_all_disabled_is_bit_identical_to_input():
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    classes = np.array([1, 5])
    out, out_onsets, out_classes = A.augment_pcm_with_chord_labels(
        pcm, onsets.copy(), classes.copy(), np.random.default_rng(1),
        config=_ALL_DISABLED)
    assert np.array_equal(out, pcm)
    assert np.array_equal(out_onsets, onsets)
    assert np.array_equal(out_classes, classes)


def test_only_pitch_shift_enabled_still_moves_the_signal():
    # Sanity counterpart to the all-disabled cells above: turning exactly one
    # switch back on must, in general, change the output (guards against an
    # implementation that ignores `enabled` entirely).
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    cfg = copy.deepcopy(_ALL_DISABLED)
    cfg["pitch_shift"] = {"enabled": True, "semitone_range": 6.0}
    out, out_onsets = A.augment_pcm_configurable(
        pcm, onsets.copy(), np.random.default_rng(5), config=cfg)
    assert not np.array_equal(out_onsets, onsets) or not np.array_equal(out, pcm)


# ---------------------------------------------------------------------------
# 5/6. The manifest contract (round brief AC5/AC6, ADR 0525 D5/D6/D8)
# ---------------------------------------------------------------------------

def _valid_transform(name="pitch_shift_label_transpose", status="candidate",
                     measured="nem mért", cost=10769.7, enabled=True):
    transform = {
        "name": name,
        "enabled": enabled,
        "params": {"semitoneRangeMax": 6},
        "status": status,
        "measured": measured,
        "reproCommand": "python3 ml/honest_eval.py logo <transform>_only",
    }
    if measured == A._NOT_MEASURED:
        transform["costBasisSeconds"] = cost
        transform["costBasisSource"] = (
            "ml/honest_results.json r173 _timing (gitignored, box-local) — a "
            "representative basis, not a per-transform measured cost")
    else:
        transform["measuredCostSeconds"] = cost
    return transform


def _valid_manifest(**overrides):
    manifest = {
        "schemaVersion": "1.0",
        "seed": 42,
        "transforms": [_valid_transform()],
        "classRatios": {
            "direction": {
                "baseline": {"down": 0.42, "up": 0.40, "noStrum": 0.18},
                "balanced": {"down": 0.3334, "up": 0.3333, "noStrum": 0.3333},
            },
            "chord": {
                "baseline": {"N.C.": 0.35, "major": 0.44, "minor": 0.21},
                "balanced": {"N.C.": 0.3334, "major": 0.3333, "minor": 0.3333},
            },
        },
        "pitchShiftLimits": dict(A.PITCH_SHIFT_LIMITS),
        "balancing": {"method": "resample_with_replacement", "dropsRealData": False},
        "provenance": {
            "generatedFrom": "unit-test fixture, not a real run",
            "datasetSource": "unit-test fixture, not a real dataset",
            "classRatiosSource": "illustrative — not measured (unit-test fixture)",
        },
    }
    manifest.update(overrides)
    return manifest


def test_a_well_formed_manifest_validates_cleanly():
    A.validate_manifest(_valid_manifest())  # no raise


def test_missing_seed_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["seed"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_missing_transforms_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["transforms"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_transform_missing_status_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["transforms"][0]["status"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_missing_class_ratios_group_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["classRatios"]["chord"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_missing_balanced_phase_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["classRatios"]["direction"]["balanced"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_numeric_zero_for_a_missing_measurement_is_rejected():
    manifest = _valid_manifest()
    manifest["transforms"][0]["measured"] = 0
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_not_measured_row_with_accepted_status_is_rejected():
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "accepted"
    manifest["transforms"][0]["measured"] = "nem mért"
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


def test_not_measured_row_with_candidate_or_rejected_status_is_fine():
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "rejected"
    manifest["transforms"][0]["enabled"] = False
    manifest["transforms"][0]["measured"] = "nem mért"
    A.validate_manifest(manifest)  # no raise


def test_measured_row_claiming_accepted_without_improvement_is_rejected():
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "accepted"
    manifest["transforms"][0]["measuredCostSeconds"] = 10769.7
    manifest["transforms"][0]["measured"] = {
        "unseenPlayerSplits": [
            {"split": "logoBatch", "baseline": 0.7066, "baselineStdDev": 0.0165,
             "treated": 0.6985, "treatedStdDev": 0.0093, "delta": -0.0081},
        ],
    }
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


def test_measured_row_with_clean_improvement_cannot_be_rejected():
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "rejected"
    manifest["transforms"][0]["enabled"] = False
    manifest["transforms"][0]["measuredCostSeconds"] = 10769.7
    manifest["transforms"][0]["measured"] = {
        "unseenPlayerSplits": [
            {"split": "logoBatch", "baseline": 0.60, "baselineStdDev": 0.01,
             "treated": 0.70, "treatedStdDev": 0.01, "delta": 0.10},
        ],
    }
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


def test_measured_row_with_clean_improvement_can_be_accepted():
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "accepted"
    manifest["transforms"][0]["measuredCostSeconds"] = 10769.7
    manifest["transforms"][0]["measured"] = {
        "unseenPlayerSplits": [
            {"split": "logoBatch", "baseline": 0.60, "baselineStdDev": 0.01,
             "treated": 0.70, "treatedStdDev": 0.01, "delta": 0.10},
        ],
    }
    A.validate_manifest(manifest)  # no raise


def test_inconsistent_delta_is_rejected():
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "rejected"
    manifest["transforms"][0]["enabled"] = False
    manifest["transforms"][0]["measuredCostSeconds"] = 10769.7
    manifest["transforms"][0]["measured"] = {
        "unseenPlayerSplits": [
            {"split": "logoBatch", "baseline": 0.60, "baselineStdDev": 0.01,
             "treated": 0.70, "treatedStdDev": 0.01, "delta": -0.10},
        ],
    }
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


def test_status_rejected_with_enabled_true_is_rejected():
    # MAJOR-2 (review E14-R19): a measured-regressing row cannot claim to be
    # a member of the actually-running set.
    manifest = _valid_manifest()
    manifest["transforms"][0]["status"] = "rejected"
    manifest["transforms"][0]["enabled"] = True
    manifest["transforms"][0]["measured"] = "nem mért"
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


def test_missing_cost_basis_seconds_on_a_not_measured_row_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["transforms"][0]["costBasisSeconds"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_missing_cost_basis_source_on_a_not_measured_row_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["transforms"][0]["costBasisSource"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_fractional_configured_semitone_range_is_a_typed_error_not_silently_truncated():
    # MINOR-2 (review E14-R19): `int(cfg["pitch_shift"]["semitone_range"])`
    # used to silently truncate a fractional configured range (e.g. 6.5 -> 6).
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    classes = np.array([1, 5])
    cfg = copy.deepcopy(A.DEFAULT_TRANSFORM_CONFIG)
    cfg["pitch_shift"] = {"enabled": True, "semitone_range": 6.5}
    with pytest.raises(TypeError):
        A.augment_pcm_with_chord_labels(
            pcm, onsets.copy(), classes.copy(), np.random.default_rng(1), config=cfg)


def test_whole_configured_semitone_range_still_works():
    pcm = _tone()
    onsets = np.array([0.2, 0.6])
    classes = np.array([1, 5])
    cfg = copy.deepcopy(A.DEFAULT_TRANSFORM_CONFIG)
    cfg["pitch_shift"] = {"enabled": True, "semitone_range": 6.0}
    A.augment_pcm_with_chord_labels(
        pcm, onsets.copy(), classes.copy(), np.random.default_rng(1), config=cfg)  # no raise


def test_dropping_real_data_during_balancing_is_rejected():
    manifest = _valid_manifest()
    manifest["balancing"]["dropsRealData"] = True
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


def test_pitch_shift_limits_must_carry_the_two_distinct_literal_bounds():
    manifest = _valid_manifest()
    manifest["pitchShiftLimits"]["cqtChordTrackMaxSemitones"] = 6  # conflated!
    with pytest.raises(ValueError):
        A.validate_manifest(manifest)


# ---------------------------------------------------------------------------
# Provenance (review E14-R19 MAJOR-2): the manifest must say WHICH run/config
# it describes, and must not be silent about an illustrative classRatios.
# ---------------------------------------------------------------------------

def test_missing_provenance_block_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["provenance"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_missing_generated_from_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["provenance"]["generatedFrom"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_missing_class_ratios_source_is_a_typed_error():
    manifest = _valid_manifest()
    del manifest["provenance"]["classRatiosSource"]
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_empty_dataset_source_is_a_typed_error():
    manifest = _valid_manifest()
    manifest["provenance"]["datasetSource"] = ""
    with pytest.raises(TypeError):
        A.validate_manifest(manifest)


def test_build_manifest_requires_provenance():
    with pytest.raises(TypeError):
        A.build_manifest(
            seed=42, transforms=[_valid_transform()],
            direction_ratios={"baseline": {"a": 1.0}, "balanced": {"a": 1.0}},
            chord_ratios={"baseline": {"a": 1.0}, "balanced": {"a": 1.0}},
            provenance={"generatedFrom": "x"})  # missing datasetSource/classRatiosSource


# ---------------------------------------------------------------------------
# The shipped manifest (round brief AC7) and its CI-side twin (review
# E14-R19 MAJOR-1: nothing else pins these two files to each other)
# ---------------------------------------------------------------------------

def test_the_shipped_ml_augmentation_manifest_json_validates_cleanly():
    import json
    import pathlib
    manifest_path = pathlib.Path(__file__).parent / "augmentation_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    A.validate_manifest(manifest)  # no raise

    composite = next(
        t for t in manifest["transforms"] if t["name"] == "composite_recipe_r173")
    assert composite["status"] == "rejected"  # round brief AC7
    assert composite["enabled"] is False  # ADR 0525 D6/D9, review MAJOR-2


def test_shipped_manifest_matches_the_dart_guard_ci_fixture_byte_for_byte():
    # MAJOR-1 (review E14-R19): the CI-side Dart guard only ever reads the
    # fixture copy, never the real ml/augmentation_manifest.json — nothing
    # else pins the two together. This cell (and its Dart-side twin in
    # test/tooling/augmentation_manifest_test.dart) is that pin.
    import json
    import pathlib
    root = pathlib.Path(__file__).parent.parent
    manifest = json.loads((root / "ml" / "augmentation_manifest.json").read_text())
    fixture = json.loads((root / "evaluation" / "recognition" / "fixtures"
                          / "augmentation_manifest_sample.json").read_text())
    assert manifest == fixture, (
        "ml/augmentation_manifest.json and the CI-side Dart-guard fixture "
        "have drifted apart")


_MANIFEST_NAME_TO_CONFIG_KEY = {
    "pitch_shift_continuous": "pitch_shift",
    "pitch_shift_label_transpose": "pitch_shift",
    "room_ir_reverb": "reverb",
    "gain": "gain",
    "device_response": "device_response",
    "mic_sim": "mic_sim",
    "compression": "compression",
    "additive_snr_noise": "add_noise",
    "traffic_ambient_noise": "traffic_noise",
    "transient_burst": "transient_burst",
}


def test_shipped_manifest_enabled_flags_mirror_default_transform_config():
    # MAJOR-2 (review E14-R19): the manifest must describe the shipped
    # baseline config, not an arbitrary all-on recipe.
    import json
    import pathlib
    manifest_path = pathlib.Path(__file__).parent / "augmentation_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    by_name = {t["name"]: t for t in manifest["transforms"]}
    for name, config_key in _MANIFEST_NAME_TO_CONFIG_KEY.items():
        expected = A.DEFAULT_TRANSFORM_CONFIG[config_key]["enabled"]
        assert by_name[name]["enabled"] == expected, (
            f"{name}.enabled={by_name[name]['enabled']!r} does not match "
            f"DEFAULT_TRANSFORM_CONFIG[{config_key!r}]['enabled']={expected!r}")


# ---------------------------------------------------------------------------
# Class balancing (ADR 0525 D8): never drop real data
# ---------------------------------------------------------------------------

def test_balance_indices_keeps_every_original_row():
    labels = np.array(["down"] * 40 + ["up"] * 30 + ["noStrum"] * 5)
    rng = np.random.default_rng(3)
    idx = A.balance_indices(labels, rng)
    assert set(range(len(labels))).issubset(set(idx.tolist()))


def test_balance_indices_equalizes_class_counts():
    labels = np.array(["down"] * 40 + ["up"] * 30 + ["noStrum"] * 5)
    rng = np.random.default_rng(3)
    idx = A.balance_indices(labels, rng)
    ratios = A.class_ratios(labels[idx])
    values = list(ratios.values())
    assert max(values) - min(values) < 1e-9


def test_class_ratios_sums_to_one():
    labels = np.array([1, 1, 2, 3, 3, 3])
    ratios = A.class_ratios(labels)
    assert abs(sum(ratios.values()) - 1.0) < 1e-9


# ---------------------------------------------------------------------------
# 8. Regression: `augment_pcm` (existing, r173) is byte-for-byte unchanged
#    for a pinned seed (round brief AC8, §9).
# ---------------------------------------------------------------------------

_PINNED_DIGEST = (
    "5b4c27a5b0af82922e66eb2c47427e24db49f4775f80d81a36c495c60f1e181f"
)


def test_existing_augment_pcm_is_byte_identical_for_a_pinned_seed():
    pcm = (0.5 * np.sin(2 * np.pi * 220 * np.arange(SR) / SR)).astype(np.float32)
    onsets = np.array([0.2, 0.6])
    rng = np.random.default_rng(1234)
    aug, ao = A.augment_pcm(pcm, onsets.copy(), rng)
    digest = hashlib.sha256()
    digest.update(aug.tobytes())
    digest.update(ao.tobytes())
    assert digest.hexdigest() == _PINNED_DIGEST, (
        "ml/augment.py::augment_pcm changed behaviour for a pinned seed — "
        "the E14-R19 extension must be purely additive (round brief §9)")


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
