# ADR 0065 — Practice Engine V2 runs beside the legacy Learn engine, behind availability flags

- **Status:** Accepted
- **Date:** 2026-07-30
- **Round:** E02-R01 (SDD Ch3, Kör 1 §1.2)
- **Required by:** SDD Ch3 §3.3 (migrációs alapelv), §4.1, Kör 1 §1.2.
  The tick-based time model is [ADR 0066](0066-practice-tick-time-model.md);
  the migration/parity contract is
  [ADR 0067](0067-practice-gradual-learn-migration.md).

> **Numbering note.** SDD Ch3 Kör 1 §1.1 names these documents `0005`/`0006`/`0007`.
> Those numbers are taken in this repository (`0005` does not exist, but `0001`–`0004`
> and `0050`–`0064` do, and the chapter was written against a generic numbering).
> The Epic-2 series therefore continues at **0065**; the SDD filenames are
> superseded by these three.

## Context

Epic 1 delivered a validated core platform, and the app already has a working
play-along experience: `LearnScreen` (839 lines) drives a `LessonScorer` over a
`Lesson`'s beat-timed events. It works, it is tested, and the user has played it
on a real guitar.

It is also a dead end for Epic 2. `LearnScreen` owns twelve responsibilities at
once (ticker, mic subscription, scorer lifecycle, metronome, backing playback,
haptics, expected-chord hint, dynamic difficulty, progress + streak persistence,
navigation, burst animation, UI state), and `LessonScorer` is bound to one
lesson format, one combined hit verdict, and `double` seconds. Epic 2 needs five
practice modes, an attempt/session state machine, a Speed Builder policy, and
per-dimension scoring — none of which fit behind that shape.

The tempting move is to rewrite `LearnScreen` in place. That would put the
app's only proven, real-device-validated scoring path into a large refactor
whose correctness cannot be demonstrated until the whole Epic is finished.

## Decision

### 1. V2 is built beside the legacy engine, not on top of it

The new engine lives in `lib/features/practice/`. `lib/features/learn/` keeps
working, unchanged, for the whole Epic. Nothing in Learn is deleted, and no
Learn behaviour changes, until every condition in
[ADR 0067](0067-practice-gradual-learn-migration.md) is met.

### 2. Three availability flags gate the rollout

Added to the Epic-1 `FeatureFlags` (`lib/app/config/feature_flags.dart`):

| Flag | Meaning | dev / lab | production |
|---|---|---|---|
| `practiceEngineV2Enabled` | the Practice feature (hub, routes, engine) exists in this build | on | off |
| `migratedLearnEnabled` | Learn is served BY the V2 engine instead of `LearnScreen` | off | off |
| `practiceDetailedHistoryEnabled` | the `practice_history_v2` store is written | on | off |

These are *availability* switches in the sense already established by
`diagnosticsEnabled` / `labModeAvailable` (E01-R03): build-level, not user
preferences.

`migratedLearnEnabled` is **off in every environment**, including development.
Turning it on is the explicit rollout decision that ADR 0067 gates, and it must
be a deliberate commit — not something a developer build quietly does first.

### 3. No new `--dart-define` in this round

The existing flags follow a deliberate rule: diagnostics and Lab availability
have no define that can force them on in production, because "a diagnostics
build must not happen by accident". The same reasoning applies here — a
production APK must not be able to serve a half-migrated Learn because a build
argument was pasted wrong. The production rollout switch is a later, explicit
change to `FeatureFlags.forEnvironment` under ADR 0067, reviewed on its own.

### 4. Dependency invariants are fail-closed

`AppConfig.resolve` gains two rules, reported the same way as every other
configuration problem (collected into `ConfigurationException`, never silently
corrected):

```text
migratedLearnEnabled          ⇒ practiceEngineV2Enabled
practiceDetailedHistoryEnabled ⇒ practiceEngineV2Enabled
```

A build that serves migrated Learn from an engine that is not compiled in, or
writes a V2 history no reader is enabled for, is a misconfiguration. It fails at
bootstrap with the failure screen, exactly like a malformed API URL.

### 5. The practice flags never imply network use

`FeatureFlags.usesNetwork` stays `accountEnabled || diagnosticsEnabled`. All
three practice flags may be on with `usesNetwork == false`, and a test asserts
it. Practice is 100 % on-device (ADR 0001, SDD Ch3 §23); a flag that quietly
pulled the app into URL validation would be the first crack in that promise.

### 6. The flags are added without breaking existing call sites

The new fields are optional constructor parameters with defaults. Seven
existing `const FeatureFlags(...)` call sites (five in `app_config_test.dart`,
one each in `app_bootstrap_test.dart` and `diagnostics_providers_test.dart`)
keep compiling untouched, so the diff that introduces the flags stays about the
flags.

## Consequences

- Epic 2 can land round by round without a single round in which the app has no
  working play-along path.
- Every Epic-2 round has a definite answer to "what does production do today?" —
  nothing, until ADR 0067's conditions are met.
- Two engines exist simultaneously for the length of the Epic. That is a real
  maintenance cost, paid deliberately: the alternative is a long-lived branch
  whose merge is a single un-reviewable event.
- The `practiceEngineV2Enabled` flag must eventually be deleted, not left on
  forever. Its removal is the signal the migration finished, and it belongs in
  the Epic-2 closing round.

## Alternatives considered

- **Refactor `LearnScreen` in place, incrementally.** Cheaper in total lines,
  but there is no intermediate state in which the screen is both half-migrated
  and demonstrably correct — and the real-device acceptance predicate
  (HORIZON: synthetic green is never "done") cannot be run on half a screen.
- **One flag instead of three.** Simpler, but it conflates three independent
  decisions: does the code exist, does Learn use it, and do we write a new
  persistence format. They will be flipped at three different times.
- **Feature flag as a runtime user preference.** Rejected: a user toggling
  scoring engines mid-Epic produces history rows nobody can compare, and the
  offline promise is a build property, not a preference.
