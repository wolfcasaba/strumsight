# Chapter 14 — recognition rollout ladder and one-switch rollback

- **Rounds:** `E14-R24` (strum release gate + controlled rollout) and
  `E14-R33` (chord release gate + rollout), documentation half; the flag
  surface itself is [ADR 0542](../adr/0542-opt-in-beta-telemetry-consent-and-recognition-rollout-flags.md)
- **Written:** 2026-09-09, PKG-D
- **State: nothing is rolled out.** Both bands sit at
  `RecognitionRolloutStage.off` in every environment, and the measured
  baseline does not support anything else — see
  [`ch14-production-gate.md`](ch14-production-gate.md).

---

## 1. The ladder

`RecognitionRolloutStage` (`lib/app/config/recognition_rollout_stage.dart`)
is a closed, ordered enum. A percentage or a free string would let a build
claim a level nobody reviewed.

| Stage | Runs inference | User-visible | Threshold bar | What it means |
|---|---|---|---|---|
| `off` | no | no | — | the band does not run at all. **The default of every environment.** |
| `shadow` | yes | **no** | none (it is how the bar gets measured) | runs alongside the shipped path; output may reach the Lab panel and the diagnostics report ONLY — never a `LiveFrame`, never a score, never a pixel |
| `alpha` | yes | yes | SDD Ch14 §7.2 / §7.4 | visible in builds the team controls (`development` / `lab`) |
| `beta` | yes | yes | SDD Ch14 §7.3 / §7.5 | visible for testers who explicitly joined |
| `ga` | yes | yes | §7.3 / §7.5 sustained | visible for everyone the build reaches |

`shadow.isUserVisible == false` is the invariant the whole shadow mode rests
on, and it is machine-pinned in `test/app/config/feature_flags_test.dart`.

## 2. Two switches per band, ANDed asymmetrically

A shadow run happens only when **both** hold:

| Band | Rollout stage | Master switch |
|---|---|---|
| Strum | `strumModelRolloutStage` | `recognitionShadowModeEnabled` |
| Chord | `chordModelRolloutStage` | `recognitionChordShadowModeEnabled` |

Either one alone turns the path **off**; neither alone turns it **on**. The
stage is a reviewed release step recorded in this document; the boolean is
the incident switch an on-call operator reaches for without having to reason
about the ladder. This is the same asymmetry as the Community master gate
(ADR 0395) and the emergency flag source (ADR 0446 D1).

## 3. One-switch rollbacks

| What went wrong | The single switch | Effect |
|---|---|---|
| Shadow work is costing battery / memory on real devices | `recognitionShadowModeEnabled` (or the chord twin) → `false` | zero extra inference; the shipped path is untouched |
| A preprocessing / device-adaptation regression in the field | `recognitionPreprocessingEnabled` → `false` | the shipped preprocessing is restored **without a new model asset and without an app release** |
| Beta telemetry must stop | `betaTelemetryEnabled` → `false` | the Privacy Center card stops offering the switch and the upload gate closes, regardless of any stored consent |
| A user withdraws consent | the Privacy Center switch | takes effect on the next gate read — no restart — and the rotating pseudonym is **erased**, not parked |
| The whole band must go | the stage → `off` | the band stops running entirely |

**What is NOT a one-switch rollback:** swapping a model asset. The
`assets/ml/model_manifest.json` binaries ship inside the APK, so replacing
one is an app release. The legacy path staying available for one release
(SDD Ch14 Kör 24/Kör 33) is what makes a stage step-down meaningful — the
NNLS-chroma chord path and the shipped strum weights remain the behaviour a
step-down returns to.

## 4. Production rollout steps and stop-conditions

These are **human decisions**, not switches that flip themselves. Each step
requires the previous one to have run its observation window clean.

| Step | Observation window | Stop-condition — any one of these halts and steps back |
|---|---|---|
| 1 % | 48 h | any P0/P1 finding; crash rate above the shipped baseline; a false-confident report from a real user |
| 5 % | 72 h | the above, plus a measured regression on any §7.2/§7.4 row |
| 20 % | 7 days | the above, plus a subgroup regression (player / device / guitar group) |
| 50 % | 7 days | the above, plus support volume attributable to recognition |
| 100 % | — | GA is recorded in `docs/release/ga-record.md`, with the flag profile and the rollback target |

**Precondition for step 1:** every row of
[`ch14-production-gate.md`](ch14-production-gate.md) §1–3 PASS, plus a
rehearsed rollback. Today none of them does.

## 5. Model card requirements

A band may not step above `shadow` without a model card that states, at
minimum:

- the supported vocabulary — for the chord band, the **25 classes** of
  `assets/ml/model_manifest.json` (`N.C.` + 12 major + 12 minor). Anything
  outside it is out of scope, and the UI must not imply otherwise;
- the input contract (100×144 CQT for the chord CRNN; 15×128 log-mel for the
  strum CRNN variants);
- the measured numbers WITH their corpus and holdout, never a number without
  its definition (ADR 0509);
- the known limitations, named: no phone-microphone diversity in the
  measured corpus; `C#-major` recall measured at 0,0; calibration fitted
  in-sample (`live_crnn_classifier.dart::calibrate`) and therefore **not** a
  validated confidence.

The model card is PKG-B's deliverable (`ml/**`, `docs/eval/**`); this section
is the requirement it must satisfy before a stage step.
