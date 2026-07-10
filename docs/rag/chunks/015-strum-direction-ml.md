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
