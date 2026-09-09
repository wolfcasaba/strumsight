---
id: 023
topic: Quality-aware input preprocessing and device adaptation on the Live path
tags: [live, dsp, preprocessing, gain, device-profile, signal-quality, agc]
sources:
  - docs/adr/0552-quality-aware-preprocessing-and-live-calibration-wiring.md
  - docs/adr/0507 (Live signal quality) · docs/adr/0224 §4 (measurement boundary)
  - docs/rounds/epic-14-completion-plan.md §2 R31
  - lib/features/live/engine/dsp/quality_aware_preprocessor.dart
built: 2026-09-09 (E14-R31)
---

# Input preprocessing — AS BUILT (mechanism only, UNMEASURED constants)

E14-R31 ships a **mechanism**, not a tuning. `QualityAwarePreprocessor` sits
in `LivePipeline.addChunk`, consumes the `SignalQualitySnapshot` the
already-shipped `LiveSignalQualityAnalyzer` produced from the **raw** chunk,
and applies at most ONE transform: a bounded, slew-limited broadband gain.

**It is off in every shipped build** (`recognitionPreprocessingEnabled`,
default `false`, ADR 0542). Off means `process` returns the caller's own list
instance — identity, not equality — so the DSP path cannot observe that the
stage exists.

## What it may do, per quality state

| `SignalQualityState` | Action |
| --- | --- |
| `tooQuiet`, `tooLoud` | level-normalise towards `targetRmsDbfs` (needs a measured `rmsDbfs`; without one, device offset only) |
| `clipping` | **HOLD** the current gain — never boost, never cut |
| `good`, `tooNoisy`, `speechLike`, `unstable`, `unknown` | device-profile offset only (0 dB on the shipped identity profile) |

The switch is exhaustive with no `default` arm: a new state must be given its
own answer.

## The constants — every one of them UNMEASURED

The 5+ phone A/B the plan (§2 R31) calls for is human + hardware work; none of
these numbers is fitted. They are **safety envelopes**. A measurement may
NARROW them; nothing may widen them without one.

| Constant | Value | Where it comes from |
| --- | ---: | --- |
| `defaultTargetRmsDbfs` | −21 dBFS | midpoint of the shipped usable window: `LiveQualityThresholds.standard.quietRmsDbfs = −40` (RMS) and `.loudPeakDbfs = −2` (peak). 19 dB above the quiet gate; at a ~12 dB guitar crest factor still ~7 dB of peak below the loud gate. NOT read from `LiveQualityThresholds` at compile time — this stage must never become a back door that retunes the quality gates. |
| `defaultMaxBoostDb` | +12 dB | 4× amplitude. Past it the device's own noise floor rises as fast as the guitar. |
| `defaultMaxCutDb` | 12 dB | symmetric with the boost bound. |
| `defaultMaxGainStepDb` | 1.5 dB / chunk | a gain that jumped between chunks would put a step at the chunk boundary, and a step is exactly what the spectral-flux onset detector is built to find (phantom strum). At a ~23 ms mic chunk it still traverses the full ±12 dB envelope in under 200 ms. |
| `defaultPeakHeadroomDb` | 1 dB | the stage must not CREATE clipping while fixing a quiet signal. |
| `DeviceAudioProfile.maxInputGainOffsetDb` | ±12 dB | one shared budget with the level correction. |

`LivePreprocessingConfig.version = 'live-preprocessing-v1'` is bumped when the
MECHANISM changes, so a recorded measurement can name the stage that produced
it. It is not a tuning version.

## Invariants that are structural, not conventions

1. **Off ⇒ bit-identical.** The same list instance comes back.
2. **The analyzer always measures the RAW input.** Measuring the corrected
   signal would close a loop and make the correction chase itself.
3. **The sample COUNT never changes.** The pipeline's emission clock counts
   raw samples, so frame cadence and `engineTimeSec` are independent of this
   stage — preprocessing cannot shift a frame in time.
4. **One scalar per chunk.** No filtering, no resampling, no time warping —
   so with nothing clamped the transform is exactly invertible by `−gain`.
5. **The ±1.0 safety clamp is COUNTED** (`preprocessingClampedSampleCount`).
   A non-zero value means the boost bound and the peak headroom disagreed
   with reality, and someone must look. It is never a silent loss.
6. **A `null` metric is never replaced by a plausible default.** A level
   state with no measured RMS yields no level correction (ADR 0271 §1).

## Device profile

`DeviceAudioProfile` (`domain/recognition/`) is a purely technical
audio-route description — `profileId`, `inputGainOffsetDb`, `noiseFloorDbfs?`
— never a person, a room, a skill or a location (ADR 0224 §4 boundary). The
shipped value is `DeviceAudioProfile.identity()`: 0 dB and `null` noise floor,
i.e. "no correction is KNOWN", not "no correction is needed".

The intended producer is the audio-setup wizard (E14-R14); E14-R31 ships the
consumer seam only. `measured()` throws rather than clamps on NaN, an empty
id, an offset past ±12 dB, or a noise floor above 0 dBFS: a buggy wizard must
fail loudly instead of pushing the bug into the DSP path where it looks like
a detection regression.

## What is NOT measured

- Whether −21 dBFS, ±12 dB and 1.5 dB/chunk are the right numbers — needs the
  5+ phone A/B.
- AGC detection on a real device — this round does not attempt it.
- Whether preprocessing improves recognition at all. That is why the flag is
  `false`; the final acceptance predicate stays the user's real-guitar APK
  test.
