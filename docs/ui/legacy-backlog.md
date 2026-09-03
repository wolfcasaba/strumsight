# Chapter 13 legacy backlog (dated)

Everything in this file is measured against `main @ 126d0dfc` plus this
round's own tree, 2026-08-27 (E13-R36, the Chapter 13 closing round). Per
brief §5.3: what remains does not disappear from the record — every entry
below carries what, why, an owner, and a date. `lib/**` is this round's
tilos zona (brief §4), so nothing here was fixed in `lib/**` this round —
only measured and recorded.

## 1. Dated exclusion-list entries (§0.0.B/B5) — measured `lib/**` layout
   defects this round could not fix

**Both entries below are CLOSED as of 2026-08-28 (E15-R02).** `lib/**` was
this round's (E13-R36) tilos zona, so the fixes were deferred; E15-R02's
own scope explicitly covered both (brief §2/§3) and fixed them: the stat-strip
`Row`'s children are now wrapped in `Expanded` (`live_screen.dart:477`), and
the permanently-denied primer branch is now wrapped in a
`SingleChildScrollView` matching the retryable branch
(`permission_primer_screen.dart`). The four `_ExcludedCell` entries in
`test/ui/goldens/e13_r36_variant_matrix_test.dart` were removed (the cells
now assert NO overflow) and the `closure_suite_test.dart` "A4" cell was
flipped the same way — both per the shrink-only guard (L180): a resolved
defect is proven by the cell turning green, not by deleting it.

Both defects were discovered BY the E13-R36 round's new gates
(`e13_r36_variant_matrix_test.dart`, `closure_suite_test.dart`) — they were
not carried over from an earlier round.

| # | Screen / widget | Cell | Measured overflow | Date | Source test | Status |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `lib/features/live/screens/live_screen.dart:477` (stat-strip `Row`) | `live·light·en·landscape·textScale2.0` | 12px, right, horizontal `Row` | 2026-08-27 | `test/ui/goldens/e13_r36_variant_matrix_test.dart` | **CLOSED 2026-08-28 (E15-R02)** — `Row` children wrapped in `Expanded` |
| 2 | same | `live·dark·en·landscape·textScale2.0` | 12px, right | 2026-08-27 | same | **CLOSED 2026-08-28 (E15-R02)** — same fix |
| 3 | same | `live·light·hu·landscape·textScale2.0` | 34px, right (longer hu labels) | 2026-08-27 | same | **CLOSED 2026-08-28 (E15-R02)** — same fix |
| 4 | same | `live·dark·hu·landscape·textScale2.0` | 34px, right | 2026-08-27 | same | **CLOSED 2026-08-28 (E15-R02)** — same fix |
| 5 | `lib/features/onboarding/screens/permission_primer_screen.dart` (permanently-denied branch, `Scaffold(body: SsPermissionState(...))` — not wrapped in a scrollable, unlike the retryable branch a few lines above it) | permanently-denied primer, compact portrait (412x915), `textScale: 2.0` | 297px, bottom, `Column` inside `Center` | 2026-08-27 | `test/accessibility/closure_suite_test.dart` (group "A4") | **CLOSED 2026-08-28 (E15-R02)** — branch wrapped in `SingleChildScrollView` |

Reproduce the (now resolved) row 1 case with:

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

## 3. Remaining legacy screens — 5 of 96 (5.208%), MEASURED 2026-09-03
   (E15-R13, §0.0.A/R1) — supersedes the 53-of-96 table below

**91/96 screens are migrated (94.792%)**, measured by
`grep -q design_system` over every `lib/features/**/*_screen.dart` file
(same measurement `migration-status.md` uses). All 5 remaining legacy
screens are **reachable** and all 5 carry a `retire` verdict with a named
successor in `docs/ui/retirement-plan.md` §6:

| Screen | Verdict | Owner round | Successor |
| --- | --- | --- | --- |
| `library/screens/library_screen.dart` | `retire` | `E15-R04` | `library_v2/.../unified_library_screen.dart` |
| `library/screens/session_detail_screen.dart` | `retire` | `E15-R04` | `library_v2/.../library_item_detail_screen.dart` |
| `songs/screens/song_list_screen.dart` | `retire` | `E15-R04` | `song_trainer/.../song_library_screen.dart` |
| `songs/screens/song_builder_screen.dart` | `retire` | `E15-R04` | `song_trainer/.../song_editor_screen.dart` |
| `streak/screens/streak_screen.dart` | `retire` | `E15-R04` | `gamification/.../gamification_hub_screen.dart` |

### 3.0 OPEN — `E15-R04`'s named retirement was never executed

**What:** the five `retire`-verdicted screens above are still present,
still reachable, and NOT deleted or route-redirected. `E15-R04` — the
round `retirement-plan.md` §6 names as owner — closed without performing
the retirement.

**Why this is not a scope violation:**
[ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md) D5:
a `retire` verdict is "a proposal for a separate, reviewed round," not
authorization to delete — `E15-R04` closing without executing it is a
legitimate outcome, not a broken contract. The Ch15 sáv's záró állítása is
therefore "every reachable screen is migrated **or** deliberately
retire-planned with a named successor" — **not** "the retirement happened."

**Owner:** a future round whose `allowed_paths` covers the five screens'
route redirects + file deletion (SDD, unscheduled).

**Date measured:** 2026-09-03 (E15-R13, `dart run
tool/check_screen_reachability.dart --format json` + the `grep -q
design_system` sweep above).

### 3.1 Historical — the 53-of-96 table (2026-08-27, E13-R36 measurement)

Kept for history; superseded first by the E15-R03 per-screen reachability
audit below (§3.2, was §3.1) and now fully superseded by the measured 5
above. The exhaustive, measured per-screen table lives in
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

### 3.2 E15-R03 correction — the table above is per-FEATURE; reachability
    is now measured per-SCREEN, and the "Owner" column above is superseded

`docs/ui/retirement-plan.md` (ADR 0471) is now the canonical per-screen
source for the "Owner" column above — `tool/check_screen_reachability.dart`
measures reachability by class name (router reference OR construction
anywhere in `lib/`), not by feature grouping. Three corrections to the table
above:

1. **`library`, `progress`, `streak` were never "retire once the legacy
   route redirect is unconditional"** — that condition doesn't apply; ADR
   0471 treats retirement as a standing proposal, not something the
   adaptive-shell rollout auto-triggers. `library` and `streak` ARE
   confirmed retire candidates (owner `E15-R04`, named successors in
   `retirement-plan.md` §5). `progress` is **not** — see point 3.
2. Every OTHER "SDD, unscheduled" owner above now has a real round:
   `ai_tutor`→`E15-R05`, `gamification` (5 of 6 — see point below)
   →`E15-R06`, `learn`+`onboarding`→`E15-R07`, `practice`+`progress`
   (as `migrate`, not `retire`)→`E15-R08`, `song_trainer` (8 of 9)→`E15-R09`,
   `songs` (2 of 4 — the other 2 are `retire`, owner `E15-R04`) +
   `audio_analysis` remainder (2 of 8)→`E15-R10`, `vision`→`E15-R11`.
3. **`progress` is `migrate`, not `retire`, because `progress_v2` turned out
   to be unwired** — `ProgressDashboardScreen`/`SkillDetailScreen` have no
   route and no construction site anywhere in `lib/`. This corrects
   `migration-status.md`'s prior "both still reachable" claim for that pair.
   See §5 below and `retirement-plan.md` §3.1.
4. `gamification`'s count of 6 legacy screens included `LevelDetailScreen`,
   which is measured **unreachable** (no route, no construction site) — it
   is excluded from the `E15-R06` round (5 screens, not 6). `song_trainer`'s
   9 similarly included `SetlistSessionScreen`, also unreachable and
   excluded from `E15-R09` (8 screens, not 9).

## 4. Not in this backlog

- `docs/ui/baseline/token-debt.md` — the E13-R01 static token-usage
  baseline (raw `Color(0x…)`/`TextStyle(`/`SizedBox`/`EdgeInsets`
  occurrence counts). Referenced by `migration-status.md`, not
  re-measured or edited here (tilos zona, brief §4).
- The eleven Ch13 §7.5 legacy ROUTE redirects — already dated, measured,
  and machine-guarded by `test/app/navigation/legacy_route_redirect_test.dart`
  (ADR 0275); repeating them here would be a second, driftable copy of an
  already-enforced contract.

## 5. E15-R03 reachability audit — new dated findings (2026-08-28)

Measured with `dart run tool/check_screen_reachability.dart --format json`
(ADR 0471); full detail and reasoning in `docs/ui/retirement-plan.md`. These
are screens the design-migration backlog above never flagged, because
"legacy" (no `design_system` import) and "unreachable" (no measured router
reference or `lib/` construction site) are independent axes — a screen can
be fully migrated and still be dead code.

### 5.1 Unwired features — not a Ch15 design-migration concern

| Feature | Screens | Measured gap | Owner |
| --- | ---: | --- | --- |
| Community | 15 (13 fully unreachable + 2 reachable only from within this same dead subgraph) | `communityEnabled` flag exists but no `community/**` class is named anywhere in `lib/app/routing/**`, gated or not | Product/navigation decision — wire the flag to a route, or retire the feature; not scheduled |
| Practice Generator | 6 | No route, no construction site anywhere in `lib/` | Product/navigation decision; not scheduled |
| Audio Analysis V2 capture wizard | 3 (`capture/analysis_home_screen.dart`, `analysis_processing_screen.dart`, `analysis_recording_screen.dart`) | No route, no construction site; the rest of `audio_analysis` (overview/timeline/compare/metric-detail/export) IS wired behind `audioAnalysisV2Enabled` | Wire the capture entry point, or retire; not scheduled |

None of these 24 screens carry an `E15-Rxx` owner in `retirement-plan.md` —
assigning a design-migration round to an unreachable screen would spend Ch15
budget on something no user can open (brief §0.0), exactly what this round
measures to prevent.

### 5.2 `progress_v2` wiring gap (corrects `migration-status.md`)

`ProgressDashboardScreen` and `SkillDetailScreen`
(`lib/features/progress_v2/screens/`) are migrated (`design_system` import
present) but have zero measured references: `app_router.dart` builds the
legacy `ProgressScreen` for both `/progress` (line 284) and
`/profile/progress` (line 528). `migration-status.md`'s E13-R36 "Superseded
pairs measured this round" section claimed this pair was "both still
reachable" — that claim predates this measurement and does not hold for
`progress_v2`. Wiring `progress_v2` into a route is a prerequisite before a
future round can revisit `progress/progress_screen.dart` as a `retire`
candidate; until then it stays `migrate` (`E15-R08`).

### 5.3 Smaller one-off unreachable findings

`lib/features/gamification/presentation/screens/level_detail_screen.dart`
(legacy), `lib/features/song_trainer/presentation/screens/setlist_session_screen.dart`
(legacy), `lib/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart`
(already migrated), `lib/features/onboarding/screens/first_win_stage_screen.dart`
(already migrated) — each has zero measured router reference or `lib/`
construction site. Same treatment as §5.1: no Ch15 round assigned.

## 6. E16-R01 gamification composition — dated `TODO(E08-R30)` exclusions

Measured against `main @ 4ca8785f` plus this round's own tree, 2026-09-03
(E16-R01, ADR 0496 §5 / brief §0.0.A/R3). The round wired five of the eight
`TODO(E08-R30)` markers in `lib/app/routing/app_router.dart` to real
providers (`lib/features/gamification/application/gamification_providers.dart`)
and removed every marker from the file; the three below could not be
resolved without touching this round's tilos zona (`lib/features/
gamification/data/**` and the gamification `presentation/screens/**`), so
each is recorded here instead of silently dropped.

### 6.1 Legacy streak write-back into the V2 envelope (E16-R01 entry 1)

**What:** `streakStateProvider` re-runs `LegacyStreakMigrator.migrate()` on
every read instead of persisting the migrated `StreakState` into the V2
namespaced storage envelope once.

**Why it wasn't built this round:** persisting the migrated result needs a
streak-write method on `GamificationRepository` (e.g.
`replaceStreakState(...)`), and `lib/features/gamification/data/**` is this
round's tilos zona (brief §4) — only `application/gamification_providers.dart`
was writable.

**Owner:** a future round whose `allowed_paths` covers
`lib/features/gamification/data/gamification_repository.dart` and its local
implementation (SDD, unscheduled).

**Date measured:** 2026-09-03.

### 6.2 Streak-recovery purchase flow (E16-R01 entry 2)

**What:** `StreakDetailScreen.onRecoveryPressed` (wired in the router's
`AppRoutes.streakDetail` route) stays a no-op — the recovery CTA renders
(when `reason == StreakEvaluationReason.broken`) but tapping it does nothing.

**Why it wasn't built this round:** there is no repository method to
purchase or apply a streak recovery, and `StreakDetailScreen` itself has no
"recovery unavailable" contract to degrade to instead — both are in this
round's tilos zona (`data/**`, `presentation/screens/**`).

**Owner:** a future round whose `allowed_paths` covers the streak-recovery
repository method and the screen's disabled/unavailable state (SDD,
unscheduled).

**Date measured:** 2026-09-03.

### 6.3 Reward-detail route (E16-R01 entry 3)

**What:** `RewardInboxScreen.onItemSelected` (wired in the router's
`AppRoutes.rewardInbox` route) stays a no-op — selecting an inbox entry does
not navigate anywhere.

**Why it wasn't built this round:** there is no reward-detail screen
anywhere on the tree to route to; building one is a new screen, which is new
scope beyond this round's composition-only brief (brief §3 — "NINCS benne:
ÚJ üzleti logika / képernyő").

**Owner:** a future round that scopes and builds a reward-detail screen
(SDD, unscheduled).

**Date measured:** 2026-09-03.

### 6.4 Quest-board content source (E16-R01 entry 4, fix-round)

**What:** `AppRoutes.quests` renders an always-empty `QuestsScreen`
(`dailyChallenge: null`, `dailyChallengeAvailable: false`, `dailyQuests`/
`weeklyQuests: const []`) — the router source for these came from
`questBoardProvider` (fix-round review B2), but that provider itself has no
real quest source to read: it always returns `available: false`.

**Why it wasn't built this round:** quest generation
(`DailyQuestGenerator`/`WeeklyQuestGenerator`) needs a persisted snapshot
(`plannedObjectives`, `availableDays`, `baselineWeeklyMinutes`) that does not
exist anywhere on the tree (§0.0.A/R2) — persisting one is new
business logic/persistence, out of this composition-only round's scope
(brief §3).

**Owner:** a future round whose `allowed_paths` covers the quest-snapshot
persistence and the generator wiring (SDD, unscheduled).

**Date measured:** 2026-09-03 (review), entry added in the fix round.

### 6.5 Four inexpressible-absence values stay a router-passed zero/empty (E16-R01 entry 5, fix-round)

**What:** `activeQuestCountProvider`, `masteryUnlockedCountProvider`,
`weeklyConsistencyDaysProvider`, and `latestSessionXpProvider` all carry
their absence in a type (`GamificationDerivedCount`/
`GamificationDerivedExperience`, `.available == false`), per ADR 0496 §2.
But `GamificationHubScreen.activeQuestCount`/`.masteryUnlockedCount`,
`StreakDetailScreen.weeklyConsistencyDays`, and
`LevelDetailScreen.latestSessionXp` are all required, non-nullable
parameters with no "unavailable" contract — so the router still passes
`.value` (`0` / `ExperiencePoints.empty()`) through unconditionally, and the
user sees the same "0"/"no XP" a bare literal would have shown. The type
carries the fact; nothing downstream can act on it yet.

**Why it wasn't built this round:** the screens are this round's tilos zona
(`presentation/screens/**`) — adding an "unavailable" branch to each of the
four call sites (e.g. an `SsEmptyState` instead of a numeric tile) is a
screen change, not a composition bekötés.

**Owner:** a future round whose `allowed_paths` covers the four screens
above, to add an absence-aware branch for each of these parameters (SDD,
unscheduled).

**Date measured:** 2026-09-03 (review), entry added in the fix round.

### 6.6 Real producers for the bekötött reads do not exist yet (E16-R01 entry 6, fix-round)

**What:** This round's providers read real repository/ledger state
honestly, but nothing on the tree currently WRITES most of it in production:
`GamificationRepository.replaceProfileSnapshot(...)`,
`ActivityEventIngestor(...)`, and `DailyChallengeService(...)` have zero
call sites in `lib/` outside their own definitions. The green router-level
tests (`gamification_composition_test.dart`) prove the wiring against a
seeded test store, not against a live producer — a real device today would
still show an empty profile/inbox/achievement set because nothing feeds
these repositories yet.

**Why it wasn't built this round:** wiring a producer (e.g. calling
`replaceProfileSnapshot` from the practice-session completion flow) reaches
into other features' write paths, which is both new scope (brief §3 —
composition-only) and outside this round's `allowed_paths`.

**Owner:** a future round that scopes and wires the practice/session
completion flow to these gamification write APIs (SDD, unscheduled).

**Date measured:** 2026-09-03 (review), entry added in the fix round.
