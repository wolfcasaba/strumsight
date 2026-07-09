---
id: 014
topic: Play-along "Learn" mode — the strum-highway animation (our Yousician-class trainer) and how it's built
tags: [learn, play-along, animation, highway, lesson, tempo, timing, roadmap, scoring]
sources:
  - User request (2026-07-09): a guitar-learning program with animation "like Yousician", but a unique animation of our own
  - Yousician / Rocksmith note-highway UX (prior art — a scrolling timeline toward a hit line); ours is horizontal + strum-direction-first
  - RAG chunk 006 (strum direction — the moat the animation showcases), chunk 013 (retention/streak the lessons feed)
---

# Play-along "Learn" mode

**What & why.** A Yousician-style animated trainer, but with **our own**
animation built around the moat: a horizontal **strum highway** where chord +
**↓/↑ arrow** cards flow right-to-left toward a fixed **strike line** in tempo
and pulse as they cross it (down = copper, up = confidence-green). No competitor
teaches strum *direction*; this makes it the hero of the learning UX and ties
the daily challenge (chunk 013) into something you actually play.

## Architecture (round 32 — animation only; scoring is next)
```
Lesson (chords/bar + 8-slot strum pattern)         lib/features/learn/model/lesson.dart
  → events: [ {beat, chord, direction}, … ]        (pure expansion, eighth-note grid)
LessonTiming (pure)                                lib/features/learn/lesson_timing.dart
  playhead = elapsed·bpm/60 − countInBeats         (negative during count-in)
  xForEvent = strikeX + (beat − playhead)·pxPerBeat
LessonHighway (pure render from playheadBeat)      lib/features/learn/widgets/lesson_highway.dart
LearnScreen (Ticker → elapsed → playhead)          lib/features/learn/screens/learn_screen.dart
LessonListScreen (built-ins + today's challenge)   lib/features/learn/screens/lesson_list_screen.dart
```
- **Pure/timing split is deliberate:** all beat→pixel maths is in `LessonTiming`
  (no clocks) so it is exhaustively unit-tested; only `LearnScreen` owns the
  `Ticker`. Same discipline as the DSP (chunk 010) and streak logic (chunk 013).
- **Deterministic tests:** the screen **starts paused** so the animation doesn't
  free-run; widget tests advance time with `tester.pump(Duration)` and never
  `pumpAndSettle` a live ticker.
- **Count-in:** a 4-beat count-in (playhead runs −4→0) with a flashed number.
- **Entry points:** a 5th **Learn** nav tab (`/learn`), and the streak screen's
  **Play along** button opens today's challenge as a one-bar strum-only lesson
  (`Lessons.fromDailyChallenge`).

## Built-in lessons (grow later)
`First Strums` (Em/G, all down-strokes on the beat, 70 BPM) and `Down-Up Groove`
(C–G–Am–F, the D-DU-UDU pop pattern, 90 BPM). Add a real library + difficulty
tiers once scoring lands.

## Live scoring (round 33 — ✅ built)
`lesson_scorer.dart`: a PURE `LessonScorer` matches detected strums (direction +
elapsed time) to the nearest open `LessonEvent` within `windowSec` (±0.28 s) →
**hit / wrong-direction / missed**, with combo, max-combo and accuracy; `passed`
at ≥70%. `LearnScreen` (now `ConsumerStatefulWidget`) subscribes to
`liveFrameProvider` **only while playing** (`ref.listenManual`, closed on
pause/dispose — starts the mic just for the run), scores each **discrete** strum,
shows a live accuracy/combo HUD + a hit/miss flash, and on finish records
practice (feeds the streak) and shows a score summary.
- **Discrete-strum detection:** `latestStrum` lingers ~2 s and repeats can share
  a direction, so `LiveFrame` gained a **`strumSeq`** counter (bumped once per new
  strum in `LivePipeline`); the scorer fires on `strumSeq` changes, not on
  `latestStrum` identity. `strumSeq` defaults to 0 (non-breaking).
- Scored on **direction + timing** (the moat). Chord-correctness is NOT gated yet
  (chord detection lags ~370 ms) — a refinement. The mic→score path is only
  verifiable on-device (the real-guitar acceptance test); the scorer itself is
  exhaustively unit-tested.

## Curriculum (round 34 — ✅ built)
7 built-in lessons across **Beginner / Intermediate / Advanced** tiers
(`Lessons.byDifficulty`). `LessonProgressController` persists per-lesson **best
accuracy** (`lesson_progress_v1`, local like the streak); `LessonProgress.stars`
maps it to 0–3 stars (≥90/80/70%). The `LearnScreen` records the run's accuracy
on finish. The list groups by tier, shows stars, and **gates progression** —
a lesson unlocks once the previous in its tier is passed (`isUnlocked`).

## Roadmap
1. Import a saved Analyze clip as a lesson. Gate hits on the **chord** too (not
   just direction) once the ~370 ms chord lag is handled.
3. Audio: a metronome click + optional backing so it's playable without reading
   only (uses the existing `audioplayers` dep).
4. Share a completed-lesson score card (feeds chunk 013's share loop).
