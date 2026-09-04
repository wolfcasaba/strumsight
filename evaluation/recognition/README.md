# Recognition baseline manifests

Machine-readable evidence for the legacy-DSP recognition baseline
(E14-R02, [ADR 0354](../../docs/adr/0354-recognition-baseline-manifest-and-evidence-index.md)).
This directory sits next to the existing `evaluation/analysis/` and
`evaluation/tutor/` corpora and follows the same repo-root `evaluation/`
convention — it does not introduce a new pattern.

## What lives here

- `baseline_manifest_schema.json` — the JSON Schema (draft-07) contract that
  `tool/benchmarks/recognition_baseline_manifest.dart` enforces by hand
  (ADR 0354 D8 — no schema-library dependency).
- `baseline_manifest.json` — the single machine-readable record of the
  measured legacy-DSP baseline: corpus identity, app commit, configuration,
  and, per metric block, either `status: "measured"` with a value/n/
  sourceFile/command quadruple for every number, or `status: "not-measured"`
  with a stated reason (ADR 0354 D3).

Render the human-readable index and check the manifest is up to date with:

```bash
dart run tool/benchmarks/recognition_baseline_manifest.dart          # (re)renders docs/eval/recognition-baseline-index.md
dart run tool/benchmarks/recognition_baseline_manifest.dart --check  # validates only, fails if the index is stale
```

## Data governance (ADR 0354)

1. **No raw audio in the repository, ever.** `baseline_manifest.json` records
   only `corpusId`, `corpusSha256`, `recordingCount`, and `eventCount` — never
   a byte of the underlying recordings. The corpus this round's numbers came
   from (`ml/data/klangio`) lives outside the repository, on the
   device/audio-evaluation owner's box (ADR 0354 D1).
2. **Every number carries its own source file and measurement command.**
   A metric entry with `status: "measured"` requires `value`, `n`,
   `sourceFile`, and `command` — a document-level "see the report" footnote
   is not an acceptable substitute (ADR 0354 D2). `n = 0` is a schema
   violation, not a valid measurement of nothing.
3. **"Not measured" is a first-class state, not a missing field.** Every
   metric block (`onset`, `direction`, `chord`, `noChord`, `latency`,
   `calibration`) states its `status` explicitly; a `not-measured` block
   carries a non-empty `notMeasuredReason` and no `metrics` key at all
   (ADR 0354 D3).
4. **A retracted claim stays retracted, mechanically.** The `bpm` block is
   not one of the six metric blocks — it always carries `retracted: true`
   and a `retractedReason`, and the rendered index marks it **RETRACTED**
   rather than silently dropping the number (ADR 0354 D4).
5. **An empty `models` list requires a stated rationale.** When a
   measurement used no ML weight, `models` is `[]` and the non-empty
   `modelsRationale` field says so explicitly — an empty list with no
   rationale, or a model hash copied in "for completeness" that never
   actually ran, are both schema/checker violations (ADR 0354 D7).

## Reproducing a byte-identical index

`tool/benchmarks/recognition_baseline_manifest.dart` never calls a clock:
the only timestamp anywhere in the render is the manifest's own
`generatedAt` field. Given the same schema and manifest text, running the
tool twice produces byte-identical Markdown — keys are rendered in
alphabetical order and every float uses `toStringAsFixed(3)` (ADR 0354 D5).
`test/tooling/recognition_baseline_manifest_test.dart` measures this
directly, including the falsification cell recorded in
[the round handoff](../../docs/rounds/e14-r02-baseline-and-evidence-index.md).

See `baseline_manifest_schema.json` for the full, machine-checkable contract
and `docs/eval/recognition-baseline-index.md` for the rendered index.
