# Audio Analysis evaluation manifests

Ground-truth manifests for the Audio Analysis V2 evaluation harness
(E06-R29, [ADR 0249](../../docs/adr/0249-analysis-evaluation-dataset-governance.md)).
This directory sits next to the existing `evaluation/tutor/` corpus and
follows the same repo-root `evaluation/` convention — it does not introduce a
new pattern.

## What lives here

- `manifest_schema.json` — the JSON Schema (draft-07) contract that
  `EvaluationManifestParser` enforces.
- `fixtures/ci_manifest.json` — the **small, synthetic** manifest run in CI
  via `tools/round-gate.sh test/features/audio_analysis test/tooling` and by
  `tool/audio_analysis_evaluate.dart`.

## Data governance (ADR 0249)

1. **No raw audio in the repository, ever.** Every manifest here contains
   only annotations (event timestamps, chord segments, tempo, confidence
   observations) and — optionally — the parameters a synthesizer would use to
   regenerate a matching clip at runtime. No `.wav`/`.mp3`/`.m4a` byte
   payload is committed. `test/tooling/analysis_evaluation_regression_test.dart`
   enforces this with a `git diff --stat` check.
2. **Real, licensed recordings live outside the repository**, in an
   access-controlled store the device/audio-evaluation owner manages
   directly. Running the harness against that external manifest is a manual
   step (`dart run tool/audio_analysis_evaluate.dart --manifest <external path>`)
   and its results close `docs/manual-testing/analysis-eval-matrix.md` PENDING
   rows — it is never a CI merge gate, because this box has no device lab and
   no repo-committed physical recordings.
3. **The CI fixture measures the harness, not model accuracy.** `ci_manifest.json`
   is entirely synthetic: every case's `detected` annotation set is a
   hand-authored, deterministic perturbation of its `expected` set, written to
   exercise the parser, the nine metrics, the slice breakdown, and the
   regression gate — not to claim a real confidence number for the shipped
   detector. See ADR 0249 §Döntés 3.
4. **Confidence calibration only ships from real, labelled data.** The CI
   fixture's `confidenceObservations` intentionally stay well under the
   30-per-bin / 300-total minimum (ADR 0249 §Döntés 4), so
   `CalibrationFitter` honestly reports `insufficientData: true` and
   `CalibrationTable.identityV1()` — never a curve fitted from a handful of
   synthetic points.
5. **No private paths.** Manifests and the reports the harness produces from
   them must never contain an absolute filesystem path or a username;
   `test/tooling/analysis_evaluation_regression_test.dart` scans for this.

## Running the harness

```bash
dart run tool/audio_analysis_evaluate.dart
# or against an external, licensed manifest:
dart run tool/audio_analysis_evaluate.dart --manifest /path/to/real-manifest.json
```

The tool prints a deterministic `EvaluationReport` JSON to stdout (no
timestamps, no wall-clock, no random ordering — the same manifest and code
always produce byte-identical output) and exits non-zero if the manifest
fails to parse.

## Manifest authoring rules

- `schemaVersion` must be `"1.0"`; the parser rejects anything else.
- Case `id` values must be unique within a manifest.
- A `strum`-typed event requires a `direction`; every other event type must
  omit it.
- A `chordSegment`'s `endMs` must be `>= startMs`.
- Every JSON object is closed (`additionalProperties: false` in the schema) —
  an unrecognised key is a typed parser failure, not a silently ignored field.

See `manifest_schema.json` for the full, machine-checkable contract and
`fixtures/ci_manifest.json` for a worked example covering silence, both
metered tempi (60/120 BPM), 3/4 and 4/4 time signatures, two- and
four-chord progressions, ring-out, clipped/quiet/noisy signal quality, a
monophonic scale, and a chord-change case.
