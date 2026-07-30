# ADR 0066 — Musical time in Practice V2 is an integer tick (480 PPQ), not a `double` beat

- **Status:** Accepted
- **Date:** 2026-07-30
- **Round:** E02-R01 (SDD Ch3, Kör 1 §1.1) — decided here, implemented in E02-R02.
- **Required by:** SDD Ch3 §9.1, §14.2, Kör 2.
  Rollout context: [ADR 0065](0065-practice-engine-v2-parallel-rollout.md).

## Context

Today a lesson event's musical position is `double beat`
(`lib/features/learn/model/lesson.dart`), at eighth-note resolution: the pattern
expander emits `bar * beatsPerBar + slot * 0.5`, so positions are `x.0` or
`x.5` and the values are exactly representable in binary floating point.

That is why nothing has broken yet. It stops being true the moment Epic 2 adds
what SDD Ch3 §9.1 requires: sixteenths (`0.25` — still exact) and **eighth-note
triplets** (`1/3` — not representable). Once a triplet exists, two things that
are musically the same position can compare unequal, `events.sort()` becomes
order-sensitive to accumulated error, and a `Map<double, …>` keyed by position
silently grows duplicate keys.

The existing code already leans on `double` equality in exactly the way that
breaks: `Lesson.simplified` selects on-beat strokes with `e.beat % 1.0 == 0`.

## Decision

### 1. `BeatPosition` stores integer ticks at 480 PPQ

```dart
final class BeatPosition implements Comparable<BeatPosition> {
  static const int ticksPerBeat = 480;
  final int ticks;
}
```

480 ticks per quarter note divides exactly by 2, 3, 4, 6, 8, 12 and 16, so every
subdivision Epic 2 supports is an integer:

| Value | Ticks |
|---|---|
| quarter | 480 |
| eighth | 240 |
| sixteenth | 120 |
| eighth triplet | 160 |
| quarter triplet | 320 |

Equality, ordering, addition and subtraction are integer operations. Two
positions are equal when they are musically equal, with no tolerance argument
anywhere.

### 2. No `double` beat positions in the Practice domain

`double` is still the right type for *durations in seconds* on the scoring side
(observations, windows, offsets) — those come from a clock and are inherently
approximate. The rule is about *musical* position only: nothing in
`lib/features/practice/domain/` stores or compares a beat as a `double`.

### 3. Negative positions are rejected; count-in is a session concept

A `BeatPosition` below zero is invalid. The count-in is not "negative beats" in
the target timeline — it is a duration the compiled target carries
(SDD Ch3 §14.1), which keeps the definition independent of how many count-in
bars a given session was configured with.

### 4. Persistence stores ticks

JSON keeps integer ticks, not beats. A stored `240` is unambiguous forever; a
stored `0.5` would have to be re-derived through whatever the reading build
believes the resolution is.

### 5. The legacy bridge is one audited conversion with a measured tolerance

`Lesson.beat` → `BeatPosition` happens in exactly one helper. `beats * 480` is
rounded, and the round-trip deviation is asserted, not assumed: the E02-R05
lesson adapter proves that every one of the 16 built-in lessons converts with
zero deviation, and the tolerance for imported (Analyze-derived) content —
where beats are computed from detected onset times and are genuinely fractional
— is documented at the conversion site.

## Consequences

- Triplets, sixteenths and mixed subdivisions become expressible without any
  epsilon comparison in the domain.
- The scorer's inputs are exact; only the observation side carries measurement
  error, which is where it belongs.
- One conversion boundary exists (legacy `double` → ticks) and it is tested,
  rather than an implicit `double` contract spread over adapters.
- 480 PPQ is a convention, not a physical limit: it is documented in the class
  and asserted by tests so nobody "optimises" it to 96 and silently loses
  triplet precision.

## Alternatives considered

- **Keep `double` beats, compare with an epsilon.** Every consumer would have to
  remember the epsilon, and "which epsilon" becomes a per-site decision. The
  first one that forgets produces a duplicate target at the same position.
- **Rational number type (numerator/denominator).** Exact for every subdivision,
  including ones 480 PPQ cannot express — but it needs normalisation, has no
  natural JSON form, and no sequencer format in the wild uses it. Ticks are what
  MIDI, DAWs and every notation format already agreed on.
- **960 or 192 PPQ.** 960 buys nothing Epic 2 needs; 192 does not divide evenly
  by 16ths against triplets. 480 is the MIDI-standard middle ground.
