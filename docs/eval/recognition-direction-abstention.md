# Direction-abstention threshold — source, coverage and the missing measurement

- **Kör:** E14-R10 (ADR 0512) — this document is `docs/eval/…` per the round's
  §5.5/D5 requirement: record the shipped threshold's provenance and name the
  measurement that is NOT in this tree yet, rather than staying silent about it.

## (a) The shipped `0.05` threshold's source

`StrumPrediction.uncertainMarginThreshold` (`lib/features/live/domain/recognition/strum_prediction.dart`)
is **`0.05`**, rejection-side inclusive (`margin <= 0.05` → `uncertain`). This
value was set by ADR 0505 D4 (E14-R04, the contract round) as a **shipped
default**, explicitly not a hand-tuned DSP/ML constant — ADR 0505 D4 says a
later, measured calibration round may override it with its own ADR. This
round (E14-R10) wires the CRNN's `pDown`/`pUp` up to that already-decided
threshold; it does not choose or retune it (AGENTS.md §9 forbids tuning a
shipping DSP/ML constant without a measured A/B and an ADR).

## (b) The coverage/accuracy pair — NOT MEASURED, and why

The question "at `0.05`, what fraction of CRNN strums abstain, and what is
the direction accuracy on the ones that don't?" **cannot be answered from
this tree today.** The measured gap:

- `evaluation/recognition/baseline_manifest.json` → `direction.status`:
  `"not-measured"` — the 82-recording klangio corpus's `.strums` files carry
  pluck (onset) ground truth only, no up/down direction label.
- The same manifest's `calibration.status`: `"not-measured"` —
  `notMeasuredReason`: *"No confidence-score ground truth exists for this
  corpus, and it does not meet the 30-per-bin / 300-total minimum ADR 0249
  §Döntés 4 requires before a calibration table may be fit."*
- The only direction-accuracy number in the repo — **80.7 %** — is a
  DIFFERENT measurement: the live 3-class CRNN's held-out eval fold
  (`docs/rag/chunks/018-strum-ml-pipeline.md`, `noStrumThreshold` doc comment
  in `live_crnn_classifier.dart`). It reports accuracy on that fold's
  strums, not a coverage/accuracy pair AT the `0.05` margin threshold — no
  bin-by-bin margin sweep against that fold exists in this tree.

There is no bin-enkénti (per-margin-bin) coverage table anywhere in this
repository. Reporting a coverage/accuracy number here without one would be
exactly the "kerek szám indoklás nélkül" ADR 0512 D5 forbids.

## (c) The measurement a later, separate calibration round would run

A held-out fold sweep over `ml/honest_eval.py` against the live 3-class
model's eval fold (the same fold `noStrumThreshold` was fit on), binning
predictions by `|pDown − pUp|` and reporting per-bin coverage (fraction not
abstained) and direction accuracy on the retained bins. This needs the ADR
0249 §D4 minimum (≥30 samples per bin, ≥300 total) before any bin's number is
trustworthy — that is a measured, separate round's job, not this hotfix's.

## (d) `calibrate()`'s floor and today's user-facing confidence threshold

`LiveCrnnStrumClassifier.calibrate()`'s knot table's lowest knot is
`(0.50, 0.55)` — no raw softmax value, however close to the 0.5 decision
boundary, calibrates BELOW `0.55`. `ConfidenceThresholdNotifier.defaultValue`
(`lib/features/settings/providers/confidence_threshold_provider.dart`) is
`0.45`. Since every CRNN-path confidence is `>= 0.55 > 0.45`, the
`confidenceThresholdProvider`'s default value rejects **zero** CRNN strums
today — and, per the round's own measurement (§0.0/5 of
`docs/rounds/e14-r10-direction-abstention-hotfix.md`), the recognition path
does not even read that provider yet. Wiring the user threshold into the
CRNN path is explicitly out of this round's scope — a separate round's job.
