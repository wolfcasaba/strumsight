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
