---
id: 015
topic: Strum direction (↓/↑) — the ML upgrade path beyond the v1 heuristic
tags: [strum, direction, crnn, tflite, litert, imu, dataset, augmentation]
sources:
  - https://arxiv.org/abs/2508.07973 (Joint Transcription of Guitar Strumming Directions + Chords, ISMIR 2025)
  - https://github.com/Klangio/KLANGIO-GST-MM-T (multimodal audio+wrist-IMU, ISMIR 2022 LBD)
  - https://archives.ismir.net/ismir2018/paper/000188.pdf (GuitarSet)
  - https://zenodo.org/records/7544110 (IDMT-SMT-Guitar)
  - https://arxiv.org/html/2408.13734v1 (Chirp Group Delay onset, fast-attack instruments)
  - https://developers.google.com/edge/litert (LiteRT)
researched: 2026-07-10 (4-agent Hermes sweep)
---

# Strum direction — beyond chunk 006's hand-tuned heuristic

**State of the art (ISMIR 2025, arXiv 2508.07973 — essentially our competing paper).**
A small **CRNN on log-mel** classifies audio-only direction at **F1-any 92.8 %,
down 85.5 %, up 79.0 %** — vs a plain spectral-flux baseline at 79.5 %. Our
current heuristic (chunk 006) is below that baseline on up-strums. Up-strum is
the intrinsic weak class in *every* published system (quieter, fewer strings,
reversed onset order with less energy).

## The recommended engine (v2)
- **Architecture:** log-mel spectrogram (128–229 mel bins, min 30 Hz, 16 kHz,
  2048-sample window / **160-sample hop = 10 ms frames**) → 3–4 small conv
  blocks (2 conv + pool each) → **stateful GRU/biGRU(128–256)** → 2-logit
  down/up head (optionally a joint onset-regression + chord head, as the paper).
- **Streaming latency <30 ms:** persist the GRU hidden state across hops → run
  inference *per 10 ms hop*, not per window. Keep the conv receptive field / 
  lookahead to a few frames. Runtime = **LiteRT** (TFLite successor) via
  **`tflite_flutter`** (raw interpreter — right for a custom per-hop loop;
  `tflite_audio` is fixed-window classification, wrong shape). Run inference in
  a SEPARATE isolate from the UI (as the DSP already is).
- **Model size:** few-hundred-K to low-single-MB quantized — comfortably
  real-time on mid-range Android.

## The key enabler — a directionally-labeled dataset (we have none)
No open dataset has clean per-strum down/up labels (GuitarSet + IDMT-SMT-Guitar
give onsets/chords only; the ISMIR-2025 set is unreleased). **Build it cheaply:**
- Record real strumming while wearing **ANY Wear OS watch / motion earbud**;
  the strum gesture is a ~2–8 Hz wrist motion, trivially captured at 200 Hz.
  Derive down/up from wrist accel, align to audio onsets → free supervision.
  (This is exactly how the ISMIR-2025 team labeled 94 h.)
- **Augment:** ±6-semitone pitch-shift (with chord-label transpose) gave
  **+14 % relative up-strum F1**. Add synthetic tab-rendered strums for bulk.
- Seed onsets/chords from GuitarSet + IDMT-SMT-Guitar subset 4.

## Sensor fusion — the honest verdict
- **Phone-on-body IMU CANNOT resolve direction.** Android caps motion sensors
  at 200 Hz (Android 12+); more importantly the phone on the body feels only
  symmetric body vibration, no directional gesture. (It *can* drive an
  accelerometer tuner — different feature.)
- **Worn IMU (wrist) DOES work** — one up/down of the accel signal per strum.
  Two uses: (1) training-time auto-labeling above; (2) an **opt-in inference
  fusion mode** for users with a paired Wear OS watch → hybrid up-strum
  **~88–92 %**. Audio-only stays the default. Earbud (head) IMU is useless.

## Onset detection — the cheap pure-Dart win (feeds direction)
Our whitened spectral flux is the weak link at **16th notes @ 120 bpm** (~8
onsets/s, ~125 ms apart). Upgrade, staying pure-Dart:
- **SuperFlux (Böck & Widmer):** log-mag mel + a **maximum filter across
  log-frequency bins** + small trajectory lag → suppresses vibrato/finger-noise
  false positives. ~F1 0.88–0.92 (IDMT/GuitarSet) vs ~0.79 plain flux. Real-time.
- **Chirp Group Delay (arXiv 2408.13734)** — matches SuperFlux at ~3× lower cost
  (3.2 vs 9.4 ms/file); pure-DSP option for fast-attack instruments.
- **Tuning:** hop ~5–10 ms, min-inter-onset ≤ ~50–60 ms, peak-pick on the
  max-filtered flux. Adopt the field-standard **±50 ms** eval window in property
  tests.

## Ranked recommendations (effort × impact)
1. **[decisive] Streaming TFLite CRNN** replacing the direction fusion. *high effort — the whole moat.*
2. **[unblocks #1] Worn-IMU auto-labeled dataset + pitch-shift augmentation.** *medium.*
3. **[cheap, now] SuperFlux onsets** (log-mel + freq max-filter, 5–10 ms hop, ±50 ms property gate). *low.*
4. **[feature eng.] Explicit inter-string onset-lag + attack-phase centroid trajectory** as CRNN input channels / sharper heuristic fallback. *medium.*
5. **[opt-in, later] Wear OS IMU fusion mode.** *high, subset only.*

**Pitfalls to hold:** up-strum is intrinsically low-recall — weight the loss
toward it and set product expectations; synthetic-only training gives good onset
F1 but POOR direction — real IMU-labeled data is mandatory. Final acceptance
stays the real-guitar APK test, never synthetic F1.

## AS BUILT round 135 (2026-07-12) — SuperFlux onsets (rec #3)
`lib/features/live/engine/dsp/superflux_onset_detector.dart` — standalone
`SuperFluxOnsetDetector` on the StrumAnalyzer framing (1024 win / 256 hop @
device rate): 64-band log-mel (`LogMelExtractor`, fMin 30 Hz) floored at
**−9.0 log-power** (kills noise-floor log-ratios), rectified difference vs a
**±1-band maximum-filtered reference lag=2 frames** back (~11.6 ms), adaptive
threshold **flux > 3.0 + 2.0 × median(0.4 s)**, ±2-frame local max, min-IOI
50 ms, **RMS silence gate** (DspConfig.silenceRms), plus BOTH chunk-005 guards
ported from the whitened-flux path: release hysteresis (≥3 frames below
threshold re-arms — one rake = one onset) and the attack-relative gate
(candidate ≥ 0.15 × 0.985-decayed flux peak — ring-out beating bumps can't
fire). Measured on the randomized gate (overlapping ring-out strums, 100–180
BPM 16ths, stagger 6–10 ms, 5 seeds): **recall 98–100 %, spurious 0–1.9 %**;
the peak gate was the decisive fix (before it: spurious up to 22 %). Vibrato
(±30 cent, 6 Hz, constant amplitude) produces ZERO onsets — the SuperFlux
signature win over plain flux. (Detector reports frame-start time, decision
lag = 2 frames ≈ 11.6 ms.)

## AS BUILT round 136 (2026-07-12) — SuperFlux IS the live onset trigger
`StrumAnalyzer` now delegates onset detection to `SuperFluxOnsetDetector`;
the whitened-flux machinery (whitening, flux, median threshold, hysteresis,
peak gate) was REMOVED from the analyzer (it all lives in the detector). The
chunk-006 classification stage (sub-band rise order + centroid fusion, r59
onset-relative baseline) is untouched; pending onsets are a QUEUE (at 200 BPM
16ths the next onset lands inside the ~70 ms classify window). Analyze inherits
the upgrade via LivePipeline. **A/B measured before the swap** (identical
randomized suite): whitened flux hallucinated **23 onsets on a 3 s
constant-amplitude vibrato** (SuperFlux: 1 — a REAL user-facing bug class:
sustained bends read as strums) and dropped 1–2 strums at 180–200 BPM 16ths
(SuperFlux 12/12 pre-tune). Integration retunes (same commit): **min-IOI
50 → 60 ms** (the old analyzer's value; a 40 ms lazy rake double-fired at 50)
and **threshold delta 3 → 20** (log-domain flux is amplitude-invariant: a real
attack rises ≥100 across bands, a late ring-out beating bump ≤10 — measured at
0.836 s into a single default strum — so 20 splits the populations; after the
retune the randomized gate reads **recall 100 %, spurious 0 % on 5 seeds**).
Honest cost: one extra 1024-pt FFT per hop (detector owns its log-mel);
200 BPM 16ths stays 11/12 (the confidence tier reports that limit honestly).

**r142 audit fix:** the silence-gate branch now ALSO advances the release
hysteresis and decays the flux-peak tracker — before the fix, a staccato stab
hard-cut to digital silence froze `_eligible=false` forever and a stale loud
peak could suppress a later soft strum (reproduced in test: stab → 1 s true
silence → 0.25× soft strum was DROPPED; now detected).

**r144 onset-TIME correction (measured):** the flux-peak frame STARTS a
constant **2.5 hops (14.2 ms) before the true attack** — invariant across
stagger 4–12 ms and level 1.0/0.3. `StrumEvent.timeSec` now reports
`(peakFrame + 2.5) × hop/sr` (the estimated attack), pinned at |bias| < 6 ms;
without it the LessonScorer's ±50 ms PERFECT window silently lost 14 ms of
late-side margin for uncalibrated users. The correction applies ONLY to the
reported time — classification and the Viterbi onset boost keep the
peak-frame reference (shifting them would slide the r59 baseline window into
the attack). Constant shifts cancel in TempoTracker/bar deltas.

**r145 follow-up (Analyze):** the Analyze timeline used its FEED position as
the strum timestamp — measured **85–165 ms late with ±40 ms jitter** (emit
cadence ~66 ms + classify delay ~70 ms + chunk quantisation), enough to shift
a strum half an eighth at 120 BPM in `Lessons.fromAnalyze` beat quantisation
and in shared cards. `LiveFrame` now carries `latestStrumTime` (the
r144-corrected attack instant on the engine's sample clock) and
`ClipAnalyzer._strumPass` stamps THAT; pinned at ±25 ms on a 4-strum clip.
Also improves `_bpmFromStrums` (median IOI on accurate times).

**r147 (the LIVE twin):** the Learn scorer received the frame-ARRIVAL lesson
time — the classify-delay constant is the calibration's job, but the emit
cadence adds **0–66 ms of jitter** a constant offset cannot absorb (up to
±33 ms on a ±50 ms PERFECT window). `LiveFrame.engineTimeSec` (emit instant,
same sample clock as `latestStrumTime`) lets `_onFrame` hand the scorer
`elapsed − (emit − attack)` — the jitter cancels exactly on the engine clock;
only transport (~ms) and the mic constant (calibration) remain. Guards:
lag ∈ (0, 0.5 s), clockless producers (−1, mocks) skip correction.
