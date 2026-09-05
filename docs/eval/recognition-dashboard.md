# Recognition dashboard report — reading guide (E14-R09)

This is the reading guide for the single-source dashboard report and the
fail-closed release gate built on top of the E14-R08 grouped-recognition
metric set (ADR 0509). It does not repeat that metric set's definitions —
see `lib/features/live/domain/evaluation/recognition_metrics.dart` and
`docs/adr/0511-recognition-release-gate-and-single-source-report.md` for the
architectural decisions this round implements.

## What this round adds

| Artefact | Role |
|---|---|
| `evaluation/recognition/recognition_release_gate.json` | Versioned threshold file (v1), pinned to the SDD Ch14 §7.2/§7.4 Alpha values. Review-gated — see [Changing the thresholds](#changing-the-thresholds). |
| `lib/features/live/domain/evaluation/recognition_release_gate.dart` | Parses the threshold file and evaluates it against a `RecognitionMetrics` instance. Fail-closed: a missing or `null` metric is a `FAIL`, named. |
| `lib/features/live/data/evaluation/recognition_report_renderer.dart` | Builds the single `RecognitionDashboardReport` intermediate model (group partition + event categories + gate verdict) and renders it as JSON, Markdown or HTML — all three from the same already-rounded values. |
| `tool/recognition_report.dart` | CLI: `dart run tool/recognition_report.dart [--manifest PATH] [--thresholds PATH] [--format json\|markdown\|html]`. Exits `0` when the gate passes, `3` when it fails closed. |

## Reading the group breakdown

The report partitions the manifest's cases on each of the four `GroupKey`
values — `player`, `device`, `guitar`, `room` — and calls the public,
unmodified `computeRecognitionMetrics` on each partition. A case missing a
given group key (e.g. no `room` recorded) is **not** silently dropped from
that axis: it is counted under a distinct `"(unknown)"` bucket, with its own
case count. If every `"(unknown)"` bucket you see is empty, every case in
the manifest carries all four group keys.

Group breakdowns are for visibility, not a separate release decision: the
release gate (below) evaluates only the manifest-wide aggregate
(`overall.*` metric paths), not any one group's slice.

**`technique` (pick vs. finger) is not one of the four axes.** The
`GroupKey` enum this round reads from (`recognition_split.dart`) declares
only `player, device, guitar, room` — `RecognitionCase` carries no technique
field. Adding it is a later round's work, extending that enum and the
E14-R08 case model; this round's dashboard does not simulate it under a
different key.

## Reading the three event categories

Every scope (`overall`, and each group breakdown) reports three counts
beyond a single accuracy percentage — none of them folds into the accuracy
ratio itself:

- **`confidentWrong`** — accepted (user-visible) detections that are not
  correct. Exact: `acceptedAccuracy.denominator − acceptedAccuracy.numerator`
  (identical to `falseVisibleEventsPerMinute.eventCount`).
- **`rejected`** — detections the engine made but chose not to surface
  (abstained). Exact: `coverage.denominator − coverage.numerator`. A
  rejected detection is **not** a false positive: it is never counted in
  `acceptedAccuracy`'s denominator or in `falseVisibleEventsPerMinute`.
- **`uncertainCorrect`** — always `null`, with a fixed, non-empty
  `uncertainCorrectUnavailableReason`. Whether an abstained detection would
  have been *correct* if surfaced is not computable from
  `computeRecognitionMetrics`'s public output: the per-event correctness set
  and the bipartite matcher it depends on are private to
  `recognition_metrics.dart` (see `docs/LESSONS.md` L269 — copying that
  matcher here would create a second, potentially divergent implementation
  of the same measurement). `null` is the honest value; reporting `0` would
  claim every abstained detection was wrong, which is not measured.
  Computing this for real requires a later round to extend the E14-R08
  harness to expose per-event correctness.

## Reading the release gate

The gate is **fail-closed** (ADR 0511 D1): for every threshold entry —

- if the report's value for that metric path is missing or `null` (zero
  denominator / zero sample), the finding is `FAIL`, and the reason names
  the metric path. There is no "skip" or "no data, pass" outcome.
- otherwise the comparison direction comes from the metric's own
  `RecognitionMetricDefinition.higherIsBetter` in the report, never from the
  threshold file (D2). A threshold entry that tries to declare a direction
  (`higherIsBetter`, `direction`, `>=`, `<=`) is rejected with a typed
  `RecognitionGateConfigException` at parse time.
- the boundary belongs to the accepting side: `value >= threshold` when
  higher is better, `value <= threshold` otherwise. A value exactly on the
  threshold **passes** (D3).

The overall verdict passes only when every finding passes. An unrecognised
`schemaVersion` in the threshold file is a typed error, never a silent
fall-back to default thresholds (D6).

### Metric paths this gate can evaluate

All gate-evaluable metric paths are scoped `overall.<metric>` — this round's
gate only ever evaluates the manifest-wide aggregate, not a group slice.
`overall.acceptedAccuracy.value` and `overall.falseVisibleEventsPerMinute.value`
are event-kind-agnostic (computed over onset + strum + chord together, not
scoped to direction or chord alone) — see the excluded-lines table below for
what that means for two Ch14 Alpha rows.

## The shipped v1 thresholds, and what they leave out

`recognition_release_gate.json` (`thresholdsVersion: "ch14-alpha-v1"`) pins
ten Ch14 §7.2/§7.4 Alpha values to metric paths that exist in the E14-R08
report:

| Ch14 Alpha line | Metric path | Threshold |
|---|---|---:|
| Onset F1 @50 ms | `overall.onsetTolerance50Ms.f1` | 0.82 |
| End-to-end direction macro-F1 | `overall.directionF1.value` | 0.80 |
| Accepted direction accuracy* | `overall.acceptedAccuracy.value` | 0.90 |
| Coverage alongside accepted accuracy | `overall.coverage.value` | 0.70 |
| False visible arrow hard-negative* | `overall.falseVisibleEventsPerMinute.value` | 2 / min |
| Verdict latency p50 | `overall.latencyP50Ms.value` | 180 ms |
| Verdict latency p95 | `overall.latencyP95Ms.value` | 280 ms |
| Chord weighted accuracy | `overall.chordWeightedAccuracy.value` | 0.80 |
| Chord macro-F1 | `overall.chordMacroF1.value` | 0.70 |
| N.C./unknown F1 | `overall.chordNoChordF1.f1` | 0.88 |

\* Event-kind-agnostic stand-in — see below.

**Four Ch14 Alpha lines have no corresponding metric in the E14-R08 report
and are deliberately absent from v1** (ADR 0511 D8) — none of them is
replaced by a similarly named but differently scoped metric (that
substitution is exactly the `docs/LESSONS.md` L549 failure class):

- **Accepted direction accuracy** and **false visible arrow hard-negative**
  are, strictly, direction-scoped metrics. The report's `acceptedAccuracy`
  and `falseVisibleEventsPerMinute` are event-kind-agnostic (onset + strum +
  chord combined) — there is no direction-only variant in the E14-R08
  output. The table above still gates on them, at the Ch14 threshold, but
  labelled as the agnostic version (ADR 0511 R6) rather than silently
  presented as the direction-scoped number.
- **Weakest supported chord recall** — the report's `chordMacroF1` exposes
  per-label F1 (`perLabel`), not a per-label recall the dashboard can name
  as "weakest."
- **Confirmed chord accepted accuracy** — `acceptedAccuracy` is not scoped
  to chord events; there is no chord-only accepted-accuracy in the report.
- **Chord transition p50** — the report's `latencyP50Ms`/`latencyP95Ms`
  measure accepted-detection latency across all event kinds, not the time
  between confirmed chord transitions; no chord-transition-specific latency
  is computed anywhere in the E14-R08 harness.
- **False confident chord hard-negative** — same combined-metric problem as
  accepted direction accuracy above, but for chords: gating it on the
  already-used `falseVisibleEventsPerMinute` a second time under a
  chord-specific name would be exactly the metric/label mismatch this
  document exists to avoid.

Mechanising any of these requires extending the E14-R08 harness
(`recognition_metrics.dart`) with a genuinely scoped metric — out of this
round's allowed-files list.

## Changing the thresholds

The threshold file is a reviewed artefact, not a knob the code can loosen
(ADR 0511 D9): `test/features/live/evaluation/recognition_release_gate_test.dart`
pins the ten v1 values above as constants and compares the file's parsed
values against them — it never re-derives them from the live tree
(`docs/LESSONS.md` L613). Lowering a threshold requires editing both the
JSON file and that pinned test in the same, visible change.

## Current baseline vs. this gate

Against the legacy DSP baseline recorded in
`docs/eval/recognition-release-guard.md` (chord accuracy 67.1%, onset F1 @50
ms 67.4%, direction accuracy 80.7%), this gate returns `FAIL`. That is the
gate working as intended (ADR 0511 "Következmények"): it rejects the
current baseline, and the release decision remains a human one, unblocked
by any change to this dashboard.
