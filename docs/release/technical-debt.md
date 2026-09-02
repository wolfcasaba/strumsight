# Technical debt — measured inventory (E12-R35)

**Kör:** `E12-R35` (Technikaiadósság- és flag cleanup). **Mérce:**
`tool/check_deprecations.dart` (`dart run tool/check_deprecations.dart`),
`test/tooling/deprecation_audit_test.dart`.

This is an **audit and backlog**, not a cleanup — this round does not delete
any `lib/` code (round brief §0.1). Every row below is a candidate a future,
dedicated round may act on, gated by its own **removal condition**. A
compatibility layer or flag closes only in a dedicated GOV-style round
([ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)).

## Methodology

- **`@Deprecated` sites and external-importer-file counts** are measured by
  [`findDeprecatedSites`](../../tool/check_deprecations.dart) +
  [`countExternalImporters`](../../tool/check_deprecations.dart): every
  `import`/`export` directive in `lib/` is resolved to a repo-relative path
  (relative imports are walked against their importing file's directory,
  not substring-matched — a naive substring compare undercounts, e.g. it
  found only 6 of the real 17 `lib/features/progress/` importers because
  most reach it via a relative import that never spells out `features/`).
  The count is of importing **files**, not import statements or call sites
  within them — a file that imports the same target three times still
  counts once. A file with **zero** external importers has no in-tree
  consumer left; it is not, by itself, permission to delete it (§5.3 below).
- **Parallel-layer (`*_v2`) external-importer-file counts** are measured the
  same way, at directory granularity (any file importing something under
  `lib/features/<name>_v2/`).
- **TODO/FIXME occurrences** are `grep -rn "TODO\|FIXME" lib/ --include="*.dart"`
  (14 total, 2026-09-02), grouped by the feature area they sit in.
- All counts below are as of **2026-09-02** (`main @ 496264d9`) — re-run
  `dart run tool/check_deprecations.dart` before acting on any row; an
  external-importer-file count can only have gone up or down since.

## §5.3 — supported legacy clients are unaffected

None of the rows below touch the boot-time `appStorageMigrations` chain
(`lib/core/storage/storage_migrator.dart`, 22 steps,
[`client-migration.md`](client-migration.md) §1) or a
[`contract-freeze.md`](contract-freeze.md) `frozen_scope` path — verified by
`A5` in `test/tooling/deprecation_audit_test.dart`.

<!-- technical-debt:begin -->
| Item | Path | Owner | Removal condition | Measured (2026-09-02) |
|---|---|---|---|---|
| `wav.dart` re-export shim (`@Deprecated`, points at `core/audio/codec/wav_codec.dart`) | `lib/features/learn/audio/wav.dart` | `lib/core/audio` (codec ownership) | `dart run tool/check_deprecations.dart` reports 0 external importer files for this file AND a dedicated cleanup round deletes it (this round's §4 forbids `lib/` deletion). | 0 external importer files |
| `guitar_strings.dart` re-export shim (`@Deprecated`, points at `core/music/guitar_strings.dart`) | `lib/features/tuner/model/guitar_strings.dart` | `lib/core/music` | Same condition as the row above, applied to this file. | 0 external importer files |
| `tuning.dart` re-export shim (`@Deprecated`, points at `core/music/tuning.dart`) | `lib/features/tuner/model/tuning.dart` | `lib/core/music` | Same condition as the `wav.dart` row, applied to this file. | 0 external importer files |
| `wav_decoder.dart` re-export shim (`@Deprecated`, points at `core/audio/codec/wav_codec.dart`) | `lib/features/analyze/engine/wav_decoder.dart` | `lib/core/audio` (codec ownership) | Same condition as the `wav.dart` row, applied to this file. | 0 external importer files |
| `sliding_framer.dart` re-export shim (`@Deprecated`, points at `core/audio/dsp/sliding_framer.dart`) | `lib/features/live/engine/dsp/sliding_framer.dart` | `lib/core/audio` (DSP ownership) | Same condition as the `wav.dart` row, applied to this file. | 0 external importer files |
| `chord.dart` re-export shim (`@Deprecated`, points at `core/music/chord.dart`) | `lib/features/live/model/chord.dart` | `lib/core/music` | Same condition as the `wav.dart` row, applied to this file. | 0 external importer files |
| `chord_event.dart` re-export shim (`@Deprecated`, points at `core/music/chord_event.dart`) | `lib/features/live/model/chord_event.dart` | `lib/core/music` | Same condition as the `wav.dart` row, applied to this file. | 0 external importer files |
| `strum.dart` re-export shim (`@Deprecated`, points at `core/music/strum.dart`) | `lib/features/live/model/strum.dart` | `lib/core/music` | Same condition as the `wav.dart` row, applied to this file. | 0 external importer files |
| `ApiConfig` legacy compatibility class (4 `@Deprecated` members, points at `AppConfig`/`appConfigProvider`) | `lib/core/api/api_config.dart` | `lib/app/config` (`AppConfig` ownership) | `dart run tool/check_deprecations.dart` reports 0 external importer files for this file (already true, measured 2026-09-02) AND a dedicated cleanup round deletes it — the file's own doc comment already names this as the Epic 1 config-migration end state. | 0 external importer files |
| `library` vs `library_v2` parallel feature layers | `lib/features/library_v2/` | `lib/features/library_v2` | The 5 remaining `lib/features/library/` external importer files migrate to `library_v2`, `dart run tool/check_deprecations.dart` reports 0 for `lib/features/library/`, and a dedicated round removes the old layer — an ADR authorising the removal (mirroring ADR 0395's pattern for closing a compatibility layer). | `library`: 5 external importer files · `library_v2`: 1 external importer file |
| `progress` vs `progress_v2` parallel feature layers | `lib/features/progress_v2/` | `lib/features/progress` / `progress_v2` (Progress domain) | `progress_v2` currently has **zero** external importer files — this alone is NOT removal permission for either layer (§5.3): either (a) `progress_v2` gains at least one real external importer file (it is being actively wired up), or (b) a dedicated round measures and demonstrates it is genuinely dead code and removes it, or (c) once `progress_v2` is the active layer, `progress`'s 17 external importer files migrate to it and a dedicated round removes `progress`. | `progress`: 17 external importer files · `progress_v2`: 0 external importer files |
| E08-R30 routing TODOs (8 occurrences: `LegacyStreakMigrator` write-back, level-detail navigation, achievement-progress wiring, typed `QuestRouteAction` routing, streak-recovery purchase flow, source-ledger/inbox routing; scattered, non-contiguous lines in `lib/app/routing/app_router.dart` — see `grep -n "TODO(E08-R30)" lib/app/routing/app_router.dart`) | — | `lib/app/routing` (E08-R30 owner) | The E08-R30 features each TODO names (listed above) actually ship, and each TODO line is deleted in the same commit that wires up its feature — not before. | 8 TODO occurrences |
| chunk 013 retention/nudge TODOs (5 occurrences: streak skill-reframe, `nudgeEnabledProvider` doc, gamification preferences doc, `NudgeService` doc, Friday-aware copy r157; spans `lib/features/streak/screens/streak_screen.dart`, `lib/features/settings/providers/nudge_enabled_provider.dart`, `lib/features/gamification/domain/gamification_preferences.dart`, `lib/core/notifications/nudge_service.dart`) | — | `lib/core/notifications` + `lib/features/gamification` (retention experiment) | The chunk 013 #2 retention experiment concludes (ships or is dropped) and the Friday-aware copy (r157) reaches its final wording — the TODO markers are removed as part of that round's changes, not independently. | 5 TODO occurrences |
| `home_shell.dart` nav ARB TODO (`TODO(E13-R16)`) | `lib/app/home_shell.dart` | `lib/app` (shell / i18n) | E13-R16 or a successor round adds dedicated nav ARB keys to the l10n scope; the TODO line is removed in that same round. | 1 TODO occurrence |
<!-- technical-debt:end -->

## Why no row deletes anything this round

Every path above is measured, not assumed — `dart run tool/check_deprecations.dart`
reproduces every external-importer-file count in the table above from the
live tree. The nine `@Deprecated` shims already show **zero** external
importer files, which
makes them the strongest removal candidates on this list — but the round
brief's §3/§4 do not include any `lib/` path in the allowed-files list for
this round, so acting on that measurement is explicitly out of scope here
(round brief §0, STOP-protokoll). The `library`/`library_v2` and
`progress`/`progress_v2` pairs are the opposite case: both still have real
external consumers (or, for `progress_v2`, may simply not be fully wired up
yet), so a removal decision there needs its own round regardless of this
round's file-list.
