# GA-scope — StrumSight capability besorolás

**Kör:** `E12-R28` (Chapter 12, Kör 28). **Normatív forrás:**
[ADR 0489](../adr/0489-ga-scope-classification-and-contract-freeze.md) (D1–D9).
Lásd még [`beta-findings.md`](beta-findings.md) (miért nem béta-adatból
épül ez a dokumentum) és [`contract-freeze.md`](contract-freeze.md) (a
core-hoz tartozó, most befagyasztott contractok).

**Állapot: NEM KÉSZ (NOT READY)** — a mérés pillanatában nyitva van egy P0
([`R-SIGN-01`](blockers.md)) és öt P1 ([`R-VER-01`](blockers.md),
[`R-PRIV-01`](blockers.md), [`R-SEC-01`](blockers.md),
[`R-STAGE-01`](blockers.md), [`R-STORE-01`](blockers.md)) — lásd
[`blockers.md`](blockers.md). Ez a dokumentum tehát egy GA-scope
**tervezetét** rögzíti, nem egy kiadható állapotot (ADR 0489 D7); a
„NEM KÉSZ" jelzés a `tool/release/verify_ga_scope.py` egyetlen géppel
olvasott állítása erről a fejlécről — ha bármelyik fenti blocker lezár, ez a
sor és a `verify_ga_scope.py --blockers` bemenete együtt frissül, nem
külön-külön.

## 1. A besorolás alanyai és a zárt készlet

A besorolás alanyainak halmaza a [`docs/beta/cohort-profiles.yaml`](../beta/cohort-profiles.yaml)
mindkét cohortja által megnevezett **16** flag-kulcs (ADR 0489 D1) — sem
kevesebb, sem több; a `tool/release/verify_ga_scope.py` nem-nulla kilépéssel
áll meg, ha egy kulcs hiányzik, duplikált, vagy a profilban nem létezik.

A besorolási készlet zárt (D2): `ga` | `preview` | `disabled` | `postponed`.

| Érték | Jelentés |
|---|---|
| `ga` | a GA-ban benne van, a core úton támaszkodni lehet rá |
| `preview` | szállítjuk, de a core út NEM támaszkodhat rá |
| `disabled` | a GA-ban ki van kapcsolva — a flag MINDEN cohortban `false` |
| `postponed` | GA után, a `contract-freeze.md`/az itteni `note` oszlop szerint nevesített feloldó feltétellel |

## 2. Capability-besorolás

Minden `evidence` oszlop egy, a fán MA feloldható repó-relatív útvonal (D3) —
béta-mérési riportra mutató hivatkozás egyikük esetében sincs, mert ilyen
riport ma nem létezik (D8, [`beta-findings.md`](beta-findings.md)).

<!-- ga-scope-capabilities:begin -->
| flag_key | classification | evidence | note |
|---|---|---|---|
| `accountEnabled` | `disabled` | `lib/core/feature_flags/feature_flag_registry.dart` | High-risk optional account layer; already off by default in every cohort (`docs/beta/cohort-profiles.yaml`); the core learning path never reads it (CLAUDE.md: app fully usable logged out). |
| `diagnosticsEnabled` | `disabled` | `lib/core/feature_flags/feature_flag_registry.dart` | Dev/lab-only diagnostics; the `environment != production` gate already resolves false in every production build; both cohorts false today. |
| `labModeAvailable` | `preview` | `docs/beta/cohort-profiles.yaml` | True in both cohorts (testers can reach Lab surfaces), but environment-gated to non-production only; the core path never opens Lab mode. |
| `practiceEngineV2Enabled` | `ga` | `lib/app/routing/app_router.dart` | Gates `AppRoutes.practiceHub` (`lib/app/routing/app_router.dart:180-183`); the core path's Quick Start step cannot render without it — see §3 below. |
| `migratedLearnEnabled` | `preview` | `docs/beta/cohort-profiles.yaml` | `internal: true`, `closed_beta: false` — a progressive, internal-dogfood-only rollout today; no core-path step references it. |
| `practiceDetailedHistoryEnabled` | `preview` | `docs/beta/cohort-profiles.yaml` | Same internal-only, progressive pattern as `migratedLearnEnabled`; no core-path reference. |
| `songTrainerV2Enabled` | `postponed` | `docs/sdd/epic-03-completion-report.md` | Epic 3's own status is "implementation evidence recorded" with release blockers still open in that report's own section; both cohorts false. |
| `aiTutorEnabled` | `postponed` | `docs/testing/device-matrix.yaml` | The `ai_tutor` capability there already carries `ga_scope: false`; hardcoded `false` in every `FeatureFlags.forEnvironment` branch, no dart-define exists to flip it. |
| `aiTutorCloudEnabled` | `postponed` | `docs/release/blockers.md` | Cloud/network sub-capability of `aiTutorEnabled`; `R-PRIV-01` (no privacy policy covering data egress) is an open P1 precondition for any network-touching capability. |
| `visionEnabled` | `postponed` | `docs/testing/device-matrix.yaml` | The `computer_vision` capability there already carries `ga_scope: false`; both shipped vision model manifest entries are `status: deferred` with missing model assets. |
| `visionLabCaptureEnabled` | `disabled` | `lib/core/feature_flags/feature_flag_registry.dart` | Lab-only camera-capture diagnostics, hardcoded `false` in every environment; not a user-facing capability this scope ever ships. |
| `audioAnalysisV2Enabled` | `postponed` | `docs/sdd/epic-06-completion-report.md` | Epic 6's own status is "rollout stays at shadow"; `ShadowAnalysisRunner` has no live caller yet, only a contract test. |
| `communityEnabled` | `postponed` | `docs/release/blockers.md` | `R-PRIV-01`/`R-SEC-01` (no release-level threat model — only the feature-scoped `community-threat-model.md`) are open P1 preconditions for any social/data-collecting surface. |
| `communityWritesEnabled` | `postponed` | `docs/release/blockers.md` | Same `R-PRIV-01`/`R-SEC-01` precondition as `communityEnabled`, narrower (the writes sub-surface). |
| `communityMediaEnabled` | `postponed` | `docs/release/blockers.md` | Same `R-PRIV-01`/`R-SEC-01` precondition as `communityEnabled`, narrowest (the media-upload sub-surface). |
| `adaptiveShellEnabled` | `preview` | `docs/adr/0467-adaptive-shell-is-the-non-production-default.md` | ADR 0467 explicitly defers the production GA decision to this round; `internal: true`, `closed_beta: false`; the core path never routes through it (`test/e2e/first_practice_offline_test.dart` drives `AppRoutes.practiceHub` directly, not the shell). |
<!-- ga-scope-capabilities:end -->

## 3. A core tanulási út — lépésenként, a rátámaszkodó capabilityvel

A négy, `E12-R11` (`done`, ADR 0452) alatt mért e2e-cella közül csak az első
(Quick Start / gyakorlás) függ a fenti 16 capability bármelyikétől; a másik
három (visszatérő felhasználó, migráció, erőforrás-egzisztencia) a saját,
capability-flagtől független `lib/**` API-t hívja közvetlenül — ezt a `none`
capability-kulcs jelöli, amit a `verify_ga_scope.py` szándékosan NEM követel
meg `ga`-ként (nincs mihez).

<!-- ga-scope-core-path:begin -->
| step | capability | evidence |
|---|---|---|
| Fresh install → onboarding (Skip) → Quick Start → offline practice session → history persists | `practiceEngineV2Enabled` | `test/e2e/first_practice_offline_test.dart` |
| Returning user survives an app restart on the same store | `none` | `test/e2e/returning_user_restart_test.dart` |
| Legacy storage migrates on boot (`StorageMigrator.migrate()` never throws) and the app still boots | `none` | `test/e2e/upgrade_migration_test.dart` |
| An arbiter-registered camera consumer frees the coordinator after route-leave/backgrounding | `none` | `test/e2e/resource_coexistence_test.dart` |
<!-- ga-scope-core-path:end -->

**Miért nem jelenik meg a táblában, ami hiányzik:** a `docs/testing/device-matrix.yaml`
kapuja ugyanerre a napra `practice_engine: ga_scope: true`-t mér — egy
független, durvább szemcséjű (device-matrix, nem cohort-flag) forrás,
amely NEM dönt itt, csak megerősíti a fenti `practiceEngineV2Enabled → ga`
sort. Az `audio_analysis_core` (ugyanott `ga_scope: true`) egy MÁSIK,
modell nélküli (`const ClipAnalyzer()`) alap-elemzőre vonatkozik, nem a
fenti `audioAnalysisV2Enabled` V2/modell-útra — a két tengely nem
azonos capability, a device-matrix nem cáfolja a `postponed` sort.

## 4. Ami MA nincs cohorthoz rendelve

A `lib/core/feature_flags/feature_flag_registry.dart` **40** bejegyzésből
csak **16** szerepel a `docs/beta/cohort-profiles.yaml`-ban — a fennmaradó
24 flag ma nincs cohorthoz rendelve, tehát ez a kör GA-besorolást sem ad
nekik (ADR 0489 "Nyitott" szakasz). Ha egy jövőbeli kör bővíti a
cohort-profilt, a `verify_ga_scope.py` D1-ellenőrzése ezt a bővítést
nem-nulla kilépéssel kényszeríti ki a GA-scope-ra is, nem csendes hiánnyal.
