# Strum direction: what the teaching sources actually agree on (2026-09)

Research behind `lib/features/curriculum/domain/rhythm_grid.dart`. The question
was narrow and load-bearing: **may the app decide, on its own, which way the hand
should be travelling at a given moment — and tell a learner they got it wrong?**

The rhythm pillar is the part no competitor has (`docs/rag/chunks/012`: "No
competitor detects strum DIRECTION (↓/↑) — that stays our moat"). That makes the
risk asymmetric. A chord recogniser that is wrong says "I did not hear C". A
direction grader that is wrong says "you strummed the wrong way" about someone
who did it correctly — and the learner, being a beginner, will believe it.

## 1. What every source agrees on

**Within continuous eighth-note strumming, direction is not a free choice.**

- The on-beat strokes (the "numbers": 1, 2, 3, 4) are **downstrokes**.
- The off-beats (the "ands") are **upstrokes**.

And the second half, which matters just as much:

**The hand does not stop.** The arm keeps moving down-up-down-up even when it is
not striking the strings. A pattern with gaps is therefore not a pattern with
fewer strokes — it is the same pendulum with some strokes **ghosted**: the hand
still travels, it just misses the strings. Sources put it as "keep your hand
moving like a pendulum — even when you skip a sound, your hand still swings,
which locks time", and describe the unstruck slots explicitly as ghost strokes.

Two consequences were taken straight into the model:

1. `RhythmGrid.pendulum` takes a `struck` list of booleans, never a list of
   directions. An author says WHETHER a slot sounds; the grid decides WHICH WAY.
   An upstroke cannot be placed on a beat by accident.
2. A ghosted slot still carries a direction, because hand travel is physical and
   continues through it. This is also why a ghost slot is never graded: the grid
   asked for no sound there, so there is nothing to hear and nothing to miss.

**At quarter-note resolution every stroke is a downstroke.** The return travel
is not a slot at that resolution, which is why the app's existing
`first-strums` lesson is `[D, ., D, ., D, ., D, .]` and why the course's first
right-hand rung is down-quarters.

## 2. Where the rule stops — the counterexample that decided the design

The pendulum is the rule for **continuous strumming**, not a law of guitar. The
3/4 waltz accompaniment is a documented, taught counterexample: a bass note
**down** on ONE and light chords **up** on two and three — "oom-pah-pah",
strummed "down-up-up". Upstrokes land squarely on beats, and that is correct.

This is not hypothetical for StrumSight: the app **already ships** it as the
`waltz-time` lesson (`lesson.dart`, `[_d, null, _u, null, _u, null]`). An audit
of the 18 shipped lesson patterns found this is the only one that departs from
the pendulum, and research says it is right to.

Had the pendulum been encoded as a hard invariant — the obvious, tidy choice —
the app would have called a correctly-taught folk waltz wrong. So the model has
two constructors: `RhythmGrid.pendulum` (directions derived; what the beginner
rungs use) and `RhythmGrid.authored` (directions given; for patterns that
legitimately depart), with `followsPendulum` reporting which kind a grid is. The
beginner course may require the derived kind without outlawing the rest of music.

Reggae and funk were checked as possible second counterexamples and are **not**
ones: both put upstrokes on the OFF-beats, never on the downbeat. They agree with
the pendulum; they simply ghost most of the on-beats. The app's `reggae-skank`
lesson (`[., U, ., U, ., U, ., U]`) is a pendulum pattern.

## 3. What is NOT claimed

- **Nothing here is a measurement of this app's accuracy.** These sources settle
  what the app should ASK for. Whether the engine can reliably HEAR a given
  stroke's direction on real audio is a separate question, measured separately
  (`onsetTolerance50Ms`, the direction-F1 metric, and the open real-guitar A/B in
  ADR 0539 D4). In particular, no minor chord and no up-stroke-heavy pattern has
  been verified on real recordings yet — all seven reference recordings are major
  chords.
- **Sixteenth-note subdivision is out of scope.** The same alternation extends to
  sixteenths (down on the number and the "and", up on "e" and "a"), but the model
  stops at eighths because that is what the beginner course uses, and shipping an
  untested third subdivision would be untested surface.
- **Whether a 50 ms window is the right feel tolerance for a BEGINNER** is not
  settled by this research. It is the window the recogniser is measured at, which
  is a different claim: it says the app's notion of "in time" is not invented, not
  that it is pedagogically ideal. If it proves too strict in use, the fix is a
  measurement, not a quiet widening.

## Sources

Pendulum and hand motion:

- [Good Guitarist — crash course, more strumming](https://goodguitarist.com/crash-course-more-strumming/)
- [Total Guitarist — introduction to guitar strumming](http://totalguitarist.com/lessons/technique/chords/strumming/intro/)
- [Online Guitar Books — right hand movement and strumming](https://onlineguitarbooks.com/strumming-directions/)
- [HubGuitar — learning strumming patterns](https://hubguitar.com/rhythm/learning-strumming-patterns)
- [Tomas Michaud — the best guitar strumming lesson](https://tomasmichaud.com/best-guitar-strumming/)
- [Ultimate Guitar — how to read and play strumming patterns](https://help.ultimate-guitar.com/en/articles/6744662-strumming-patterns-how-to-read-play)

Ghost strokes and skipped strokes:

- [StringKick — 7 essential strumming patterns](https://www.stringkick.com/blog-lessons/strumming-patterns/)
- [School of Rock — best guitar strumming patterns and techniques](https://www.schoolofrock.com/resources/guitar/best-guitar-strumming-patterns-and-techniques)
- [Online Guitar Tuner — how to read guitar strumming patterns](https://www.online-guitartuner.com/blog/how-to-read-guitar-strumming-patterns)
- [Acoustic Guitar Playing — eighth-note strumming patterns](http://www.acousticguitarplaying.info/rhythm-exercise-eighth-note-strumming-patterns/)

The waltz counterexample:

- [Folk Friend — how to strum a waltz](https://folkfriend.co.uk/how-to-strum-a-waltz-easy-folk-guitar-strumming-pattern-lesson/)
- [Acoustic Guitar — weekly workout, living in 3/4 time](https://acousticguitar.com/weekly-workout-living-in-34-time/)
- [Soundbrenner — waltz rhythm](https://www.soundbrenner.com/blogs/articles/waltz-rhythm)
- [Wikipedia — oom-pah](https://en.wikipedia.org/wiki/Oom-pah)

Off-beat genres, checked and found consistent with the pendulum:

- [Wikipedia — ska stroke](https://en.wikipedia.org/wiki/Ska_stroke)
- [Guitar Wiz — reggae guitar chords, skank rhythm and upstrokes](https://guitarwiz.app/articles/reggae-guitar-chords/)
- [Guitar Wiz — syncopation on guitar](https://guitarwiz.app/articles/syncopation-guitar/)
