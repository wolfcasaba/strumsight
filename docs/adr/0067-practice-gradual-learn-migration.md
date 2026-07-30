# ADR 0067 — Learn migrates to Practice V2 only against a frozen parity baseline

- **Status:** Accepted
- **Date:** 2026-07-30
- **Round:** E02-R01 (SDD Ch3, Kör 1 §1.1, §1.3, §1.4)
- **Required by:** SDD Ch3 §3.3, §25.3.
  Rollout mechanism: [ADR 0065](0065-practice-engine-v2-parallel-rollout.md).

## Context

Epic 2 replaces `LessonScorer` with a multi-dimensional scorer. `LessonScorer`
is not a specification — it is an accumulation of tuning decisions made against
a real guitar over ~200 rounds: a ±280 ms match window, 50/120 ms perfect/good
tiers, a 370 ms chord-lag tolerance, extra strums deliberately unpunished,
combo tiers at 5/10/20, a 0.7 pass mark, an Easy cut offered after four
consecutive failures.

None of that is written down anywhere except in the code. If the V2 scorer is
built from the SDD's proposed tempo-aware formulas alone, the first real-device
session will feel different from today's — and nobody will be able to say
whether that is an improvement or a regression, because there is no record of
what "today" scored.

## Decision

### 1. Today's behaviour is frozen as a golden fixture set before anything is built

E02-R01 records the current `LessonScorer` against a fixed scenario set — 4/4
pattern, 3/4 waltz, all-perfect, all-late, wrong direction, extra strums, chord
lag, input latency, de-jittered timestamps — into a checked-in JSON golden, plus
the scenario definitions in shared test code that later rounds replay against
the V2 engine.

The golden is a **record, not a wish**. It is generated from the current code and
frozen. It is not edited to make a later round green.

### 2. The `legacyLearn` scoring profile must reproduce the golden exactly

V2 ships a `legacyLearn` `ScoringProfile` pinned to the recorded constants
(280 / 50 / 120 ms, extra-strum `ignore`, the existing input-latency semantics).
Replaying the frozen scenarios through V2 with that profile must produce the
same hits, wrong-directions, misses, timing tiers, combo, max-combo and chord
tallies as the golden (SDD Ch3 §25.3).

### 3. A deviation needs its own ADR

Any documented difference between the legacy engine and the `legacyLearn`
profile — including "the golden captured a bug and V2 fixes it" — is recorded
in a new ADR that states the scenario, the old value, the new value and the
reason. A deviation may not be absorbed by editing the golden.

### 4. `migratedLearnEnabled` may only be turned on when all four hold

1. the parity replay is green for every frozen scenario;
2. every deviation has an accepted ADR;
3. the user has played the migrated path on a real guitar and accepted it
   (HORIZON: synthetic green is never "done", CLAUDE.md);
4. the legacy path is still present and can be restored by flipping the flag
   back.

### 5. Known gaps are documented, not frozen

Some of today's behaviour is a gap Epic 2 is meant to close — most concretely,
`LearnScreen._pause()` stops the ticker but neither closes the mic subscription
nor guards `_onFrame`, so strums that arrive while paused are still scored, at
the frozen elapsed time (SDD Ch3 §6.1 requires the opposite).

Such behaviour is written into the baseline report as a known gap with the
round that closes it. It is deliberately **not** asserted in the golden: a green
test that pins a bug turns the fix into a test edit, and a test edit is exactly
what makes a parity suite stop meaning anything.

### 6. Nothing in Learn changes while the baseline is being taken

E02-R01 makes no production change to `lib/features/learn/` or its behaviour. If
recording the baseline surfaces a defect, it is reported and scheduled — not
fixed in the round whose only job is to describe the starting point.

## Consequences

- Every later Epic-2 round has an objective answer to "did I change scoring?".
- The tuning knowledge embedded in `LessonScorer` survives the rewrite as data,
  not as folklore.
- The golden must be regenerated deliberately if the legacy engine ever changes
  on purpose; that regeneration is a reviewable commit with a stated reason.
- The parity suite is a cost on every V2 scoring round. That is the point.

## Alternatives considered

- **Port `LessonScorer` line by line into V2.** Preserves behaviour by
  construction, but carries the design that Epic 2 exists to replace (one
  combined verdict, chord as a side counter, `double` seconds) into the new
  domain.
- **Accept the SDD's tempo-aware windows as the default immediately.** SDD Ch3
  §15.2 itself forbids this: "a production default csak mérés és parity review
  után válthat a legacy konstansokról."
- **Compare engines only on the real device.** The only test that ultimately
  matters, but it cannot run per commit, and it cannot tell a 3 ms window drift
  from a bad take.
