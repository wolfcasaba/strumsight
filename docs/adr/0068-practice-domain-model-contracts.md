# ADR 0068 — Practice V2 domain model contracts: validation-as-value, integer percents, canonical chord labels

- **Status:** Accepted
- **Date:** 2026-07-30
- **Round:** E02-R03 (SDD Ch3, Kör 3) — decided here, implemented in the same round.
- **Required by:** SDD Ch3 §8.3, §10.1–10.9, §15.2, §16.1–16.8, Kör 3.
  Time model: [ADR 0066](0066-practice-tick-time-model.md).
  Rollout context: [ADR 0065](0065-practice-engine-v2-parallel-rollout.md).
  Learn migration: [ADR 0067](0067-practice-gradual-learn-migration.md).

## Context

E02-R02 landed the musical-time value objects (`BeatPosition`, `Tempo`, `Meter`)
plus a small aggregating validation type. E02-R03 adds the ~13 remaining
domain contracts (event, definition, session config, observation, verdict,
metrics, attempt/session result, scoring profile, mode/source/difficulty
enums). Every later Epic-2 round — catalog (Kör 4), adapters (Kör 5), target
compiler (Kör 6), state machine (Kör 7), matcher/scorer (Kör 9–10), persistence
(Kör 18) — is written against these types, and Kör 18 persists them. Four
cross-cutting questions therefore have to be answered once, here, instead of
being re-litigated per round:

1. **Where does invalid data get rejected** — constructor exception or value?
   The legacy scorer has no validation layer at all; the adapters (Kör 5) import
   third-party-shaped data (lesson, song, analyze) that *will* be malformed, and
   they need to see *all* problems to decide clamp-vs-reject
   ([ADR 0065](0065-practice-engine-v2-parallel-rollout.md) parity work).
2. **What numeric type carries scores, weights and thresholds.** SDD Ch3 §16.6
   gives weights as percentages that must sum to 100% and §16.7 gives pass
   thresholds as `0.85`/`0.70`. A `double` weight-sum check needs an epsilon —
   the exact failure mode [ADR 0066](0066-practice-tick-time-model.md) removed
   from musical time.
3. **What a "normalized chord label" is.** SDD Ch3 §10.3 requires target chords
   to be "normalized label or null", but the repo has no normalizer: the DSP
   matcher and the CRNN decoder both emit sharp-spelled major/minor labels
   (`lib/features/live/engine/dsp/chord_matcher.dart:24-35`,
   `lib/features/analyze/engine/ml_chord_decoder.dart:41-66`), while Learn
   lessons use `''` for a muted/strum-only stroke
   (`lib/features/learn/model/lesson.dart:22-23`).
4. **How immutable aggregates that hold lists compare.** Dart `List` `==` is
   identity, so a naive `PracticeDefinition ==` would report two structurally
   identical definitions as different — and Kör 4 wants `const` catalog data.

## Decision

### 1. Validation is a value, not an exception (data-driven paths)

Every aggregate exposes `List<PracticeValidationFailure> validate()` which
**aggregates** all problems (empty list = valid) and never throws, following the
`AppConfig.resolve` `problems` pattern already used in
`lib/core/config/`. Constructors do **not** validate. `PracticeValidationFailure`
(E02-R02) stays the single failure type, with stable
`<type>.<field>.<problem>` codes; the domain does **not** depend on
`AppResult`/`AppFailure` (`AppFailure` is sealed —
`lib/core/foundation/app_failure.dart:55`).

Exceptions are reserved for **programmer errors**: a derived getter that cannot
produce a meaningful answer on unvalidated input throws `StateError`, and it does
so **symmetrically for every field it depends on** (this closes the E02-R02
review MINOR-1: `Meter.ticksPerBar` used to fail fast on `beatUnit` but silently
return `0` for `beatsPerBar == 0`). Callers validate first; `BeatPosition`'s
existing `ArgumentError` on negative ticks is unchanged (ADR 0066 §3).

### 2. Weights, thresholds and windows avoid `double` comparison

- Scoring **weights** are `int` percents keyed by dimension and must sum to
  **exactly 100** (or be empty for a mode without an overall score). No epsilon,
  no normalization pass.
- **Pass thresholds** are `int` percents (`0…100`): §16.7's `0.85`/`0.70`
  becomes `85`/`70`.
- **Match windows** are `Duration` (integer microseconds), so §15.2's
  `±280/50/120 ms` is exact and ordering (`perfect ≤ good ≤ match`) is an
  integer comparison.
- Computed **scores** stay `double` in `0.0…1.0` — they are the output of
  interpolation (§16.3) and cannot be integers — but they are always carried by
  the `MetricValue` sealed hierarchy (`available` / `notApplicable` /
  `insufficientData`), never by a bare nullable `double`, and are validated as
  finite and in range.

### 3. Canonical chord label = sharp-spelled major/minor; normalization happens at the adapter

The domain's canonical label set is the 24 labels
`{C, C#, D, D#, E, F, F#, G, G#, A, A#, B} × {"", "m"}` — exactly the detector
vocabulary minus `N.C.`. `null` means "no chord target" (target side) or "no
chord detected" (observation side); the empty string is **invalid**. Flat
spellings (`Bb`), `N.C.`, and richer qualities (`7`, `sus4`, `maj7`) are invalid
*in the domain*; mapping them — flat→sharp, `N.C.`→`null`, Learn's `''`→`null`,
unsupported quality→reject — is the job of the Kör-5 adapters and the Kör-8
observation gateway, which is where the source-specific knowledge lives. The
domain therefore has exactly one predicate, and detector output compares to a
target with plain string equality.

### 4. `const` constructors + explicit deep equality; lists are immutable by contract

Aggregates keep `const` constructors (Kör 4's built-in catalog is `const` data)
and implement `==`/`hashCode` **structurally**, comparing list fields
element-wise via a small local helper (`Object.hashAll` for the hash). No
`package:collection` — no new dependency for four lines of code. Passing a
mutable list in is a caller bug: the doc comment states the contract ("the list
must be immutable — use a `const` list or `List.unmodifiable`"), the domain never
mutates a list it was given, and every list-returning member is documented as
read-only.

### 5. Persisted enums carry a stable string code

Every enum that can reach storage or a wire format (`PracticeMode`,
`PracticeSource`, `PracticeDifficulty`, `TimingGrade`, `PracticeFinishReason`,
`PracticeAttemptOutcome`, extra-strum policy, score dimension) exposes a
`code` string that is **independent of the Dart identifier order and name**, plus
a strict `…FromCode(String)` lookup that returns `null` for an unknown code
(never throws, never falls back to a default). Renaming or reordering enum
values must not change a stored code — a test pins every code literal, so a
rename that changes the wire format fails the suite.

### 6. The domain stays pure — machine-checked

No Flutter/Riverpod/Dio/storage/l10n import (already enforced for
`lib/features/practice/domain/` by `tool/check_architecture.dart` since E02-R02),
and additionally **no ambient non-determinism or IO**: `DateTime.now()`,
`Stopwatch()`, `Random()` and `print()` may not appear in the domain source
(SDD Ch3 §8.3). Timestamps and durations are injected as fields. A source-scanning
test in `test/features/practice/domain/` enforces this — deliberately in test
space, not in the CI architecture gate, so a false positive cannot break the
merge gate for unrelated work.

## Consequences

- Adapters (Kör 5) get the full problem list and own the clamp-vs-reject policy;
  the domain never silently repairs data.
- `Kör 4` can express the whole built-in catalog as `const` data with working
  value equality, and `Kör 18` can serialize enums without a mapping table.
- Weight/threshold arithmetic in the scorer (Kör 10) is integer-exact; only the
  final interpolated scores are `double`.
- Song import (Kör 5) must normalize flats before constructing events, and will
  reject qualities beyond major/minor until the vocabulary is widened — an
  explicit, testable boundary rather than a silent mismatch at scoring time.
- The strict `fromCode` means an unknown persisted code surfaces as `null` and
  the caller must decide (quarantine, drop) — consistent with the versioned
  storage migrator's quarantine behaviour (Epic 1).

## Alternatives considered

- **Throwing constructors.** Rejected: the first malformed adapter input would
  crash a practice session, and callers could not report *all* problems.
- **`double` weights summing to 1.0 with an epsilon.** Rejected for the reason
  ADR 0066 gives for musical positions: epsilon comparisons spread through
  every consumer.
- **A full chord parser (root + quality) in the domain now.** Rejected as
  premature: Epic 2 scores major/minor targets only (SDD Ch3 §7), and a parser
  would have to guess enharmonic policy before any importer exists. The label
  predicate is a one-line replacement point when Epic 3 widens the vocabulary.
- **`package:collection`'s `ListEquality`.** Rejected: a new direct dependency
  for a four-line helper, against the round's no-new-package rule.

## References

- SDD Ch3 §8.3 (code-quality rules), §10.1–10.9 (models), §15.2 (match window),
  §16.1–16.8 (scoring), Kör 3.
- [ADR 0066](0066-practice-tick-time-model.md) — integer tick time model.
- E02-R02 review MINOR-1: [`docs/reviews/e02-r02-review.md`](../reviews/e02-r02-review.md).
