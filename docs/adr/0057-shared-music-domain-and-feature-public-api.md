# ADR 0057 — Shared music domain in `core/`, feature access through `public.dart`

- **Status:** Accepted
- **Date:** 2026-07-29
- **Round:** E01-R10 (SDD Ch2, Kör 10) — A-part (music domain + feature public API).
  The B-part (shared WAV codec + architecture guard) is recorded in
  [ADR 0058](0058-shared-wav-codec-and-architecture-guard.md).
- **Required by:** SDD Ch2 Kör 10 §10.1–10.5. §10.5 additionally requires an ADR
  for anything that stays on the architecture-guard allowlist.

## Context

`Chord`, `Strum`, `StrumDirection` and `ChordEvent` lived in
`lib/features/live/model/`, and `GuitarString`/`Tuning` in
`lib/features/tuner/model/` — but by round 215 they were consumed by nine
features (Songs, Setlists, Learn, Streak, Share, Library, Analyze,
Diagnostics, Live). "Live's model" had become the app's musical vocabulary
while still living behind a feature's private door, so:

- every new feature deepened the dependency on Live's internals;
- the models imported `package:flutter/foundation.dart`, so the domain could
  not be reasoned about (or tested) without Flutter;
- there was no boundary to enforce — any file could reach into any other
  feature's `screens/`, `providers/` or `engine/`, and 114 import statements
  across 43 files did exactly that.

## Decision

### 1. `lib/core/music/` is the canonical musical domain

`Chord`, `ChordEvent`, `Strum`, `StrumDirection`, `GuitarString`,
`GuitarStrings`, `Tuning` and `Tunings` moved there unchanged. The barrel
`core/music/music.dart` exports the set.

The domain is **Flutter-free**: `@immutable` now comes from `package:meta`
(added as a direct dependency for exactly this reason) instead of
`package:flutter/foundation.dart`. Keeping the annotation matters more than
avoiding the dependency — dropping it would have silently retired the lint
that stops a mutable field appearing in a value object every consumer
compares by value.

### 2. What deliberately did NOT move

- **`BeatSlot`** (was in `strum.dart`) stayed in Live as
  `features/live/model/beat_slot.dart`. It models one slot of the Live beat
  counter; nothing outside Live counts beats that way. A shared domain is
  the set of types other features can *reasonably* consume, not everything
  that happens to sit in the moved file.
- **`LessonTiming`** is listed by §10.1 as a migration candidate ("general
  lesson timing value objects, if not Learn-specific"). It is defined in
  terms of `Lesson` events, not general music theory, so it stays in Learn
  and is reachable through `features/learn/public.dart` — which is what its
  one external consumer (Share's strum reel) needs.
- **The Live DSP/ML engine.** §10.3 explicitly forbids moving the DSP in one
  step. Only `SlidingFramer` crossed into `core/audio/dsp/`: it is used by
  both the Live pipeline and the Tuner engine, has no UI or provider
  dependency, and the move came with a direct test (it previously had only
  indirect pipeline-level coverage — the bar §10.3 sets).

### 3. Old paths stay valid for one transition period

Each moved file left a `@Deprecated` re-export shim behind (§10.2), so a
consumer that was missed still compiles. Every `lib/` and `test/` consumer
in the repository was migrated in this round, so the shims are currently
load-bearing for nothing but the compatibility test that pins them
(`test/core/music/legacy_import_compat_test.dart`, which also asserts a shim
re-exports the canonical type rather than redeclaring it). They are expected
to be **deleted** in a later round; that deletion is the signal the migration
is complete, and it must be a deliberate commit rather than a side effect.

### 4. Cross-feature access goes through `features/<x>/public.dart`

Eleven features gained a `public.dart` (Auth already had one from E01-R08),
each exporting only the files other features actually consume, with the
reason documented per entry. All 114 cross-feature import statements were
repointed at those boundaries — except the exception below.

Entries export whole files rather than `show`-lists (unlike Auth's). Private
declarations do not cross a library boundary anyway, so the practical surface
is the same; narrowing to explicit `show` clauses is a follow-up, not a
correctness gap.

### 5. Accepted allowlist entry: `analyze → live/engine/**`

`ClipAnalyzer`, `MlChordDecoder` and the analyze providers keep importing the
Live DSP/ML engine directly (12 import statements, 10 files). This is
recorded on the architecture-guard allowlist rather than routed through
`live/public.dart`.

**Why not just export them?** Because `public.dart` is a promise. Those files
are scheduled to move to a shared `core/audio/dsp` boundary in a later round
(§10.3); publishing them now would declare a stable contract for code we
intend to relocate, and would make the eventual move a breaking change for
an API we advertised. An allowlist entry says "known debt, shrinking"; a
public export says "this is where it lives". Only the second one lies.

Per §10.5 the allowlist may only shrink; adding to it needs its own ADR.

## Consequences

- The musical vocabulary has one definition, testable without Flutter.
- Adding a feature no longer means importing Live's internals.
- The architecture guard (ADR 0058) can be enforced from a near-empty
  allowlist instead of a 114-entry one nobody would ever pay down.
- `meta` becomes a direct dependency (it was already present transitively).
- Two follow-ups are recorded, not fixed here: narrowing the `public.dart`
  exports to `show`-lists, and dissolving the `analyze → live/engine`
  allowlist entry when the DSP boundary moves.

## Alternatives considered

- **Leave the models in Live and export them via `live/public.dart`.**
  Cheaper, but it keeps the app's shared vocabulary owned by one feature —
  Songs would still depend on Live to describe a strum pattern that never
  touches the microphone.
- **Move the whole DSP in this round.** Explicitly ruled out by §10.3, and
  it would have put a large behaviour-critical diff (DSP parity) in the same
  PR as a mechanical import migration — un-reviewable as one unit.
- **Drop `@immutable` instead of adding `meta`.** Zero dependency change, but
  it removes a real check from exactly the files we just declared canonical.
