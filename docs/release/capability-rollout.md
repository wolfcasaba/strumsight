# Capability rollout — non-production (development/lab) defaults

**Kör:** `E16-R03` (Chapter 16, Kör 3). **Normatív forrás:**
[ADR 0492](../adr/0492-capability-rollout-decision-evidence-and-nonprod-boundary.md)
(D1–D8).

**Ez a dokumentum a NEM-production (development/lab) alapértelmezésekről
dönt** — melyik capability kap `nonProd` alapértelmezést
`FeatureFlags.forEnvironment`-ben (`lib/app/config/feature_flags.dart`), ha a
build environment `development` vagy `lab`.

**Amit ez a dokumentum NEM tesz** (ADR 0492 D2):

- **Nem a `docs/release/ga-scope.md`** — az a **production/GA** besorolás
  egyetlen normatív forrása (ADR 0489, `tool/release/verify_ga_scope.py`
  gépileg visszaellenőrizve). Ez a dokumentum a production
  alapértelmezésről **saját állítást nem tesz** — arra a `ga-scope.md`-re
  hivatkozik; a mért production-alapértelmezés oszlopa kizárólag ott él, itt
  nincs ismételve, nehogy két igazságforrás keletkezzen ugyanarra a mezőre.
- **Nem a `docs/release/rollout-decision.md`** — az a lépcsőzött, publikus,
  **százalékos** rollout (1% → 5% → 20%) döntési sémája (E12-R32,
  `tool/release/verify_rollout_decision.py`). Ez a dokumentum nem
  százalékot, hanem egy build-idejű be/ki alapértelmezést rögzít.

## 1. A négy kritérium (ADR 0492 D1, round brief §0.0)

Egy capability csak akkor kap `nonProd` alapértelmezést („BE"), ha mind a
négy kritérium teljesül, és a táblában hivatkozással szerepel:

| Jel | Kritérium |
|---|---|
| (a) | A felülete migrált és elérhető |
| (b) | A kompozíciós rétege valós adatot ad |
| (c) | A saját mérce-sávja (teszt/eval gate) zöld |
| (d) | Nem igényel a felhasználónál hiányzó külső erőforrást (backend, API-kulcs, letöltendő modell) |

**NEM elfogadható gyengítés:** „elkészült, tehát menjen" (D1) — egy epic
saját zárójelentése nyitott tétele önmagában kizáró ok, még ha a kód zöld is.

A besorolás zárt készlete: **BE** (alapértelmezés `nonProd`-ra vált) ·
**PREVIEW** (flag mögött marad, van explicit opt-in mechanizmus — pl.
dart-define — de nem alapértelmezés) · **KI** (nincs opt-in mechanizmus sem;
minden környezetben `false`).

## 2. Döntési tábla — mind a 40 `forEnvironment` mező

<!-- capability-rollout-decisions:begin -->
| capability_group | flags | classification | a | b | c | d | evidence | resolving |
|---|---|---|---|---|---|---|---|---|
| Diagnostics | `diagnosticsEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:80` (`nonProd`, E01-R03 óta) | — (már BE) |
| Lab mode | `labModeAvailable` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:81` (`nonProd`, E01-R03 óta) | — (már BE) |
| Practice Engine V2 | `practiceEngineV2Enabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:82` (`nonProd`, ADR 0065) | — (már BE) |
| Migrated Learn | `migratedLearnEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:83` (`nonProd`) | — (már BE) |
| Practice detailed history | `practiceDetailedHistoryEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:84` (`nonProd`) | — (már BE) |
| Song Trainer V2 | `songTrainerV2Enabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:85` (`nonProd`, ADR 0197) | — (már BE) |
| Practice Generator | `practiceGeneratorEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:92` (`nonProd`, ADR 0491 D2, E15-R07) | — (már BE) |
| Adaptive shell | `adaptiveShellEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:138` (`nonProd`, ADR 0467, E15-R02) | — (már BE) |
| Account layer | `accountEnabled` | N/A — nem `forEnvironment`-döntés | — | — | — | — | `lib/app/config/feature_flags.dart:79` (hívó-adta átmenő érték, forrás: `lib/core/api/api_config.dart:19`, `STRUMSIGHT_ACCOUNT` dart-define) | ez a kör nem dönt róla — a `ga-scope.md` `disabled` sora fedi |
| AI Tutor (local) | `aiTutorEnabled` | **KI** | ✓ | ✗ | ✓ | (✓)† | `lib/app/routing/app_router.dart:190,583,655` (route-gate, E04-R18); `lib/features/ai_tutor/application/offline/local_tutor_fallback.dart` (szinkron, hálózat nélküli deterministic fallback) | `docs/sdd/epic-04-completion-report.md` §„Nyitott tételek": **„GA flag-flip döntés \| Termék/User \| Külön döntés"** — az epic saját zárójelentése nevesíti, hogy a bekapcsolás egy külön, ezen a körön kívüli Termék/User döntés, nem mérnöki készenlét kérdése (D1 „elkészült, tehát menjen" tiltása) |
| AI Tutor (cloud) | `aiTutorCloudEnabled` | **KI** | ✓ | ✗ | — | ✗ | `lib/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart` (StrumSight backend proxy szükséges); `docs/release/blockers.md` R-PRIV-01 (nincs release-szintű privacy policy adat-egressre) | `E12-R17` (privacy/data inventory, `pending`) + `E16-R04` (élő backend end-to-end, `PREPARED`) |
| Planner Assist | `plannerAssistEnabled` | **KI** | — | ✗ | — | ✗ | `lib/app/config/feature_flags.dart:182-184` (doc-comment: „remains OFF … until its rollout decision is recorded"); `docs/rounds/e07-r30-evaluation-and-epic-closure.md` §5.1 „A ROLLOUT emberi döntés" — modell-asszisztált javaslat, nincs modell-integráció | nevesítetlen jövőbeli rollout-kör (Termék döntés) — ld. `docs/rounds/e07-r30-evaluation-and-epic-closure.md` §5.1; ADR 0491 D2 külön tartja a `practiceGeneratorEnabled`-től |
| Computer Vision (11 flag) | `visionEnabled`, `visionSetupEnabled`, `visionHandTrackingEnabled`, `visionPoseTrackingEnabled`, `visionGuitarGeometryEnabled`, `visionPracticeIntegrationEnabled`, `visionSongIntegrationEnabled`, `visionTutorIntegrationEnabled`, `visionAnalysisIntegrationEnabled`, `visionExperimentalFineFretEnabled`, `visionLabCaptureEnabled` | **KI** | ✓ | ✓ | ✗ | ✗ | `docs/sdd/epic-05-completion-report.md:5`: „implementation evidence complete; all Vision user capabilities remain flag-OFF pending HORIZON device acceptance" — 86 PENDING valós-eszköz sor (kamera, thermal/soak, latency) | HORIZON valós-eszköz elfogadás (`docs/sdd/epic-05-completion-report.md`, program-szintű kapu, nincs hozzárendelt kör-szám) |
| Audio Analysis V2 (9 flag) | `audioAnalysisV2Enabled`, `analysisBeatGridEnabled`, `analysisPitchEnabled`, `analysisPreprocessingExperimentalEnabled`, `analysisExperimentalFusionEnabled`, `analysisTechniqueProxiesEnabled`, `analysisComparisonEnabled`, `analysisPracticeIntegrationEnabled`, `analysisTutorIntegrationEnabled` | **KI** | ✓ | ✓ | ✗ | — | `docs/sdd/epic-06-completion-report.md:5`: „implementation evidence recorded; rollout stays at shadow, release blockers remain" (ADR 0220); `ShadowAnalysisRunner` élő hívó nélkül, csak contract-teszt | Epic 6 release-blokkolók feloldása (`docs/sdd/epic-06-completion-report.md`, nincs hozzárendelt kör-szám) |
| Recognition recovery (3 flag) | `recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`, `newLiveStageEnabled` | **KI** | ✓ | ✗ | ✗ | — | `docs/eval/recognition-release-guard.md` „Activation contract": evaluation report + baseline manifest + candidate model manifest + corpus identity + rollback recipe mind hiányzik ma (ADR 0271) | `E14-R02` (baseline/evidence index, `PREPARED`, nincs lefuttatva) + egy jövőbeli, nevesítetlen aktivációs kör |
| Community (5 flag) | `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled`, `communityLeaderboardEnabled`, `communityClubsEnabled` | **PREVIEW** (változatlan — `const bool.fromEnvironment(...)`, ADR 0395) | ✓ | (✓)‡ | ✓ | ✗ | `backend/app/main.py:238-241` (a Community router felcsatolva, E15-R12); `docs/release/blockers.md` R-PRIV-01, R-SEC-01 (nyitott P1, nincs release-szintű privacy policy / threat model) | `E12-R17` (privacy) + `E12-R18` (threat model), mindkettő `READY`, `pending` végrehajtás; + `E16-R04` (élő backend end-to-end) |
<!-- capability-rollout-decisions:end -->

† `aiTutorEnabled` (d) kritériuma technikailag teljesül (a helyi fallback
szinkron, hálózat nélküli — `LocalTutorFallback`), de a `production` wirés
gateway ma egy `LocalTutorModelGatewayStub`, ami MINDIG „capability
unavailable"-t jelent (`lib/features/ai_tutor/data/model_gateway/
local_tutor_model_gateway_stub.dart:14`) — a bekapcsolás ma csak a
determinisztikus (nem modell-generált) debrief-et adná, a Coach felület
mögött. A (b) kritérium ettől függetlenül bukik: az epic saját zárójelentése
a bekapcsolást explicit külön Termék/User döntéshez köti.

‡ A Community kompozíciós rétege (backend router, E15-R12) valós adatot ad,
de a build-idejű alapértelmezés bekapcsolása enélkül is bukna (d)-n — a
dart-define hiányában MINDEN cohortban `false` marad, ez a struktúra
változatlan.

## 3. A kör döntése — ZERO FLIP

**Egyetlen capability sem teljesíti mind a négy kritériumot ma** — a
`feature_flags.dart` `forEnvironment` törzse **VÁLTOZATLAN** marad. Ez nem
hiányos kör: a round brief §0.0.1 R3 és az ADR 0492 D1 kifejezetten
elfogadott, mért kimenetként rögzíti ezt az esetet.

A nyolc, korábbi körökben már `nonProd`-dá vált capability (Diagnostics, Lab
mode, Practice Engine V2, Migrated Learn, Practice detailed history, Song
Trainer V2, Practice Generator, Adaptive shell) változatlanul BE marad — ezt
a kör nem mozdítja, csak megerősíti a fenti táblában.

A `production` ág egyetlen mezője sem változott — a GA-scope döntés a
Chapter 12 Kör 28 hatásköre (`docs/release/ga-scope.md`, ADR 0489).

## 4. Valódi-sértés próba (round brief §6.1, dokumentálva a §10-ben)

A round brief §6.1 kötelező próbája — `aiTutorCloudEnabled` ideiglenes
`nonProd`-ra állítása, a §7 gate lefuttatása, majd visszaállítás — a round
brief `docs/rounds/e16-r03-capability-rollout-decisions.md` §10
„Implementation handoff" szakaszában van dokumentálva a mért kimenettel
együtt.
