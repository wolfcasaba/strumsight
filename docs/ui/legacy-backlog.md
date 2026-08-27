# Chapter 13 legacy backlog (dated)

Everything in this file is measured against `main @ 126d0dfc` plus this
round's own tree, 2026-08-27 (E13-R36, the Chapter 13 closing round). Per
brief §5.3: what remains does not disappear from the record — every entry
below carries what, why, an owner, and a date. `lib/**` is this round's
tilos zona (brief §4), so nothing here was fixed in `lib/**` this round —
only measured and recorded.

## 1. Dated exclusion-list entries (§0.0.B/B5) — measured `lib/**` layout
   defects this round could not fix

Both defects were discovered BY this round's own new gates
(`e13_r36_variant_matrix_test.dart`, `closure_suite_test.dart`) — they are
not carried over from an earlier round. Each is a `const _ExcludedCell`
(matrix file) or a dedicated `testWidgets` cell (closure suite) that
verifies the overflow is STILL present — a resolved defect left on either
list would turn that cell RED (the shrink-only guard, L180).

| # | Screen / widget | Cell | Measured overflow | Date | Source test | Owner | Why not fixed this round |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `lib/features/live/screens/live_screen.dart:477` (stat-strip `Row`) | `live·light·en·landscape·textScale2.0` | 12px, right, horizontal `Row` | 2026-08-27 | `test/ui/goldens/e13_r36_variant_matrix_test.dart` | Next Live-screen round (SDD, unscheduled) | `lib/**` is this round's tilos zona; the fix (wrap the Row's children in `Expanded`/`Flexible`, or let the strip scroll) is a `live_screen.dart` edit |
| 2 | same | `live·dark·en·landscape·textScale2.0` | 12px, right | 2026-08-27 | same | same | same |
| 3 | same | `live·light·hu·landscape·textScale2.0` | 34px, right (longer hu labels) | 2026-08-27 | same | same | same |
| 4 | same | `live·dark·hu·landscape·textScale2.0` | 34px, right | 2026-08-27 | same | same | same |
| 5 | `lib/features/onboarding/screens/permission_primer_screen.dart` (permanently-denied branch, `Scaffold(body: SsPermissionState(...))` — not wrapped in a scrollable, unlike the retryable branch a few lines above it) | permanently-denied primer, compact portrait (412x915), `textScale: 2.0` | 297px, bottom, `Column` inside `Center` | 2026-08-27 | `test/accessibility/closure_suite_test.dart` (group "A4") | Next onboarding/permission round (SDD, unscheduled) | `lib/**` is this round's tilos zona; the fix is wrapping the permanently-denied branch in a `SingleChildScrollView`, matching the retryable branch's own comment ("A9 (golden gate, textScaler 2.0): scrollable rather than overflowing") |

Reproduce any row with (row 1 example):

```bash
~/flutter/bin/flutter test test/ui/goldens/e13_r36_variant_matrix_test.dart \
  --plain-name "live|light|en|landscape|2.0"
```

## 2. Deferred UI-architecture guard (§0.0.B/B3)

**What:** `tool/check_ui_architecture.dart` — a machine guard over the
design-system boundary (analogous to `tool/check_architecture.dart`'s
`crossFeatureImportsMustUsePublicApi` rule, but for `core/design_system`
usage) — does not exist.

**Why it wasn't built this round:** the two real gate entry points that
could run it (`tools/round-gate.sh:233`'s `architecture` step and
`.github/actions/flutter-gates/action.yml:21`) and the guard-of-the-guard
location (`test/tooling/`, e.g.
`architecture_allowlist_guard_test.dart`'s sibling) are ALL in this round's
tilos zona (`tools/**`, `.github/**`, `test/tooling/**` — brief §4). A
measure nothing runs and nothing guards is a decoration, not a gate
(brief §5.1) — so the correct move was to defer the wiring, not to write
an unwired file that looks done.

**Owner:** a future governance round whose `allowed_paths` explicitly
covers `tool/check_ui_architecture.dart`, `tools/round-gate.sh`, and
`.github/actions/flutter-gates/action.yml` together (SDD, unscheduled).

**Date measured:** 2026-08-27.

**What the guard should do, once built:** the same three cells the manual
migration-status.md measurement above did by hand — every `lib/features/
**/*_screen.dart` file's `design_system` import presence, the shrink-only
migrated/legacy set, and a regression check that a MIGRATED screen never
reverts to importing `AppColors`/`AppPalette` directly instead of
`core/design_system` tokens.

## 3. Remaining legacy screens — 53 of 96 (55.2%)

The exhaustive, measured per-screen table lives in
`docs/ui/migration-status.md` (§"Per-feature status") — not duplicated
here. Summary, with owner and date:

| Group | Screens remaining | Owner | Date measured |
| --- | ---: | --- | --- |
| `ai_tutor` | 5 | Next AI-Tutor design round (SDD, unscheduled) | 2026-08-27 |
| `analyze` | 1 | Next Analyze design round (SDD, unscheduled) | 2026-08-27 |
| `audio_analysis` | 5 | Next Audio-Analysis design round (SDD, unscheduled) | 2026-08-27 |
| `gamification` | 6 | Next Gamification design round (SDD, unscheduled) | 2026-08-27 |
| `learn` | 4 | Next Learn design round (SDD, unscheduled) | 2026-08-27 |
| `library` (superseded by `library_v2`, both still reachable) | 2 | Retire once the legacy route redirect is unconditional (SDD, unscheduled) | 2026-08-27 |
| `onboarding` | 1 (`onboarding_screen.dart`) | Next onboarding round (SDD, unscheduled) | 2026-08-27 |
| `practice` | 4 | Next Practice design round (SDD, unscheduled) | 2026-08-27 |
| `practice_generator` | 6 | Next Practice-Generator design round (SDD, unscheduled) | 2026-08-27 |
| `progress` (superseded by `progress_v2`, both still reachable) | 1 | Retire once the legacy route redirect is unconditional (SDD, unscheduled) | 2026-08-27 |
| `song_trainer` | 9 | Next Song-Trainer design round (SDD, unscheduled) — the E09 "V2" rewrite was architectural, not a Ch13 design migration | 2026-08-27 |
| `songs` | 4 | Same as `song_trainer` — the two features share the eventual migration | 2026-08-27 |
| `streak` (superseded by `gamification`'s hub, both still reachable) | 1 | Retire once the legacy route redirect is unconditional (SDD, unscheduled) | 2026-08-27 |
| `vision` | 3 | Next Vision design round (SDD, unscheduled) | 2026-08-27 |
| `community` | 1 (`followers_screen.dart`) | Next Community follow-up round (SDD, unscheduled) | 2026-08-27 |

**Why this is a backlog, not a regression:** every legacy screen above
compiles, is reachable through its current route (measured by
`test/app/routing/app_router_test.dart` / `legacy_route_redirect_test.dart`
being green — A6), and renders on `AppColors`/`AppPalette`/`AppTheme` — the
Chapter 13 compatibility layer this round's `migration-status.md`
documents. None of them regressed FROM a migrated state; they were never
assigned a Ch13 round.

## 4. Not in this backlog

- `docs/ui/baseline/token-debt.md` — the E13-R01 static token-usage
  baseline (raw `Color(0x…)`/`TextStyle(`/`SizedBox`/`EdgeInsets`
  occurrence counts). Referenced by `migration-status.md`, not
  re-measured or edited here (tilos zona, brief §4).
- The eleven Ch13 §7.5 legacy ROUTE redirects — already dated, measured,
  and machine-guarded by `test/app/navigation/legacy_route_redirect_test.dart`
  (ADR 0275); repeating them here would be a second, driftable copy of an
  already-enforced contract.
