# E03-R22 Independent Review — Setlist V2, progress integration & Epic-3 closure

- **Reviewer:** Claude Opus 4.8 (independent, read-only per ADR 0055 / `sdd-round-review`)
- **Branch:** `codex/e03-r22-setlist-progress-epic-closure` @ `e2607e3` (base `origin/main` @ `3a5762a`)
- **Isolated clone:** `/tmp/review-e03r22` (no production file edited except disposable mutations, each reverted)
- **Date:** 2026-08-04

## Verdict: **CHANGES REQUESTED**

One BLOCKER (red local gate — real test regression) and one MAJOR (non-discriminating
matrix invariant). Scope, provenance gate, schema gate and completion-report honesty
are all clean, and every central invariant probed turns RED under a real fault.

---

## BLOCKER

### B1 — Local round gate is RED: production wiring change breaks a pre-existing (out-of-scope) test

After generating l10n (`flutter gen-l10n`, required because the generated
`lib/l10n/app_localizations.dart` is gitignored), the mandatory gate runs
`format → analyze → test → architecture`:

```
tools/round-gate.sh test/features/song_trainer test/features/songs test/features/practice test/property
  format:   ZÖLD
  analyze:  ZÖLD (No issues found!, 9.8s)
  test test/features/song_trainer:  PIROS (kilépési kód 1)   → +464 ~1 -1
GATE_EXIT=10
```

Failing test (NOT in the round's `allowed_paths`, so it cannot be patched here):

```
test/features/song_trainer/application/trainer/song_trainer_controller_test.dart:
  "playback-only provider does not read the microphone permission provider"  [E]

ProviderException: UnimplementedError: keyValueStoreProvider must be overridden
  storage_providers.dart:14
  → practiceHistoryRepositoryProvider (local_practice_history_repository.dart:242)
  → songProgressSessionRecorderProvider (song_trainer_providers.dart:438)
  → songProgressCommitterProvider (song_trainer_providers.dart:422)
  → songTrainerControllerProvider (song_trainer_providers.dart:410)
  → song_trainer_controller_test.dart:175 (container.read, no keyValueStore override)
```

**Root cause (this round's diff).** `song_trainer_providers.dart` changed
`songProgressSessionRecorderProvider` from a dependency-free
`const NoopPracticeSessionRecorder()` to
`PracticeHistoryRecorder(repository: ref.watch(practiceHistoryRepositoryProvider), …)`
(`song_trainer_providers.dart:434-449`). That recorder is transitively watched by
`songProgressCommitterProvider` → `songTrainerControllerProvider`, so **constructing the
Song Trainer controller now eagerly builds the practice-history repository**, which
requires `keyValueStoreProvider` to be overridden. The pre-existing R21 test read the
controller without that override because, before R22, the recorder was a Noop with no
deps.

**Why this is a BLOCKER, not an environment artifact.** The failure is a deterministic
`UnimplementedError` (not flakiness, not inotify, not the missing generated l10n). The
implementer's handoff (§10) reported only the box's inotify exhaustion at the analyze
step and never reached the test step, so this regression was never surfaced. The merge
bar is "every gate green"; it is not.

**Design ripple (informs the fix, not a separate finding).** The failing test encodes the
intent that the *playback-only* Song Trainer path is lightweight. The new wiring makes even
the playback-only controller eagerly construct the practice-history repository. The fix
should keep that path lazy (e.g. defer the recorder construction, or give
`songProgressSessionRecorderProvider`/`keyValueStoreProvider` a test-safe default) rather
than merely widening test overrides — and since the affected test is outside
`allowed_paths`, resolving it needs a brief-revision / scope decision by the orchestrator.

---

## MAJOR

### M1 — "playback-only → streak credit 0" is validated against a test double, not production

The §6 matrix row *"playback-only → streak credit 0"* is asserted by
`song_progress_public_integration_test.dart` → *"playback-only terminal leaves streak
credit at zero"*, but that test exercises a **`_CountingCreditRecorder` double that
reimplements the guard** (test lines 120-139). The production
`PracticeSessionSongCreditRecorder.record` guard
(`song_progress_aggregator.dart:224-230`) has **no test reference at all**
(`grep -rn PracticeSessionSongCreditRecorder test/` → 0 hits).

**Mutation proof (disposable, reverted).** Removing the production guard
`if (record.playbackOnly) { return const SongPracticeCreditOutcome(streakCredited:false, dailyGoalActiveSeconds:0); }`
and running the two integration/wiring suites:

```
flutter test test/features/song_trainer/integration/song_progress_public_integration_test.dart \
             test/features/song_trainer/data/local/song_progress_wiring_test.dart
→ All tests passed!  (3/3 GREEN — fault NOT caught)
```

A central matrix invariant on the production path is non-discriminating. Add a test that
drives the real `PracticeSessionSongCreditRecorder` (via `songPracticeCreditRecorderProvider`
or directly) with a `playbackOnly: true` record and asserts `streakCredited == false` /
`dailyGoalActiveSeconds == 0`.

---

## MINOR

### m1 — Property test ignores `PROPERTY_SEED` (HORIZON anti-reward-hacking convention)

`test/property/song_progress_property_test.dart:10` hardcodes `const seed = 20260804` and
never reads `PROPERTY_SEED`. CLAUDE.md's HORIZON convention requires `test/property/` to
read `PROPERTY_SEED` (absent → 42) so CI's HARD step can run
`PROPERTY_SEED=${{ github.run_id }}`. As written the CI randomized step cannot vary this
test's seed — the anti-reward-hacking randomization is inert. (The property itself *is*
discriminating — see probe P1 below — but the seed is fixed.)

---

## NOTE

- **N1** — The gate is reproducible in a fresh clone only after `flutter gen-l10n`
  (`app_localizations.dart` gitignored). The implementer's inotify-exhaustion report is
  an environment issue, orthogonal to B1.
- **N2** — `docs/adr/0130-*.md` appears in the branch diff but is the orchestrator's
  pre-flight commit (`docs(e03-r22): pre-flight — ADR 0130 …`), not an implementer scope
  violation (brief §0.0 pt.7).

---

## Scope re-audit — CLEAN

Every changed file is within brief §4 `allowed_paths`. `lib/` changes are limited to
`song_trainer/**`, `features/progress/public.dart`, `features/practice/public.dart`, and
the two l10n ARBs. Cross-feature barrels are **additive-export only**:

- `progress/public.dart`: `+export 'providers/daily_goal_provider.dart';` (only add) ✓
- `practice/public.dart`: `+export` of history repo provider / recorder / mapper (only adds) ✓
- `streak/public.dart`: **UNCHANGED** (credit entrypoint already exported; correct) ✓

No internal cross-feature imports from song_trainer; daily-goal reached via the barrel
(`song_trainer_providers.dart:455` `progress.dailyGoalProvider`).

## Provenance gate — HONEST

`tool/ci/check_song_fixture_licenses.dart`: `Song fixture provenance OK (30 fixtures)`,
matching 30 files on disk (`find test/fixtures/song_trainer -type f ! -name README.md | wc -l` = 30).
- (a) enumerates every fixture recursively (excludes README) ✓
- (b) verifies SHA-256 per fixture against the inline manifest ✓
- (c) fails on a disk fixture missing from the manifest — **proven**: adding
  `native/interloper.json` → `dart run … ; exit 1` with
  `"fixture has no provenance manifest entry"` ✓
- (d) GP entries mirror `guitar_pro/README.md` verbatim, including the MPL-2.0
  `minimal_gpx.gpx` (alphaTab commit `a186437…`, SHA `b437b7a2…`) ✓
- (e) no fabricated hashes — all 30 recomputed and matched ✓

## Schema gate — PASSES

`tool/ci/check_song_schema.dart`: `Song schema snapshot OK (6 persisted schema sources)`;
inline start-marker + SHA-256 slice of codec/importer/exporter/setlist/progress sources.

## Completion report — HONEST

`docs/sdd/epic-03-completion-report.md` opens *"ez nem release approval"*, every capability
row carries an evidence link, and **every** real-device checklist row is named as an
individual release blocker (§"Nyitott release blockerek" pt.4). No aspirational claim
stated as fact; the long-song baseline is explicitly labelled structural, not a device
profile. The un-green local gate is itself listed as an open blocker (pt.5).

---

## Mutation / refutation probes (all disposable, reverted)

| # | Invariant | Mutation | Result |
|---|---|---|---|
| P1 | Aggregate idempotency (unit + property) | `song_progress_aggregator.dart`: replace `unique.putIfAbsent(record.id,…)` with a per-index key (dedup off) | **RED** — `song_progress_test` + `song_progress_property_test` both fail |
| P2 | Revision no-false-transfer | `song_revision_progress_mapper.dart`: `targetCounts[id] != 1` → `== 0` (allow ambiguous) | **RED** — "deleted or ambiguous … archived without false transfer" fails |
| P3 | Terminal exactly-once | `song_progress_aggregator.dart`: disable `_commits` cache early-return | **RED** — "duplicate terminal callback … once" fails (`saves` expected 1) |
| P4 | Setlist order / duplicate / skip | `setlist_session_controller.dart`: `results.add` → `results.insert(0,…)` | **RED** — duplicate-order + missing-skip tests fail |
| P5 | Performance = playback-only (no scoring runner / mic 0) | `setlist_session_screen.dart`: Performance branch uses `_practiceRunner()` | **RED** — "Performance never constructs the lazy scoring runner" fails |
| P6 | Playback-only streak-0 on **production** recorder | `song_progress_aggregator.dart`: remove production `playbackOnly` guard | **GREEN (fault uncaught) → M1** |

Exact commands per probe are recorded in the review session transcript; each ran as
`flutter test <single file(s)>` (never chained with analyze) and was reverted with the
saved `.bak`.

---

## Summary

Setlist V2, revision-aware progress, the aggregator/mapper, the two CI gates, and the
completion report are well-built, in-scope, and backed by genuinely discriminating tests
(P1-P5). Two things block merge: **B1** the local gate is RED because this round's
`songProgressSessionRecorderProvider` rewiring makes the Song Trainer controller eagerly
require `keyValueStoreProvider`, breaking a pre-existing out-of-scope test; and **M1** the
production playback-only streak-credit guard is untested (only a double is). Fix B1 without
weakening the "playback-only is lightweight" contract the failing test encodes, add M1's
production-path test, and address m1's `PROPERTY_SEED` wiring, then re-run the full gate.
