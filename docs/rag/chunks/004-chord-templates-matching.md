---
id: 004
topic: Chord recognition — 24 maj/min templates, cosine match, hysteresis, confidence
tags: [chord, template, cosine, matching, hysteresis, confidence, major, minor]
sources:
  - https://www.audiolabs-erlangen.de/resources/MIR/FMP/C5/C5S2_ChordRec_Templates.html
  - https://github.com/adamstark/Chord-Detector-and-Chromagram
---

# Chord matching

**Templates:** 24 binary chroma templates — root+quality:
maj = {0,4,7}, min = {0,3,7} semitone offsets, L2-normalized. (Validated in the
Python plan; port identically.)

**Score:** cosine similarity `score_c = template_c · chroma` (both unit-norm).
Best chord = argmax.

**Confidence** (0..1, drives the UI ramp) — combine two signals:
- `margin = (best − secondBest) / best` — how decisively this chord wins;
- `strength = best` — how chord-like the chroma is at all.
- `confidence = clamp(strength * (0.5 + 2*margin), 0, 1)` — start here, tune on
  real audio; a bare triad scores ~0.9+ strength, mush scores <0.5.

**Hysteresis (anti-flicker):** only switch the reported chord when the SAME new
chord wins for **≥3 consecutive smoothed frames** (~70 ms) OR wins once with
confidence ≥0.8. Keep reporting the previous chord (with decayed confidence)
otherwise. Without this the display flickers between relative maj/min (C↔Am
share 2 of 3 notes — the classic failure).

**Silence:** below the RMS gate report `chord = null` (UI shows "—"), never a
random template hit on noise.

**Known limits (v1):** 24 triads only — no 7ths/sus/dim; capo/transpose is a
UI-layer shift (pitch-class rotation), not a detector concern.
