# ADR 0581 — Shape-informed string-arrival direction cue, fused behind the classifier seam

- Status: accepted (2026-09-15, round strum-strings)
- Numbering: 0581 deliberately skips 0550–0580, which the unmerged `claude/e18-r06-verify-followup` branch occupies.
- Supersedes nothing; complements ADR 0549 (no-strum gate) and ADR 0512 (direction abstention).

## Context

E18 closed the model side of ↓/↑ direction: on the CRNN's own log-mel input a linear reader reaches ~0.66, the 16-band ceiling is ~0.73, and on unseen players the shipped live model sits at 0.61 (Klangio LOGO) and **0.39 macro-F1 on GuitarSet** (ADR 0550/0553). E18 also measured that a sweep spans a median 22 ms across the strings and concluded "direction reads off spectral balance, not string ordering" — a statement about what a *learned* model extracts from a 10 ms log-mel, not about the physics.

The physics is the strongest cue there is: a down-stroke excites low E first and high E last, ~4–5 ms per string; an up-stroke the reverse. Resolving it needs (a) knowing which frequency lives on which string — i.e. the played **voicing** — and (b) a per-string envelope with ~1 ms time resolution. The app's guided modes (Learn, Practice, Song Trainer) *display* the shape, so (a) is known there.

## Decision

**D1 — The cue.** `StringArrivalCue` (`lib/features/live/engine/dsp/direction/string_arrival_cue.dart`): for every string of the voicing, the partials (fundamental + up to 6 harmonics, 150–4000 Hz) that no other string shares within the analysis bandwidth are tracked by a **centred Hann-Goertzel envelope** (2048-sample window ≈ 46 ms, 64-sample hop ≈ 1.45 ms). Pre-onset baseline (earliest quarter of a 40 ms pre-window) is subtracted so a ringing previous strum does not count; partials of one string are summed (each normalised to its own peak, SNR-weighted) **before** the 50 %-rise crossing. The direction is the sign of Kendall's tau between string index and arrival time; confidence = 0.5 + 0.45·|tau|·min(1, span/8 ms)·min(1, (strings−1)/4).

**D2 — Speak threshold.** The cue reports a direction only at confidence ≥ 0.65. Measured ladder (GuitarSet, 3035 hexaphonic-truth clean sweeps, exact voicings): ≥ 0.80 → 97.7 % (n = 218); 0.65–0.80 → 85.6 % (n = 871); < 0.65 → 60.8 % (n = 426). The bottom rung is a coin; it stays silent.

**D3 — Fusion rule.** `ShapeInformedStrumClassifier` wraps the activated classifier: **if the cue speaks, its verdict wins; otherwise the inner verdict stands; an inner no-strum suppression is always honoured.** Measured on the 1996 GuitarSet sweeps the live path heard (`docs/eval/string-arrival-fusion-2026-09-15.md`): CRNN alone 46.4 % → fused 62.3 %; on the cue's high tier CRNN 56.5 % vs cue 97.7 %; up-class 60.7 → 68.7 %; both player groups gain (48.0 → 59.1, 45.1 → 64.9). Every intermediate gate (cue only at ≥ 0.80; cue when CRNN margin < 0.3) lost coverage without gaining accuracy, so the rule is the simplest one. The cue verdict carries no pDown/pUp, so ADR 0512's margin rule does not apply to it (the cue already abstained below its ladder).

**D4 — Arming.** The voicing comes from `ChordShapes.forLabel(expectedChord)` and is set **only while the decoder currently shows that same chord**. A wrong voicing drags the cue to chance (Klangio with guessed open-position shapes: 52–55 % on covered, labelled or SuperFlux-detected onsets alike), so a learner playing something else is never judged against a shape they are not holding. The free Live mirror sets no expected chord → the wrapper is a bit-identical pass-through.

**D5 — Live truncation.** The verdict instant leaves ~78 ms of post-attack audio; the live cue runs with `postSec = 0.075`. Validated at that truncation (12-file GuitarSet probe): 82.5 % on 27 % coverage, high tier 93.5 %.

## Refuted in the same round (do not repeat)

- **Per-string log-energy slope** as a second channel ("first-struck strings ring louder"): 55–57 % = chance on GuitarSet.
- **Ring-based voicing estimation** (pick the chord-tone fret per string from the 40–230 ms ring by Goertzel score): 45 % per-string pitch accuracy; the cue fed with it falls to ~55 %. Shared harmonics between chord tones defeat a per-string argmax; a joint (NNLS-style) assignment was not tried.
- **Short (4-cycle) Goertzel windows**: the Hann main lobe (±f/2) lets neighbouring partials leak in and compressed a 60 ms synthetic stagger to 14 ms. The uniqueness separation must be derived from the window (2.1·sr/N).
- **Klangio as a bench for this cue**: the corpus has chord labels but no voicings; every guessed-shape result is chance-level and says nothing about the cue.

## Consequences

- Guided modes get a direction verdict that is right ~88 % of the time on ~36 % of strokes and ~98 % on ~7 %, on top of the CRNN elsewhere. Rhythm scoring — where a wrong call costs the learner (ADR 0549 D2) — benefits most.
- Coverage is the lever now: 34 % of GuitarSet's clean sweeps never reach a verdict because the no-strum gate suppresses them (upstrokes hardest). Letting a high-tier cue rescue a suppressed onset is **unmeasured** and therefore not done.
- Cost: ~2 M MAC per strum, inline on the DSP isolate; negligible next to the CRNN forward pass.
- Owner's real-guitar APK test remains the acceptance predicate; the cue's numbers are GuitarSet (studio room mic, 6 players), not phone-mic learners.
