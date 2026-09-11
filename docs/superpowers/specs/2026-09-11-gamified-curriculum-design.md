# Gamified guitar curriculum — design

**Date:** 2026-09-11 · **Status:** approved sections 1–2, sections 3–5 awaiting
review · **Requested by:** the user ("szeretnék hasonló játékos oktatási
programot" — a Yousician-like playful teaching programme, plus "csak fel le ütés
is legyen a ritmusérzékeltetéshez, a Yousicianon ilyen nincs")

**Standing user constraint, applies to every section:** the app must never teach
anything false; it must follow real guitar pedagogy. Every pedagogical ordering
claim in this document carries its source.

## 0. Decisions already taken (user, this session)

| question | decision |
|---|---|
| content source | generated exercises as the backbone + the learner's own songs; licensed songs a later, separate business question; NO hand-authored public-domain repertoire |
| scope | a NEW curriculum layer ON TOP of the existing engines — `gamification`, `practice_generator`, `today`, `progress_v2`, `streak` stay as they are |
| progression shape | a fixed, visible ladder, with the adaptive generator choosing WHAT is practised inside each level |
| mission completion | only `confirmed` recognition counts; mistakes never penalise; a mission cannot fail |
| rhythm pillar modes | all four: muted-string rhythm, silent grid + metronome, with a chord, and listen-and-repeat |
| architecture | approach A — the curriculum is a GOAL SEQUENCER over the existing planner |

## 1. The curriculum spine (APPROVED)

New feature `lib/features/curriculum/`. Four concepts, all DATA, no behaviour:

- **Course** — versioned (`courseId`, `version`). The version exists so a later
  re-ordering cannot silently invalidate progress already earned.
- **Stage** — a broad section ("First sounds", "First changes", "Rhythm in your
  hand").
- **Level** — one rung, bound to an existing `PracticeGoalType`.
- **Mission** — the smallest unit, and deliberately NOT a hand-written exercise.
  It is a triple: a `PracticeGoal`, a `SuccessCriteria` (the existing type,
  which "is never vacuously satisfied"), and an unlock rule.

Starting a mission asks the existing `practice_generator` to produce the actual
exercise from the learner's `SkillEstimate`. The curriculum says WHAT to
practise and WHEN the next rung opens; the already-written adaptive engine says
HOW.

### 1.1 The first stage's order, and its basis

REVISED TWICE, by research and then by measurement. The table below is what
ships (`lib/features/curriculum/data/beginner_course.dart`); what it replaced,
and why, is recorded after it.

| rung | content | measured |
|---|---|---|
| 1 | tuning + playing position | nothing, and it says so |
| 2 | right hand alone: muted strings, DOWN only, quarter notes | direction + timing |
| 3 | first shape: **Em**, one strum per chord, no pattern yet | chord |
| 4 | **Am**, then the **Em↔Am change** — and "keep the strumming hand moving" | chord + direction |
| 5 | **a playable two-chord song** | chord + direction |
| 6 | right hand: DOWN-UP eighths, still muted | direction |
| 7 | first pattern `↓ ↓↑ ↑↓↑` over Em/Am | chord + direction |
| 8 | **D**, then Am→D | chord + direction |
| 9 | **G**, then D→G | chord + direction |
| 10 | **C**, then G→C | chord + direction |

**Sources, and where they disagree.** Em first: two fingers, all six strings
ring, and Em→Am is among the easiest CHANGES — which matters more than the
shape, because every source agrees the change is the hard part. That choice is
CONTESTED and the contest is recorded rather than smoothed over: JustinGuitar,
the largest structured beginner course, starts D-A-E and defers minors to its
module 3, and Musicademy rejects the bedrock-chord opening entirely in favour of
G/Em7/Cadd9. Em-first is supported by the National Guitar Academy and Guitar
Noise, it is the easiest physical start, and — decisively — it agrees with the
three lessons this app ALREADY ships (`Lessons.all` opens on Em/G), so the app
teaches one order instead of two.

- [JustinGuitar — beginner 1, first steps](https://www.justinguitar.com/modules/beginner-1-first-steps)
- [JustinGuitar — A & D chords, play your first song](https://www.justinguitar.com/modules/a-d-chords-play-your-first-song)
- [Musicademy — how to teach beginners guitar](https://www.musicademy.com/blog/how-to-teach-beginners-guitar-a-new-approach/)
- [National Guitar Academy — easy guitar chords](https://nationalguitaracademy.com/chords/easy-guitar-chords/)
- [Guitar Noise — beginner chords](https://www.guitarnoise.com/help/beginner-chords/)
- [Tomas Michaud — strumming through chord changes](https://tomasmichaud.com/strumming-guitar/)
- [Fundamental Changes — changing chords while strumming](https://www.fundamental-changes.com/changing-chords-while-strumming/)
- [Tom Hess — teaching beginner guitar students](https://tomhess.net/TeachBeginnerGuitarStudents.aspx)

**What the first draft got wrong, corrected here.** An independent cross-check
contradicted three things the first version of this section asserted:

1. It called Em-first "the conventional first chord". It is not a consensus; see
   above. The claim is now stated as a choice with its reasons.
2. It put "change without stopping the strumming hand" at rung 8, as its own late
   milestone. Three independent teaching sources treat it as a rule applied from
   the VERY FIRST change, so it moved to rung 4.
3. It withheld a playable song until rung 10. That is a documented attrition
   risk — JustinGuitar has a two-chord song in module 1, and Tom Hess's
   teacher-training material argues explicitly against strict "master one skill
   before the next" sequencing. The song moved to rung 5, and the strumming
   pattern moved forward to rung 7 instead of sitting behind the whole chord set.

Uniformly supported by every source checked, and unchanged: isolating the right
hand on muted strings, and no barre chord or F anywhere in this stage.

### 1.2 No simplified stepping-stone chord — decided by measurement

Sources that dislike delaying C and G reach for simplified voicings rather than
delay: Cmaj7 for C, the two-finger G6 (320000) for G. Measured through the real
`LivePipeline`, neither can be SCORED honestly:

- **G6 is not in the recogniser's vocabulary at all.** `chord_dictionary.dart`
  carries maj, min, 7, maj7, m7, sus4, dim and aug — no 6 — so the two-finger
  shape reads as `G`. The app would be scoring a label it cannot distinguish from
  a different chord.
- **Cmaj7 does not reliably confirm.** On a clean three-second voicing it sat
  below the presence gate for 24 of 32 frames, against 3 for plain C. That is the
  maj7 Occam handicap doing its intended job — maj7 must be clearly present or
  phantom overtone energy would rename every triad — with plain C right next door
  taking the margin (RAG chunk 012).

So the course SCORES major and minor triads only. A simplified shape may be shown
as an unscored hint, never set as a mission target: a learner must never play
something correctly and be credited with nothing. Two tests pin this — every
scored chord must be in the recogniser's vocabulary, and must be a plain triad.

Also measured, and the reason the minor opening is defensible at all: Em, Am, D,
A, E, G and C all decode correctly AND confirm through the real pipeline on
realistic voicings (~22 of 32 frames each). Real-audio minors remain unverified —
all seven reference recordings are major — so that gap still stands (see §7).

## 2. Unlock and completion — the honesty rules (APPROVED)

1. **Only `confirmed` counts.** Progress accrues solely from confirmed
   recognition. `uncertain` and `rejected` frames give nothing and take nothing.
2. **No negative claim without confirmed evidence.** The app never says "you
   strummed up instead of down" unless the decision was `confirmed`
   (`AGENTS.md` §5; `debugDeriveChordDecision` already ranks this way).
3. **Blame the signal, not the player.** `signalQuality` already outranks
   `noChord`/`lowConfidence`, so a bad microphone reads as "I cannot hear you
   well", never as "you played it wrong". The curriculum inherits that.
4. **The "cannot measure" signal is the level METER, not a text banner.** The
   user's own words: *"ez a sok felirat hogy rossz a minőség nem kell, elég az
   equalizer jelzés"* (logged as E18-R01 F13). So §5's honesty and the user's
   request do not collide: the fact is present, just not as prose.
5. **Unlocking requires confidence, not luck.** Not a hit count: the gate is
   `SkillEstimateState` — `emerging` or better opens, `stale` and `conflicted`
   never open. A lucky run on thin evidence does not advance.
6. **A mission cannot fail.** There is no "failed", only "not yet done". This
   deliberately differs from Yousician's scoring.
7. **What is not measured says so.** Tuning/posture rungs use
   `SuccessCriterionKind.completion`, and the progress surface separates
   "measured" from "not measured" visibly. An unmeasured rung must never
   masquerade as measured skill.

**The cost, named.** With only confirmed evidence counting, a learner with a
weak microphone advances slowly and may feel stuck. The remedy is not a looser
gate but a **"practice without scoring"** mode: they can play, measurement is
off, and they know it. A silent microphone then never traps anyone, and no false
claim is made.

## 3. The rhythm pillar — down/up (NEEDS REVIEW)

This is the part Yousician does not have, and the repo's own research note
already calls it the moat: *"No competitor detects strum DIRECTION (↓/↑) — that
stays our moat"* (`docs/rag/chunks/012`). All four modes the user chose form a
pedagogical order of their own, from easiest to measure and easiest to play,
toward the real thing:

1. **Muted strings, no chord.** The left hand damps; only the right hand works.
   Strongest isolation and easiest recognition — there is no chord to get right,
   so a direction error cannot be confused with a fingering error.
2. **Silent grid + metronome.** The arrow row (`↓ ↑ ↓ ↑`) scrolls, the
   metronome ticks, the learner plays. The recogniser marks which strokes
   landed. Works with or without a chord.
3. **With a chord.** The target state: hold a shape and play the pattern.
   Harder, and the first mode where chord and direction are scored together.
4. **Listen and repeat.** The app plays a pattern, the learner plays it back.
   Trains the ear, not only reading.

**Notation.** `↓` downstroke, `↑` upstroke, `x` muted/dampened stroke, `>`
accent — the existing `Strum` model already carries `accent` and `muted`, so the
notation is not new vocabulary.

**What counts as "on time".** A stroke is credited to a grid slot when its onset
falls inside a tolerance window around the slot. The window must be a named,
documented constant with a measured basis, NOT a guess — the existing
recognition evaluation already uses a 50 ms onset tolerance
(`matchOnsetsUs(..., toleranceUs: 50000)` in
`tool/benchmarks/real_audio_dsp_baseline.dart`), and the release gate names
`onsetTolerance50Ms`. Reusing that constant keeps the curriculum's notion of
"in time" identical to the one the engine is already measured against, instead
of inventing a second, unmeasured one.

**Open question for implementation:** whether a MISSED slot (no stroke detected)
should count as neutral or as nothing-at-all. Rule 1 says a mistake never
penalises; a silent slot is not evidence of a wrong stroke, it is absence of
evidence. So a missed slot contributes nothing and the mission simply needs more
repetitions. That follows from rule 1 rather than adding a new rule.

## 4. How a mission becomes a real exercise (NEEDS REVIEW)

The curriculum never builds exercise content. A mission carries a
`PracticeGoal` (existing type, with `PracticeGoalType` and `GoalPriority`) and
a `SuccessCriteria`. Starting it builds a `PracticeGenerationRequest` and hands
it to the existing `generation_orchestrator`, which already:

- reads the catalogue through `PracticeCatalogReader`
 (revisioned snapshot, so a run records its provenance);
- aggregates evidence via `evidence_aggregator` and the `skill_snapshot_reader`
  port;
- applies `ProgressionRule` / `ProgressionStep` to make the next attempt harder
  or easier;
- validates with `PlanValidationIssue`.

Required exercise capabilities come from the existing
`ExerciseCapability` enum — notably `supportsDirectionScoring` already exists,
so the rhythm pillar has a capability slot rather than needing a new one. A
mission whose required capability is unsupported must be surfaced as
unavailable, never silently substituted.

**Content sources, in the order the user chose:** generated exercises are the
backbone; the learner's own songs (existing `song_trainer` + importers) provide
`songPerformance` missions; licensed repertoire is out of scope here.

## 5. Gamification wiring and testing (NEEDS REVIEW)

**Wiring — additive only.** The existing `gamification` feature already has
`activity_event_ingestor`, `achievement_evaluator`, `mastery_evaluator`,
`reward_policy_engine`, `streak_service`, and a `gamification_plan_adapter` in
`practice_generator`. The curriculum emits the same activity events those
consume; it does not introduce a parallel XP system. `progress_v2` already has
`skill_detail_projection`, which is where "measured vs not measured" belongs.

**Testing, per `AGENTS.md` §9 and the repo's own habits:**

- **Pure-domain unit tests** for the unlock evaluator: every
  `SkillEstimateState` against every gate, including that `stale` and
  `conflicted` never open a rung.
- **A property test** that the ladder is well-formed for any course version:
  no rung unlocked by itself, no cycle, every mission's required capability
  declared, every `SuccessCriteria` non-vacuous.
- **An honesty test** — the one that matters most: assert that no
  curriculum-emitted learner-facing negative judgement can be produced from a
  non-`confirmed` decision. This is the machine form of rule 2.
- **A pedagogy-ordering test**: the shipped course's chord order matches the
  documented, sourced order (Em before Am before D before C/G; no barre in
  stage 1). This pins §1.1 so a later edit cannot quietly reorder the teaching
  without the test and the sources disagreeing.
- No golden/pixel tests in the first slice; the domain lands before any UI.

## 6. Deliberately NOT in this design

- Licensed song repertoire.
- Sheet-music reading and fingerpicking tracks (Yousician has them; out of
  scope until the spine exists).
- Leaderboards or any social comparison.
- A second XP currency.
- Any change to the DSP engine. The recognition work of E18-R06/R07 is done and
  this layer only consumes it.

## 7. Open risks

- **Recogniser accuracy at scale is unverified.** The 82-recording /
  11 767-event `ml/data/klangio` baseline lives outside the repo, so chord
  accuracy is measured on seven recordings plus synthetic fixtures. A curriculum
  that gates on recognition inherits that uncertainty. Rules 1–3 bound the
  DAMAGE (never a false accusation, never a penalty) but not the FRICTION.
- **No minor chord is measured on real audio** — all seven reference recordings
  are major, yet rungs 3–5 teach Em and Am. This is a concrete gap between what
  the curriculum teaches first and what the engine is verified on, and it should
  be closed by recording real Em/Am/Dm before those rungs ship.
- **The parallel right-hand / chord start (§1.1) is a choice, not a consensus.**
  If learner data later shows it splits attention, the ladder's version field is
  what allows a re-order without invalidating earned progress.
