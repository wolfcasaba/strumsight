---
id: 016b
topic: World-class strum highway + game-feel + latency calibration (Flutter, 2026)
tags: [animation, highway, juice, custompainter, impeller, shader, latency, calibration, gamefeel]
sources:
  - https://www.giantbomb.com/note-highway/3015-7102/ (note highway convention)
  - https://arxiv.org/pdf/2011.09201 (Designing Game Feel survey)
  - https://hackread.com/the-juice-factor-designing-game-feel/ (juice)
  - https://docs.flutter.dev/ui/design/graphics/fragment-shaders (Flutter shaders)
  - https://ddrkirbyisq.medium.com/rhythm-quest-devlog-10-latency-calibration-fb6f1a56395c (latency calibration)
  - https://www.ubisoft.com/en-us/help/rocksmith-plus/gameplay/article/changing-difficulty-settings-in-rocksmith/000097526 (Dynamic Difficulty)
researched: 2026-07-10 (4-agent Hermes sweep)
---

# Making the strum highway world-class (and reel-viral)

**Current state (the ceiling).** `lib/features/learn/widgets/lesson_highway.dart`
is a widget `Stack` of `Positioned`+`Transform.scale` cards **re-laid-out every
frame**; `lib/features/share/screens/strum_reel_screen.dart` does a
**whole-screen `setState` per Ticker frame**. Both are the main perf/juice
ceiling. `lib/features/live/widgets/strum_arrow.dart` is already the RIGHT
pattern — a real `CustomPainter` with tight `shouldRepaint` and **shape+color**
encoding (color-blind safe) — use it as the template everywhere.

## The game-feel gaps (what turns "a diagram scrolling" into "a game")
- **Simultaneous hit-juice at the strike line (P0):** on cross, fire together on
  the SAME frame the beat sounds — hit-stop (freeze scale 1–2 frames), a
  particle/shader spark in the note's copper/green, a `PERFECT/GOOD/EARLY/LATE`
  pop (`flutter_animate`), a chime, a haptic tick. Misaligned juice feels WORSE
  than none.
- **Reward chain (P1):** running **combo multiplier** + a soft rock-meter +
  **Duolingo safe-failure** (misses nudge, never a harsh red X) + section-end
  confetti. Beginners miss constantly → failure must feel *safe* or they quit.
  Keep the in-song verdict to **one glyph + one word**; push stats to the
  results screen.
- **Dynamic Difficulty (P4):** Rocksmith's most-credited feature = progressive
  strum density — start downbeats-only, layer in up-strokes/off-beats as
  accuracy rises; per-song memory + a "show everything" toggle.
- **Anticipation (P5):** vanishing-point perspective — notes start small/dim far
  away, grow + brighten toward the line (Synthesia's real power is read-ahead).
- **Accessibility:** never rely on hue alone — down = copper *down-glyph*, up =
  green *up-glyph* (already true in `StrumArrow`; extend to the highway).
- **Feedback vocabulary:** Yousician's early/late/correct + a `↕ wrong-way`
  badge; for pitch, needle→green-zone + cents + a pitch-history dot trail.

## Flutter rendering (2026)
- **Impeller is the default** (iOS+Android) → AOT shaders, predictable budget;
  target **120 fps = ~8.33 ms/frame** (~4 ms UI + ~4 ms raster).
- **Collapse the highway into ONE `CustomPainter`** (P2) driven by a single
  `AnimationController`/`ValueListenable<double> playhead` → `AnimatedBuilder`
  → `CustomPaint`, wrapped in **`RepaintBoundary`**. Many overlapping
  transparent widgets each = draw calls; one `paint()` pass is the documented
  win. Cache `Paint` objects (no per-frame alloc), tight `shouldRepaint`, keep
  chord-name text as a thin cached widget/`Paragraph` layer.
- **`flutter_animate` for discrete juice** (hit pop, confetti, count-in, reel
  shimmer); **one raw `Ticker`/`AnimationController` for the continuous scroll**
  (tempo-locked, deterministic). Don't animate the scroll with implicit anims.
- **Glow/particles via fragment shaders** (`flutter_shaders`, `AnimatedSampler`):
  radial-falloff × color = real glow with NO blur pass, far cheaper than stacked
  `BoxShadow`. Budget ≤4–5 ms, avoid branching, prefer `mix`/`smoothstep`/`clamp`.
- **Flame engine not warranted** — one scrolling lane → a single painter is
  lighter and reuses the `StrumArrow` code.

## Audio-visual latency (Android — decisive for a rhythm game)
Android round-trip audio latency is device-specific and often >20 ms; there is
**no universal offset**. Model **three** latencies — audio, visual, input —
audio is usually the largest on Android. Approach:
- **Pre-schedule the beat audio** to its sample time regardless of input (so the
  *sound* is always right), then compensate only the visual/input offset.
- **Ship a Rock-Band-style calibration flow:** a tap test with **separate audio
  and video offsets** (allow negatives), ~4–8 samples, real-time flash feedback,
  and **silent tap buttons** (so taps don't pollute the audio measurement).
  Persist per device; re-prompt on output-route change (Bluetooth adds big lag).
- Offset the strike-line crossing by the calibrated visual offset so the arrow
  crosses exactly when the beat is heard. `soundpool` is slow — use a
  low-latency path at **48 kHz** and pre-warm it (first play has a warm-up cost).

## Ranked recommendations (impact ÷ effort)
- **P0** Simultaneous hit-juice at the strike line. *medium — the single biggest feel upgrade.*
  ✅ **DONE (round strum-strings, 4th step below):** the strum juice is now the
  **six-string band** (`SsStrumStrings`) plus the spark and a neutral impact ring,
  on **Live, Practice and the Song Trainer** — and on Live it fires on the ONSET,
  58 ms of DSP before the direction verdict exists (ADR 0582).
- **P1** Combo/multiplier + safe-failure + section-end celebration. *medium.*
- **P2** Highway → one `CustomPainter` + `RepaintBoundary` + single controller (unblocks P0 particles + 120 fps). *medium–high.*
- **P3** Latency calibration + pre-scheduled beat + low-latency 48 kHz engine. *medium — without it juice mis-lands on Android.*
  **PARTIAL round 72:** the calibration flow shipped — Settings → "Timing
  calibration": 100 BPM click + 8 silent taps → median offset (MAD stability
  gate ±40 ms, botched taps >250 ms discarded) → persisted ms (local-only,
  `inputLatencyProvider`) → `LessonScorer.inputLatencySec` corrects every
  mic-fed timestamp (strums, chord obs, miss clock).
  **Round 74 added the VISUAL half:** the calibration screen gained a Visual
  mode (tap on the FLASH, no click) → `visualLatencyProvider`; the Learn
  highway draws with `playhead − (audioMs − visualMs)/1000 · bps` so a card
  crosses the strike line when the beat is HEARD (Bluetooth-style audio lag
  ⇒ visuals drawn later). Scoring/metronome keep the true playhead. NOT yet
  done: the 48 kHz low-latency audio path + pre-scheduled beat audio. True
  end-to-end latency numbers need the real-guitar APK test.
- **P4** Progressive strum density (Dynamic Difficulty). *medium.*
  ✅ r63 static half (Easy toggle) + **r154 progressive half**: `LessonScorer.failStreak`
  (consecutive miss/wrong since the last hit; one hit resets) → at 4 the HUD shows a
  QUIET offer row "try Easy mode?" (switch = toggle + restart, never forced); the
  reverse offer ("try the full lesson?") appears in Easy at ≥90 % accuracy over ≥8
  resolved events. True per-event density morphing (Rocksmith-style) stays future work.
- **P5** Vanishing-point perspective + radial-shader glow (screenshot/reel-worthy). *medium.*
- **P6** Signed timing + wrong-direction feedback vocabulary. *low–medium.*
- **P7** Reel viral polish (branded end-card, downbeat punch-in, 1-tap share) once P0/P5 land. *low.*

## AS BUILT (2026-09-15) — the strike-line spark reaches the Live hero
`HitBurst` moved from `features/learn/widgets/` to **`core/widgets/hit_burst.dart`**
(shared, dependency-free geometry) and gained `directionSign` (−1 = the
default upward cone, +1 = downward). New `features/live/widgets/strum_burst_hero.dart`
wraps the Stage `SsChordHero`: every NEW `LiveFrame.strumSeq` throws a spark
over the ↓/↑ glyph — copper fanning down for ↓, confidence-green fanning up
for ↑, strength = stroke confidence (clamped ≥ 0.35). A local `Ticker` runs
only while a burst is alive (≤ 0.45 s) and stops itself, so an idle Live
schedules no frames and `pumpAndSettle` terminates; reduced motion
(`SsMotionScope`) draws no spark (the glyph shape already carries direction).
This is event-driven decay, not rhythm — ADR 0274's audio-clock rule is not
in play. Next on this thread (Chapter 18 plan): verdict pop + combo counter
on Live once a beat-relative timing verdict exists there (today Live has no
scorer, only the metronome grid).

## AS BUILT (2026-09-15, 2nd step) — the same spark on Practice and Song Trainer
`StrumBurstOverlay` (was the Live-only `StrumBurstHero`) now lives in
**`core/widgets/strum_burst_overlay.dart`** with a caller-supplied `centerOf`
and `strength`. The Practice engine exposes a per-strum stream —
`PracticeSessionController.strumFeedback` → `PracticeStrumFeedback`
(observed direction + confidence + the matched target's LIVE verdict, null
for a stray) — through the `PracticeSessionHost` boundary; the session
screen forwards it to `StrumPatternView` / `ChordProgressionView`, which
burst at the strike line (mirrored for left-handed) with the Learn timing
ladder (PERFECT 1.0 · GOOD 0.72 · EARLY/LATE 0.45 · missed/stray 0.35) and
finally show the live verdict in `PracticeFeedback` (the old R10 null gap).
`SongTrainerController.practiceStrumFeedback` passes the scored session's
stream through; the trainer's running body bursts at the strum lane's
"now" edge. Nothing here touches DSP or the reducer: the stream is emitted
from the controller's observation intake right after the scoring pass.

## AS BUILT (2026-09-15, 3rd step) — streak flame + share reveal (Ch18 R06/R07 slice)
`SsFlame` (**`core/design_system/components/music/ss_flame.dart`**) is the
painted streak glyph — S 16 / M 40 / L 72 — lit (colour + light core) or
dim (same shape, grey). It "ignites" ONCE (grow 0.6 → 1.18 → 1 about the
foot, plus a sine glow, `celebration` = 700 ms) when `lit` flips true, when
the caller's `ignition` counter rises (the streak length → the daily-credit
moment) or on mount (`igniteOnMount`, hero reveal). No idle flicker (§9.7 —
no endless decoration): at rest it schedules no frames. Reduced motion
snaps. `SsFlame.milestoneFor(days)` → 7/30/100. Wired: `StreakBadge` (Live
header, ignites on credit), `StreakScreen` hero (L, ignite on entry,
milestone pill, one `SsStaggeredEntrance` of six groups = 500 ms), the
gamification streak tile (S), `StreakStatusCard` (M, for the two "lit"
reasons only) and the streak-detail current card (M; the caller-fed
`reduceMotion` reaches it through `SsMotionScope(appOverride:)`).
`SsShareReveal` + `SsRevealSlot` (**`motion/ss_share_reveal.dart`**): one
0 → 1 progress over `celebration`, inherited down the card; each slot maps
it onto its own [start, end] window (fade + 10 px rise, or `landing` from
1.6× for the ↓/↑ arrows — `SsRevealSlot.windowFor` spreads the arrows
evenly over 0.40–0.85). At/after `end`, or with no reveal above, a slot
returns its child UNTOUCHED — so the `RepaintBoundary` capture and the
card tests see the plain card. `SharePreviewScreen` / `WrappedPreviewScreen`
gate the IMAGE share on `onCompleted` (text share never waits) and press
the card to 0.98 (`instant`) outside the boundary. The milestone SCENE
(`SsCelebrationScene` via the ADR 0389 coordinator) stays R03's.

## AS BUILT (2026-09-15, 4th step) — the STRINGS BAND is the P0 hit-juice, and on Live it fires on the ONSET
**The P0 gap above is closed** (ADR 0582). The strum juice is no longer only a
spark: a painted six-string band rings under the hero on every stroke, on
**Live, Practice and the Song Trainer** — one stroke reads as one event because
all three surfaces use the same copper-down / green-up pair the spark uses.

- **Geometry is pure Dart** (`core/design_system/components/music/ss_strum_strings_model.dart`,
  `dart:math` only — no Flutter, no `core/music`): 6 strings, index 0 = low E at
  the top; the pick sweeps 60 ms across the set → **12 ms per string**; each
  string then rings `A·exp(−t/τ)·sin(2πft)` with **τ = ringSec/4.2 = 142.9 ms**,
  **f 9 → 14 Hz** low→high, `A` scaled by stroke strength AND by string gauge
  (1.00 → 0.55). MEASURED: the envelope is at **1.51 % of peak at `ringSec`**
  (0.6 s), so the hard cut-off is invisible rather than a pop; the worst swing is
  **0.348 string-spacings < 0.5**, so no string reaches its neighbour's lane; the
  up-stroke pick is an exact reflection of the down-stroke (|down+up−5| ≤ 8.9e-16).
- **The widget** (`ss_strum_strings.dart`) is the `StrumBurstOverlay` ticker
  discipline: a local `Ticker` started when a stroke is added, stopped with the
  clock reset when the last stroke is pruned → an idle band schedules **no
  frames** (measured: `hasScheduledFrame == false`, `pumpAndSettle()` = 1 frame)
  and `pumpAndSettle` terminates. Painter: each string is a 24-segment polyline
  whose displacement is shaped by `sin(πx/width)` (pinned at the nut and bridge),
  stroke width 2.4 px × gauge, all `Paint`s cached, `RepaintBoundary` on top.
  A 9–14 Hz sine sampled at 60 fps read as a slow WOBBLE in the frame dump, so
  each excited string also draws two faint ghost lines at ± its decay envelope
  (the shape the eye knows as a ringing string), the tint fades with `sqrt(decay)`
  so a struck string still LOOKS struck once its swing is sub-pixel, and the pick
  carries a three-ghost trail (12/24/36 ms lag) plus a soft glow. This was judged
  on rendered frames, not by eye: `test/tools/strum_strings_frame_dump_test.dart`
  writes PNGs to `build/strings_frames/` with `STRINGS_FRAME_DUMP=1`.
- **Two-stage on Live only.** `LiveFrame.onsetSeq` starts an UNDIRECTED stroke
  (six strings ring together, neutral colour, no pick); the `strumSeq` verdict
  ~58 ms of DSP later RESOLVES that same stroke in place (pick + direction
  colour, ring-out never restarts) while it is younger than
  `directionGraceSec = 0.25 s`. MEASURED matched pair: a verdict 0.1 s after the
  onset leaves the band settled 0.66 s after the onset (ONE stroke); a verdict at
  0.3 s is still animating at 0.7 s, because that one legitimately starts a
  SECOND stroke (0.96 s). The burst overlay follows the same split — a neutral
  0.28 s impact ring on the onset, the directional spark on the verdict.
- **Practice / Song Trainer get the directed-only variant** through the shared
  56 dp `core/widgets/strum_strings_band.dart` (Live's own band is 72 dp and
  labelled; the scored ones are decorative, `ExcludeSemantics`, because both
  screens already announce the stroke in words). `onsetSeq` is hard-wired to 0
  there and NOT exposed: `PracticeStrumFeedback` is emitted once per stroke after
  the scoring pass with the direction already decided, so there is no earlier
  onset signal to pass. Strength is floored at 0.35 exactly as the spark floors
  its burst, so a dim stroke is never a dead band under a visible spark.
- **Reduced motion** (`SsMotionScope`, ADR 0274 §5.1): no strokes, no ticker, no
  frames — and the last known direction survives as a STATIC pick glyph parked on
  the string the sweep would have ended on. A running stroke is dropped the
  moment reduced motion turns on.
- **Honest limit:** every number here is host-side (widget tests + a frame dump).
  The felt latency on a phone is dominated by the capture buffer, not by this
  code — chunk 010's measured table, 145 ms of Android mic chunk vs 20.3 ms of
  onset-first DSP. Next on this thread: verdict pop + combo counter on Live once
  a beat-relative timing verdict exists there.
