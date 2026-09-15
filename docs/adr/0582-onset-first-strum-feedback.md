# ADR 0582 — The strum event is published in two stages: the onset rings the strings, the verdict colours them

- Status: accepted (2026-09-15, round strum-strings)
- Numbering: continues 0581; 0550–0580 stay reserved for the unmerged `claude/e18-r06-verify-followup` branch.
- Related: ADR 0512 (direction abstention / margin gate), ADR 0549 (the no-strum gate at 0.85), ADR 0581 (shape-informed string-arrival cue), ADR 0274 (motion driven by the audio clock, §5.1 reduced motion), chunk 010 (latency budget), chunk 016b (game feel).

## Context

Until this round a strum reached the UI as ONE event: `LiveFrame.strumSeq` bumped
when `StrumAnalyzer` had collected `_classifyAfterFrames = 12` hops of post-onset
evidence (256-sample hop at 44.1 kHz → **69.7 ms** of audio after the onset frame),
and the frame carrying it was only emitted on the next ~15 Hz cadence tick
(0–66 ms more). So the app said *nothing at all* for the whole classification
window, then said everything at once. On top of that, the classifier can decide the
onset was not a strum (ADR 0549: at the shipped 0.85 gate the measured true-strum
retention on GuitarSet is 0.649) — in which case the UI stayed silent for a hit the
learner definitely felt in their hands.

But the app knows a hit happened much earlier than it knows its direction. SuperFlux
confirms an onset `_postFrames = 2` hops after the onset frame, and `StrumAnalyzer`
already computes the r144-corrected attack instant at that moment. That is
**10 hops = 58.1 ms** of information sitting unused before the verdict exists.

The two facts together decide the shape of the feature: the feedback that has to be
immediate (*something happened*) and the feedback that has to be correct
(*which way*) are separated by ~58 ms and must therefore be two published signals,
not one.

## Decision

### D1 — Two counters on the frame contract, not one

`LiveFrame` carries `onsetSeq` (default 0) and `latestOnsetTime` (default −1) beside
the existing `strumSeq` and `latestStrumTime`. `LivePipeline` bumps `onsetSeq` on the
frame `StrumAnalyzer.onsetJustFired` is true, and publishes
`StrumAnalyzer.lastOnsetTimeSec` — the same r144-corrected attack instant, on the
same engine sample clock, that a later `StrumEvent` reports for the same stroke.

**A suppressed (no-strum) onset still bumps `onsetSeq` and never bumps `strumSeq`.**
The hit was heard, so the strings react; only the arrow waits for a verdict that in
that case never comes. This keeps ADR 0549's suppression honest (no arrow, no
scoring, no streak) while removing its side effect of a dead screen.

### D2 — Emit immediately on the confirming chunk

`LivePipeline.addChunk` now emits a frame as soon as a chunk confirms an onset OR a
strum, in addition to the unchanged idle ~15 Hz cadence. The 0–66 ms cadence jitter
is removed from *both* signals; the measured emit-cadence contribution for onset and
direction is now **0 ms** (chunk 010, D4 probe). Everything else on the frame
(level, chord, beat grid) keeps the cadence it had.

### D3 — The visual contract: ONE stroke, upgraded in place

The strings band starts an **undirected** stroke on an `onsetSeq` rise (all six
strings ring together, neutral colour, no pick drawn). A `strumSeq` rise with a
non-null direction **resolves that same stroke in place** —
`SsStrumStroke.resolveDirection` moves the pick and tints the already-excited
strings without restarting the ring-out — as long as the stroke started at most
`SsStrumStrings.directionGraceSec = 0.25 s` ago. Past the grace, or for a `strumSeq`
rise with no stroke to upgrade, the verdict starts its own directed stroke. Both
counters rising in the same update is treated as a strum whose direction was known
at the onset: ONE directed stroke that keeps the full string-by-string stagger.

A null direction is ignored, exactly as `StrumBurstOverlay` ignores it for sparks.
The neutral impact ring on the burst overlay follows the same rule: `onsetSeq` fires
a direction-free ring (0.28 s, theme on-surface tint), the directional spark and pick
sweep follow on `strumSeq`.

### D4 — The strings band is the Live juice (chunk 016b P0)

`SsStrumStrings` (design system, `components/music/`) over the pure-Dart geometry
`SsStrumStringsModel` is the hit-juice this round ships. Geometry: 6 strings, index
0 = low E at the top; sweep 60 ms → 12 ms per string; per-string ring-out
`A·exp(−t/τ)·sin(2πft)` with τ = ringSec/4.2 = 142.9 ms, f 9 → 14 Hz low→high,
amplitude scaled by stroke strength and by string gauge (1.00 → 0.55); the pick
sweeps across [−0.8, 5.8] string lanes, mirrored for up-strokes. The band is fed
`onsetSeq`/`strumSeq` on Live (72 dp, labelled) and — through the shared
`StrumStringsBand` wrapper (56 dp, decorative, strength floored at 0.35 like the
spark) — on Practice and the Song Trainer.

**On the scored surfaces `onsetSeq` is hard-wired to 0 and not exposed.** They are
fed by `PracticeStrumFeedback`, which is emitted once per stroke *after* the scoring
pass with the direction already decided, so there is no earlier onset signal to pass
and every stroke there is a directed one. The two-stage feel is Live-only until a
controller-level onset event exists.

### D5 — Event-driven decay, self-stopping ticker, reduced motion

The band owns a local `Ticker` (the `StrumBurstOverlay` discipline): started when a
stroke is added, stopped — with the clock reset — when the last stroke is pruned, so
an idle band schedules no frames and `pumpAndSettle` terminates. A late verdict
resolves a stroke but never restarts the ticker (that would reset the clock its
`startSec` is measured against). This is decay triggered by an event, not rhythm, so
ADR 0274's audio-clock rule does not apply; ADR 0274 §5.1 does — under reduced
motion there are no strokes and no frames, and the last known direction survives as
a static pick glyph parked on the string the sweep would have ended on.

### D6 — The mock reproduces the gap

`MockStrumEngine` publishes `onsetSeq` = pattern strums struck at or before *t* and
`strumSeq` = the same count evaluated `MockStrumEngine.directionDelay = 70 ms`
earlier, so demo mode shows the same two-stage behaviour as a microphone instead of
a synchronised single event.

## Measured

**Where the 58 ms comes from** (`test/features/live/engine/capture_latency_probe_test.dart`,
44.1 kHz, attack at a known sample, latency = feed-cursor position when the carrying
`LiveFrame` was emitted, minus the attack; every bound derived from framing
constants, never hand-picked):

```
  onset-first  = onsetWindow 1024 + _postFrames 2 hops − 2.5-hop attack offset =  896 samples = 20.3 ms
  direction    = onsetWindow 1024 + _classifyAfterFrames 12 hops − same offset = 3456 samples = 78.4 ms
  emit cadence = 0 ms for both (addChunk emits immediately); ≤66 ms still bounds level/chord refresh
  gap          = 2560 samples = 58.1 ms   ← what the strings fill
```

In-app latency by capture chunk size (probe output):

```
  chunk   512 ( 11.6 ms): onset  25.1 ms, direction  83.1 ms
  chunk  1024 ( 23.2 ms): onset  25.1 ms, direction  94.7 ms
  chunk  4096 ( 92.9 ms): onset  71.5 ms, direction 164.4 ms
  chunk  6400 (145.1 ms): onset 135.4 ms, direction 135.4 ms   ← Android today
  chunk 22050 (500.0 ms): onset 200.0 ms, direction 200.0 ms   ← iOS tap request
```

At 6400/22050 both verdicts fall inside the same chunk and collapse into one emitted
frame — i.e. **on Android today the two stages are not separable at all**, because
the capture buffer is longer than the gap between them. Composed worst case (attack
landing just after a chunk boundary): 165.4 ms to the ring, 223.5 ms to the arrow, of
which 145.1 ms is the mic chunk. The DSP path itself meets the <80 ms felt target
(20.3 / 78.4 ms); the target is missed on-device purely because of capture buffering,
and `audio_streamer` 4.3.0 exposes no knob for it (Android hard-codes 6400 samples,
iOS `installTap(bufferSize: 22050)`) — see chunk 001 and chunk 010.

**The visual, measured on the real model and the real widget:**

- Envelope at `ringSec` = 1.51 % of peak → the hard cut-off is invisible, not a pop;
  worst swing 0.348 string-spacings < 0.5, so no string crosses into its neighbour's
  lane; pick mirror symmetry |down(t) + up(t) − 5| ≤ 8.9e-16.
- Idle band: `hasScheduledFrame == false`, `pumpAndSettle()` = 1 frame. A `strumSeq`
  rise schedules frames and the band settles by itself.
- Late-verdict pair: a verdict 0.1 s after the onset (inside the grace) leaves the
  band completely settled 0.66 s after the onset = ONE stroke ending at
  onset + `ringSec`; a verdict 0.3 s after (past the grace) is still animating at
  0.7 s, because a second stroke runs to 0.96 s.
- Mock parity: swept 0–12 s at 5 ms, both counters monotonic, `onsetSeq ≥ strumSeq`
  and `onsetSeq − strumSeq ≤ 1` (the tightest pattern gap, 312.5 ms at 96 BPM, is
  4.5× the 70 ms delay). The 60 ms tick is shorter than the 70 ms delay, so the
  first emitted frame of a demo strum is always onset-only.

## Consequences

- The learner sees the strings react **58 ms of DSP earlier** than the arrow, and
  sees *something* even when ADR 0549's gate suppresses the stroke — and 35 % of
  true strums are suppressed at the shipped gate (GuitarSet retention 0.649), with
  up-strokes hardest hit (ADR 0581).
- The frame contract grew two fields with safe defaults, so every existing producer
  (mocks, fakes, the Practice path) is unchanged and simply never bumps `onsetSeq`.
- Direction quality is untouched by this ADR, and stays the open problem: GuitarSet
  direction macro-F1 0.4311 at the shipped gate (ADR 0549), new-player Klangio LOGO
  accuracy 0.6061 ± 0.0548 vs 0.807 same-player (ADR 0549, `ml/model_card.json`),
  against the Chapter 14 §7.2 Alpha gate of 0.80. The two-stage split makes a *late*
  verdict cheap; it does not make a *wrong* verdict cheap.
- On Android the whole benefit is currently masked by the 145 ms capture chunk. The
  first honest on-device statement about this feature needs either a capture-buffer
  fix (plugin fork/PR or another package) or an acceptance that the ring and the
  arrow arrive together.
- Acceptance stays the owner's real-guitar APK test (same predicate as ADR 0581 and
  chunk 018). Everything above is host-side: synthetic probes, widget tests and a
  headless emulator harness that replays a WAV through the capture-factory seam —
  no figure here was produced by a phone microphone.
