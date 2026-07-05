---
id: 006
topic: Strum direction (↓/↑) — state of the art and our audio-only heuristic
tags: [strum, direction, downstroke, upstroke, sub-band, centroid, onset order]
sources:
  - https://arxiv.org/html/2508.07973v1 (Joint Transcription of Acoustic Guitar Strumming, 2025)
  - http://pejard.slu.edu.ph/vol.9/2019.10.26.pdf (CNN strum classification, 91%)
---

# Strum direction — THE differentiator, and the honest state of the art

**What the literature says (2025):** the best published system (arXiv
2508.07973) classifies direction with an **accelerometer on the strumming
hand** (+CRNN: F1 down 90.0 / up 88.7). Their AUDIO-only path only detects
onsets; direction from audio alone is **not a solved problem**. A 2019 CNN
audio-only study reports ~91% on hand-segmented single strums (lab conditions).
Down-strums are consistently easier than up-strums for every method.

**Our v1 heuristic (audio-only, on-device):** two independent cues per onset,
computed on the fast pipeline (1024/256) in a ±90 ms window around the onset:

1. **Sub-band rise order.** Envelopes of low band (<250 Hz — E2/A2 strings) vs
   high band (>1500 Hz — B3/E4 + pick brightness). First-rise time = first
   frame the band env crosses 50% of its in-window peak. Bass rises first →
   DOWN; treble first → UP. Gap <1 frame (~6 ms) → ambiguous.
2. **Spectral-centroid slope** over the first ~60 ms after onset: centroid
   rising (dark→bright as high strings join) → DOWN; falling → UP.

**Fusion → confidence:** both agree → high (0.8–0.95, scaled by margin);
disagree or one ambiguous → the stronger cue wins with mid (0.45–0.7); both
ambiguous → direction=last direction alternated? NO — report `unknown` and let
the UI show the low tier. Never fake certainty.

**Expectations to encode in tests + UI:** up-strum accuracy WILL trail
down-strum (fewer strings, softer attack, treble-led is noisier). This is why
confidence is a first-class UI signal (shape+colour), not decoration.

**v2 upgrade path:** small CRNN/TFLite on user-recorded labeled clips.
