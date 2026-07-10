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

**⚠ ROUND 59 — onset-relative baseline (the ring-out fix).** Cue 1 must be
computed on the sub-band envelopes with the **pre-onset baseline subtracted**:
the mean low/high band energy over the ~5 frames BEFORE the onset is subtracted
from the post-onset window before `_firstRise`. WHY: during fast strumming the
*previous* strum is still ringing, so an ABSOLUTE band envelope is already above
its own 50%-rise line at frame 0 and the rise-order cue collapses. MEASURED (synth,
alternating strums): direction fell to 5/8 @120 BPM and 4/7 @200 BPM 16ths;
baseline subtraction restored **8/8 for 100–160 BPM 16ths** (the realistic
hand-strum ceiling) with zero regression on isolated strums (baseline ≈ 0 there).
Randomized property gate: overlapping strums at 90–160 BPM hold ≥0.72 direction
accuracy across seeds (measured spread ≈0.77–0.86).

**⚠ Honest limit:** 200 BPM 16ths (~75 ms apart) still degrades — the next
strum bleeds into the ~70 ms classify window. Attack-anchoring / hard window
caps were tried and REGRESSED the common tempos (the cue needs the full attack
window), so the extreme case is left to the confidence tier rather than faked.

**⚠ ROUND 60 — band-redesign hypothesis REFUTED (measured, don't repeat).**
Intuition said the high band (≥1000 Hz) misses treble-string FUNDAMENTALS
(B3 247 / E4 330 Hz sit in the 200–1000 Hz gap) so up-strums are under-served.
A sweep of 8 band configs (240 overlapping-strum trials each, fixed seed) proved
the opposite: the **current (bass ≤200, treble ≥1000, no cap) is the BEST at
87.9%**; every treble-fundamental widening scored WORSE (77–82%). Reason: a
treble band reaching down to ~240 Hz is polluted by the BASS strings' upper
harmonics (E2's 3rd ≈ 246, A2's 2nd ≈ 220), which arrive *with* the bass strings
on a DOWN-strum → the treble band rises early on down-strums too, blurring the
cue. The ≥1000 Hz band works precisely because bass harmonics are weak up there
and pick brightness genuinely distinguishes. **Conclusion: the audio-only
heuristic is at ~88% aggregate — near the trained-CRNN ceiling. Further gains
need the ML path (chunk 015), not band tuning.** Keep the current bands.

**Expectations to encode in tests + UI:** up-strum accuracy WILL trail
down-strum (fewer strings, softer attack, treble-led is noisier). This is why
confidence is a first-class UI signal (shape+colour), not decoration.

**v2 upgrade path:** small CRNN/TFLite on user-recorded labeled clips.
