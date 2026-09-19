# Chapter 14 — production gate checklist

- **Round:** `E14-R42` (Chapter 14, Kör 42 — the chapter's closing round),
  [ADR 0543](../adr/0543-ch14-production-gate-and-traceability-closure.md)
- **Measured on:** 2026-09-09, branch `claude/laptop-apk-debug-prompt-kys4oa`
- **Sources of every number below (this file is a VIEW, not a source):**
  - `evaluation/recognition/baseline_manifest.json` — the measured baseline
    (corpus `ml/data/klangio`, 82 recordings, 11 767 events,
    `corpusSha256=4880fac…`, app commit `5ceed22d`)
  - `evaluation/recognition/recognition_release_gate.json` — the thresholds
    (`thresholdsVersion: ch14-alpha-v1`, 10 rows)
  - `docs/sdd/14-chapter-14-recognition-ui-recovery.md` §7 — the product
    targets those thresholds implement

> **Verdict of this checklist as of the measurement date: NOT PASSING.**
> Two thresholds are measured and BELOW their bar; the remaining eight are
> not measured at all. Under [ADR 0511](../adr/0511-recognition-release-gate-and-single-source-report.md)
> a missing metric is a **FAIL**, never a neutral "no data" — so no
> recognition band may leave `RecognitionRolloutStage.off`
> ([ADR 0542](../adr/0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md) D1).

---

## 1. Strum band — SDD Ch14 §7.2 (Alpha gate)

| Metric | Threshold | Measured | Verdict | Owning workflow / producer |
|---|---:|---|---|---|
| Onset F1 @50 ms | ≥ 0,82 | **0,674** (`metricBlocks.onset.tolerance50000us.f1`) | **FAIL** | `ml-train.yml` (`sections="logo"` retrain) → `tool/recognition_evaluate.dart` → baseline manifest |
| End-to-end direction macro-F1 | ≥ 0,80 | *not measured* (`metricBlocks.direction.status = not-measured`) | **FAIL (fail-closed)** | `ml-train.yml` (`sections="threeway logo"`) |
| Accepted direction accuracy | ≥ 0,90 | *not measured* | **FAIL (fail-closed)** | `ml-train.yml` + the decision state machine's accepted/rejected split |
| Coverage alongside accepted accuracy | ≥ 0,70 | *not measured* | **FAIL (fail-closed)** | same as above — the pair must be reported together |
| False visible arrow on hard-negative audio | ≤ 2 / min | *not measured* | **FAIL (fail-closed)** | `evaluation/recognition/negative_taxonomy.json` corpus + `tool/recognition_evaluate.dart` |
| Verdict latency p50 | ≤ 180 ms | *not measured* (`metricBlocks.latency.status = not-measured`) | **FAIL (fail-closed)** | on-device run; `build-apk.yml` artifact + a real handset — NOT producible in CI |
| Verdict latency p95 | ≤ 280 ms | *not measured* | **FAIL (fail-closed)** | same as above |

**Beta/GA targets (§7.3)** are not tabulated per-row here on purpose: an
Alpha row that fails cannot have a meaningful Beta verdict. They become
relevant only once every row above reads PASS.

## 2. Chord band — SDD Ch14 §7.4 (Alpha gate)

| Metric | Threshold | Measured | Verdict | Owning workflow / producer |
|---|---:|---|---|---|
| Weighted accuracy | ≥ 0,80 | **0,671** (`metricBlocks.chord.metrics.accuracy`, 7 892/11 767 correct) | **FAIL** | `chord-train.yml` (Klangio pinned SHA + GuitarSet) |
| Macro-F1 | ≥ 0,70 | *not measured* — per-label precision/recall exist, the macro-F1 roll-up is not in the manifest | **FAIL (fail-closed)** | `chord-train.yml` → `computeRecognitionMetrics` |
| N.C./unknown F1 | ≥ 0,88 | *not measured* (`metricBlocks.noChord.status = not-measured`) | **FAIL (fail-closed)** | `chord-train.yml` + hard-negative corpus |
| Weakest supported chord recall | ≥ 0,55 | **0,000** — `C#-major` recall is 0,0 (precision 0,0 as well); next weakest `D-major` 0,417 | **FAIL** | `chord-train.yml`; the per-label block already exists in the manifest |
| Confirmed chord accepted accuracy | ≥ 0,88 | *not measured* — the provisional→confirmed stabilizer (E14-R12, ADR 0518) has no measured accepted-subset accuracy | **FAIL (fail-closed)** | `chord-train.yml` + the stabilizer's accepted split |
| Chord transition p50 | ≤ 350 ms | *not measured* | **FAIL (fail-closed)** | on-device run — NOT producible in CI |
| False confident chord on hard-negative audio | ≤ 2 / min | *not measured* | **FAIL (fail-closed)** | `negative_taxonomy.json` corpus |

**Measured context that matters for reading the chord rows:** the
always-predict-G-major baseline scores 0,188 on the same corpus, so 0,671 is
a real signal, not noise — it is simply 0,129 short of the gate. The
minor-chord subset scores 0,833 on 222 events; the weighted number is
dominated by the major classes.

## 3. Corpus prerequisite — SDD Ch14 §7.1

| Requirement | State | Note |
|---|---|---|
| 8 separate guitarists | **NOT MET** | the baseline is the Klangio corpus, not own recordings |
| 6 separate phone models | **NOT MET** | no phone-microphone diversity in the corpus at all |
| 4 guitars | **NOT MET** | — |
| pick and finger | **NOT MET** | not annotated in the baseline manifest |
| quiet / medium / loud | **NOT MET** | — |
| ≥ 4 rooms, several phone–guitar distances | **NOT MET** | — |
| 24 maj/min chords with balanced support | **PARTIAL** | the shipped `chord_crnn.bin` covers 25 classes (N.C. + 12 major + 12 minor); the measured corpus does not cover them evenly — `C#-major` has zero correct predictions |
| hard-negative audio | **MET (taxonomy)** | `evaluation/recognition/negative_taxonomy.json` (E14-R15, ADR 0521); the RATE against it is not measured |
| player/device/guitar grouped holdout | **MET (harness)** | grouped evaluation + leakage protection shipped (E14-R08, ADR 0509); the grouped RUN is not done |

**Consequence:** §7.1 is a precondition of the Beta gate, and it is not met.
No amount of green in §1–2 would substitute for it.

## 4. Human decision rows — not metrics

These never turn green by themselves. Each names who decides, what the input
is, and its state today.

| Decision | Who decides | Input it needs | State today |
|---|---|---|---|
| `adaptiveShellEnabled` production GA flip | user (product owner) | Chapter 12 Kör 28 GA-scope record + the accessibility/variant matrix evidence | **OPEN** — the flag resolves to `nonProd`; production stays off (ADR 0467 D8) |
| Strum band rollout step (`strumModelRolloutStage`) | user, on the §7.2 table | every §1 row PASS + a rollback rehearsal | **OPEN** — stays `off` (ADR 0542 D1) |
| Chord band rollout step (`chordModelRolloutStage`) | user, on the §7.4 table | every §2 row PASS + the §7.1 corpus | **OPEN** — stays `off` |
| Privacy review + threat model signature (Kör 41) | user | the shipped consent model, the event schema, the redaction property | **OPEN** — the mechanism is in place; the SIGNATURE is a human act |
| Beta cohort launch (Kör 41) | user | the signature above + a transport, which this wave does NOT ship | **OPEN** |
| Internal Alpha field study (Kör 40) | user + 8 guitarists | `lab-apk.yml` build, the protocol in `ch14-r40-field-study.md` | **NOT RUN** |
| Production rollout 1% → 5% → 20% → 50% → 100% | user | every row above, plus the stop-conditions in `ch14-recognition-rollout.md` §4 | **OPEN** |
| Final acceptance: the real-guitar APK test | user | a `build-apk.yml` artifact on a real handset with a real guitar | **OPEN** — this is the chapter's final acceptance predicate, and no synthetic green replaces it |

## 5. What is machine-checked today

| Fact | Where |
|---|---|
| The release gate is fail-closed (missing metric = FAIL) | `test/features/live/evaluation/**` (E14-R09, ADR 0511) |
| The recognition metric tree (onset P/R/F1 per tolerance, direction macro-F1, chord weighted/macro/N.C., coverage, ECE, Brier, per-group split) | `lib/features/live/domain/evaluation/recognition_metrics.dart` (E14-R08, ADR 0509) |
| Every recognition rollout gate resolves to `off` in every environment | `test/app/config/feature_flags_test.dart` (E14-R41, ADR 0542 D1) |
| Beta telemetry cannot send without all three gates | `test/core/telemetry/telemetry_consent_test.dart`, `test/privacy/beta_telemetry_egress_test.dart` |
| The telemetry payload never exceeds its allowlist | `test/property/telemetry_redaction_property_test.dart` (randomized, `PROPERTY_SEED`) |

## 6. How to re-measure

```bash
# strum training / calibration (x86 CI, TF wheel, Klangio pinned SHA)
gh workflow run ml-train.yml -f sections="logo calib"

# chord training / evaluation (Klangio + GuitarSet)
gh workflow run chord-train.yml

# full Flutter gate + APK (once, at the end of a session)
gh workflow run full-gate.yml --ref <branch>
gh workflow run build-apk.yml --ref <branch>
```

After a run, update `evaluation/recognition/baseline_manifest.json` (PKG-B
owns it) and only then this file — never the other way round.
