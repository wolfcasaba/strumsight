# Recognition annotation contract and two-annotator agreement

The recognition annotation contract ([ADR 0359](../adr/0359-recognition-annotation-contract-and-agreement.md))
gives onset/strum/chord annotation the same versioned, validated, and
visually-traceable shape as the Audio Analysis evaluation manifest
([ADR 0249](../adr/0249-analysis-evaluation-dataset-governance.md)):
`evaluation/recognition/annotation_schema.json` is the contract,
`RecognitionAnnotationParser` (`lib/features/live/data/evaluation/`)
is the typed-failure validator, and `AnnotationAgreementCalculator`
(`lib/features/live/domain/evaluation/`) turns two independent annotators'
annotations of the same clip into a machine-readable agreement report.

The graphical annotator (waveform, spectrogram, draggable onset, undo/redo)
is **not** part of this round — see the E14-R07 round brief §0.0 and ADR
0359 D7. Writing an annotation today means hand-editing
`evaluation/recognition/fixtures/annotation_pair.json` (or a copy of it)
and running the CLI below.

## What lives here

- `evaluation/recognition/annotation_schema.json` — the JSON Schema
  (draft-07) contract, enforced by hand in `RecognitionAnnotationParser`
  (no schema-library dependency, matching ADR 0354 D8's precedent).
- `evaluation/recognition/fixtures/annotation_pair.json` — the CI fixture:
  two annotators' events for the same imagined clip.
- `lib/features/live/domain/evaluation/recognition_annotation.dart` — the
  Flutter- and `dart:io`-independent model (`AnnotationEvent`,
  `AnnotationChordSegment`, `RecognitionAnnotation`,
  `RecognitionAnnotationPair`) plus `AnnotationAgreementCalculator` and
  `AgreementReport`.
- `lib/features/live/data/evaluation/recognition_annotation_parser.dart` —
  `RecognitionAnnotationParser`, the typed-failure JSON parser and
  structural validator.
- `tool/recognition_annotate.dart` — the CLI: `dart run
  tool/recognition_annotate.dart [--pair <path>] [--tolerance-ms <ms>]`.

## The provenance rule (ADR 0359 D2)

Every annotated event and chord segment carries a required `provenance`
field: `auto | human | reviewed`. A missing `provenance` is a typed parse
failure — never `null`, never defaulted to `human`. The parser never
promotes an `auto` value to `human` or `reviewed` on its own; that
promotion is a human act (re-annotating), not a side effect of reading the
file. An automatic label is therefore never mistaken for ground truth
downstream (ADR 0249, and the E14-R01 release guard's "unvalidated claim
retracted" rule).

## Overlap is a typed failure, not a silent fix (ADR 0359 D3)

- **Events** (point-in-time onset/strum annotations): two events of the
  same `type` at the exact same `timeMs` are rejected. Events of different
  types at the same instant are fine — they are different lanes.
- **Chord segments** (real intervals): two segments whose
  `[startMs, endMs)` ranges intersect are rejected; segments that merely
  touch at a boundary (one's `endMs` equals the other's `startMs`) do not
  overlap.

Either failure carries **both** conflicting indices
(`RecognitionAnnotationParseException.conflictingIndices`) — the parser
never trims, merges, or reorders around the conflict.

## Agreement is a measured number, with a caller-supplied tolerance (ADR 0359 D4)

`AnnotationAgreementCalculator(toleranceMs: 50)` (50 ms is the documented
default, not a baked-in constant) pairs each annotator's events — and,
separately, each annotator's chord segments — with the other's via the
same deterministic maximum-cardinality matching `EvaluationRunner` uses for
Audio Analysis (Kuhn's algorithm; the pattern is copied, not imported, per
ADR 0359 D6). The pairing boundary is **inclusive**: a gap exactly equal to
`toleranceMs` still pairs, a strictly larger gap does not.

The report distinguishes two different quantities that must not be
confused:

- `matchedEventRatio` — matched pairs divided by the **larger** annotator's
  event count. On the CI fixture: 8 matched out of 10 events each ⇒ `0.8`.
- `directionAgreement` — of the matched pairs, how many agree on strum
  direction, divided by the **matched pair count** (not the raw event
  count). On the CI fixture: 7 of the 8 matched pairs agree ⇒ `0.875`.

`directionAgreement` and `chordAgreement` are `null` — never `0` — when
there is nothing paired to divide by.

## Determinism (ADR 0359 D5)

`AgreementReport.toJson()` renders keys in a fixed, alphabetical order;
`toDeterministicJson()` never reads the clock. The same annotation pair and
tolerance always produce byte-identical report JSON, so it can be diffed or
pasted into a document as evidence.

## Running the CLI

```bash
dart run tool/recognition_annotate.dart
dart run tool/recognition_annotate.dart --pair path/to/pair.json --tolerance-ms 30
```

Parse failures print to stderr with a non-zero exit code; a successful run
prints the deterministic `AgreementReport` JSON to stdout and nothing else.
