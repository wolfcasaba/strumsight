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

| rung | goal | measured by |
|---|---|---|
| 1 | tuning + posture | nothing (and it says so) |
| 2 | right hand: muted strings, **down only**, quarter notes | strum direction + timing |
| 3 | first shape: **Em**, one strum per chord | chord, and whether it rings clean |
| 4 | second shape: **Am** (shares Em's shape) | chord |
| 5 | **Em↔Am change**, slow, one strum | chord change |
| 6 | right hand: **down-up** eighths on muted strings | strum direction |
| 7 | **D**, then Em→D and Am→D | chord change |
| 8 | change **without stopping the strum** | direction + continuity |
| 9 | **C**, **G** (harder shapes) | chord |
| 10 | first pattern: `↓ ↓↑ ↑↓↑` | direction + pattern |

**Sources and what they settle.** Em first: two fingers and all six strings
ring. First batch Am, C, D, Em, G. Early practice is two chords, slow switching,
**one strum per chord with no strumming pattern yet**. The difficulty is the
TRANSITION, not the shape. The key skill is moving between shapes **without
stopping the strum** — which is rung 8, and which StrumSight can actually
measure, unlike a chord-only recogniser.

- [Musicademy — how to teach beginners guitar](https://www.musicademy.com/blog/how-to-teach-beginners-guitar-a-new-approach/)
- [School of Rock — guitar chords for beginners](https://www.schoolofrock.com/resources/guitar/guitar-chords-for-beginners)
- [National Guitar Academy — chord learning program drills](https://nationalguitaracademy.com/wp-content/uploads/2016/01/NGA-Chord-Learning-Program-Practice-Drills.pdf)
- [Acoustic Life — transitioning Am, Dm, Em](https://acousticlife.tv/guitar-for-beginners/minor-chords-a-d-and-e/)

C and G come late on purpose (the sources group them with the harder shapes) and
the barre F is not in this stage at all.

**An honest fork, not silently resolved.** Some schools isolate the right hand
first (muted rhythm), others start with a chord shape and a single strum. Both
are established. This ladder runs them in PARALLEL from the start (rungs 2 and
3), because they train different hands and the app can measure both. That is a
choice, not a consensus.

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
