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
8 built-in lessons across **Beginner / Intermediate / Advanced** tiers (incl. a barre-chord lesson, round 44)
(`Lessons.byDifficulty`). `LessonProgressController` persists per-lesson **best
accuracy** (`lesson_progress_v1`, local like the streak); `LessonProgress.stars`
maps it to 0–3 stars (≥90/80/70%). The `LearnScreen` records the run's accuracy
on finish. The list groups by tier, shows stars, and **gates progression** —
a lesson unlocks once the previous in its tier is passed (`isUnlocked`).

## Score-card share (round 35 — ✅ built)
A completed lesson can be shared as a 9:16 **lesson score card**
(`LessonScoreCard` + `LessonScorePreviewScreen`), reusing the round-29 share
pipeline via a new generic `ShareService.shareImage(boundaryKey, caption,
fileName)`. Caption = `ShareContent.lessonCaption` (score + stars + best combo +
moat + install link + `#StrumSightChallenge`). Reachable from the end-of-lesson
summary dialog — wires Learn into the chunk-013 viral loop (a brag card =
motivation + reach).

## Metronome (round 36 — ✅ built)
`audio/metronome.dart`: the click is **synthesised in pure Dart** (a short
decaying-sine → a valid 16-bit PCM WAV via `buildClickWav`, unit-tested) so there
is NO bundled asset; playback goes through the existing `audioplayers`.
`LessonTiming.beatsCrossed(prev, next)` (pure) tells the player which integer
beats were crossed each frame — click on each (accent on bar downbeats), count-in
included. A mute toggle sits in the app bar. All playback is **fire-and-forget**
(`.ignore()`, never `await` a platform round-trip — it hangs where the channel is
absent) so a click can't stall the lesson clock. Playback itself is on-device-only
to verify (like mic scoring); the WAV + scheduling are the unit-tested surface.

## Import a recording as a lesson (round 37 — ✅ built)
`Lessons.fromAnalyze(AnalyzeResult, name:)` turns a saved clip into a play-along:
each detected strum → a beat-timed `LessonEvent` (`beat = (t − t0)/secPerBeat`,
tempo = the clip's detected BPM) on the chord that was sounding then; the length
extends to the bar containing the last stroke. `Lesson` gained a
`Lesson.fromEvents` constructor (and now stores `totalBeats` + derives
`chordSequence` from events) so it can hold irregular, imported events. Entry: a
"Practice as a lesson" 🎓 action on the **Library** session detail. Unlimited
content — practise any riff you recorded.

## Chord-aware scoring (round 38 — ✅ built)
`LessonScorer.observeChord(label, t)` records detected-chord change-points; each
chord-bearing event is graded (in `advance`/`finalize`) as correct if the target
chord was sounding **at** the stroke OR ~`_chordLagSec` (0.37 s) after — a
lag-tolerant, **secondary** metric that NEVER gates the reliable direction hit.
`ScoreSnapshot` gains `chordHits/chordTotal/chordAccuracy`; the summary shows
`Chords: N%` when the lesson has chords. `LearnScreen` feeds it `frame.current`.

## Polish (round 39 — ✅ built)
"Practice as a lesson" now also sits on the **Analyze** done view (import a riff
you just recorded without saving first); the metronome mute preference is
**persisted** (`metronomeMutedProvider`, local).

## Practice speed (round 40 — ✅ built)
A 50% / 75% / 100% speed selector on the player scales the effective tempo
(`_bpm = lesson.bpm × speed`); the playhead, metronome and scorer all use it
(`LessonScorer` gained a `bpm:` override). Changing speed restarts the run so the
tempo-dependent playhead maths stays clean. Slow-down practice is the classic
learning lever.

## Chord diagrams (round 41 — ✅ built)
`lib/features/chords/`: `ChordShapes` (a data table of ~21 open-position shapes,
low-E→high-E frets; −1 muted / 0 open) + `ChordDiagram` (a `CustomPaint` mini
fretboard with ○/× markers and dots). The player shows the **currently-fretted**
chord's diagram under the highway (`_activeChord()` = last event chord ≤ playhead).
Covers every chord the built-in lessons use (asserted by a test). Layout gotcha:
the diagram's own Column overflowed its reserved box in the 600px test viewport →
tightened both (highway 140, diagram size 66, size×1.05) to fit.

## Chord diagrams on Live (round 42 — ✅ built)
The detected chord's fretting now shows on the **Live** screen too, as a small
top-left **overlay** (`Positioned` in a `Stack`, `showLabel:false` so it doesn't
duplicate the huge chord letter) — deliberately an overlay, not a column child,
because the Live hero layout is height-tight (adding it inline overflowed by 72px).

## Chord library (round 43 — ✅ built)
`ChordLibraryScreen` (`/chords`, opened from the Learn app-bar grid icon): a
browsable dictionary of every `ChordShapes` fingering, grouped Major / Minor /
Sevenths / Suspended (`ChordShapes.allLabels` + a suffix classifier). A reference
tool for learners; reuses `ChordDiagram`.

## Roadmap
1. A backing track / count-in voice; the animated "Strum Cam" video share (growth #1).
2. Left-handed mirror mode; more chord shapes (barre chords); a search box on the library.
