# Capability rollout — non-production (development/lab) defaults

**Kör:** `E16-R03` (Chapter 16, Kör 3). **Normatív forrás:**
[ADR 0492](../adr/0492-capability-rollout-decision-evidence-and-nonprod-boundary.md)
(D1–D8). **Utólagos módosítás (2026-09-15, tulajdonosi döntés):** a helyi
AI Tutor és az Audio Analysis V2 hét nem-kísérleti flagje **BE** lett a
NEM-production sávban — a részleteket a tábla és a §3 rögzíti.

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
| Diagnostics | `diagnosticsEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:93` (`nonProd`, E01-R03 óta) | — (már BE) |
| Lab mode | `labModeAvailable` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:94` (`nonProd`, E01-R03 óta) | — (már BE) |
| Practice Engine V2 | `practiceEngineV2Enabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:95` (`nonProd`, ADR 0065) | — (már BE) |
| Migrated Learn | `migratedLearnEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:96` (`nonProd`) | — (már BE) |
| Practice detailed history | `practiceDetailedHistoryEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:97` (`nonProd`) | — (már BE) |
| Song Trainer V2 | `songTrainerV2Enabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:98` (`nonProd`, ADR 0197) | — (már BE) |
| Practice Generator | `practiceGeneratorEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:111` (`nonProd`, ADR 0491 D2, E15-R07) | — (már BE) |
| Adaptive shell | `adaptiveShellEnabled` | **BE** (változatlan) | ✓ | ✓ | ✓ | ✓ | `lib/app/config/feature_flags.dart:162` (`nonProd`, ADR 0467, E15-R02) | — (már BE) |
| Account layer | `accountEnabled` | N/A — nem `forEnvironment`-döntés | — | — | — | — | `lib/app/config/feature_flags.dart:92` (hívó-adta átmenő érték, forrás: `lib/core/api/api_config.dart:19`, `STRUMSIGHT_ACCOUNT` dart-define) | ez a kör nem dönt róla — a `ga-scope.md` `disabled` sora fedi |
| AI Tutor (local) | `aiTutorEnabled` | **BE** (tulajdonosi döntés 2026-09-15, csak NEM-production) | ✓ | ✓ (a Termék/User döntés megszületett) | ✓ | ✓ | `lib/app/config/feature_flags.dart:105` (`nonProd`); a helyi út hálózat nélküli, szinkron (`lib/features/ai_tutor/application/offline/local_tutor_fallback.dart`), a production tutor-override-okat a `lib/main.dart` bekötve indítja; route-gate: `lib/app/routing/app_router.dart` (E04-R18) | — (BE 2026-09-15 óta, tulajdonosi döntés: „az egész app működjön a telepített development/lab buildben"; a production ág változatlanul `false` — ld. `docs/release/ga-scope.md`) |
| AI Tutor (cloud) | `aiTutorCloudEnabled` | **KI** | ✓ | ✗ | — | ✗ | `lib/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart` (StrumSight backend proxy szükséges); `docs/release/blockers.md` R-PRIV-01 (nincs release-szintű privacy policy adat-egressre) | `E12-R17` (privacy/data inventory, `pending`) + `E16-R04` (élő backend end-to-end, `PREPARED`) |
| Planner Assist | `plannerAssistEnabled` | **KI** | — | ✗ | — | ✗ | `lib/app/config/feature_flags.dart:210-211` (doc-comment: „remains OFF … until its rollout decision is recorded"); `docs/rounds/e07-r30-evaluation-and-epic-closure.md` §5.1 „A ROLLOUT emberi döntés" — modell-asszisztált javaslat, nincs modell-integráció | nevesítetlen jövőbeli rollout-kör (Termék döntés) — ld. `docs/rounds/e07-r30-evaluation-and-epic-closure.md` §5.1; ADR 0491 D2 külön tartja a `practiceGeneratorEnabled`-től |
| Computer Vision (11 flag) | `visionEnabled`, `visionSetupEnabled`, `visionHandTrackingEnabled`, `visionPoseTrackingEnabled`, `visionGuitarGeometryEnabled`, `visionPracticeIntegrationEnabled`, `visionSongIntegrationEnabled`, `visionTutorIntegrationEnabled`, `visionAnalysisIntegrationEnabled`, `visionExperimentalFineFretEnabled`, `visionLabCaptureEnabled` | **KI** | ✓ | ✓ | ✗ | ✗ | `docs/sdd/epic-05-completion-report.md:5`: „implementation evidence complete; all Vision user capabilities remain flag-OFF pending HORIZON device acceptance" — 86 PENDING valós-eszköz sor (kamera, thermal/soak, latency) | HORIZON valós-eszköz elfogadás (`docs/sdd/epic-05-completion-report.md`, program-szintű kapu, nincs hozzárendelt kör-szám) |
| Audio Analysis V2 (7 flag) | `audioAnalysisV2Enabled`, `analysisBeatGridEnabled`, `analysisPitchEnabled`, `analysisTechniqueProxiesEnabled`, `analysisComparisonEnabled`, `analysisPracticeIntegrationEnabled`, `analysisTutorIntegrationEnabled` | **BE** (tulajdonosi döntés 2026-09-15, csak NEM-production) | ✓ | ✓ | ✗ (Epic 6 release-blokkolók nyitva — a tulajdonos ezt a development/lab sávra tudatosan felülírta) | ✓ | `lib/app/config/feature_flags.dart:129-131,134-137` (`nonProd`); a V2 útvonal ugyanebben a development/lab sávban kapja meg a capture-producerét (`lib/features/audio_analysis/application/shadow_analysis_runner.dart`) | — (BE 2026-09-15 óta; a production ág változatlanul `false`, ott az `analysisRolloutStage` `v1Default` — ld. `docs/release/ga-scope.md`) |
| Audio Analysis V2 experimental (2 flag) | `analysisPreprocessingExperimentalEnabled`, `analysisExperimentalFusionEnabled` | **KI** | ✓ | ✗ | ✗ | — | `lib/app/config/feature_flags.dart:132-133` (`false` minden ágban); nincs élő hívó, az E06-R29 kiértékelési evidencia hiányzik (ADR 0220) | Epic 6 release-blokkolók feloldása (`docs/sdd/epic-06-completion-report.md`, nincs hozzárendelt kör-szám) |
| Recognition recovery (3 flag) | `recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`, `newLiveStageEnabled` | **KI** | ✓ | ✗ | ✗ | — | `docs/eval/recognition-release-guard.md` „Activation contract": evaluation report + baseline manifest + candidate model manifest + corpus identity + rollback recipe mind hiányzik ma (ADR 0271) | `E14-R02` (baseline/evidence index, `PREPARED`, nincs lefuttatva) + egy jövőbeli, nevesítetlen aktivációs kör |
| Community (5 flag) | `communityEnabled`, `communityWritesEnabled`, `communityMediaEnabled`, `communityLeaderboardEnabled`, `communityClubsEnabled` | **PREVIEW** (változatlan — `const bool.fromEnvironment(...)`, ADR 0395) | ✓ | (✓)‡ | ✓ | ✗ | `backend/app/main.py:238-241` (a Community router felcsatolva, E15-R12); `docs/release/blockers.md` R-PRIV-01, R-SEC-01 (nyitott P1, nincs release-szintű privacy policy / threat model) | `E12-R17` (privacy) + `E12-R18` (threat model), mindkettő `READY`, `pending` végrehajtás; + `E16-R04` (élő backend end-to-end) |
<!-- capability-rollout-decisions:end -->

† `aiTutorEnabled` — E16-R03 idején KI volt: a (d) kritérium technikailag
teljesült (a helyi fallback szinkron, hálózat nélküli —
`LocalTutorFallback`), de az epic saját zárójelentése a bekapcsolást külön
Termék/User döntéshez kötötte. **Ez a döntés 2026-09-15-én megszületett**
(tulajdonos: „az egész app működjön a telepített buildekben"), ezért a flag
a NEM-production sávban `nonProd` lett. A helyi modell-gateway ma is
`LocalTutorModelGatewayStub` (`lib/features/ai_tutor/data/model_gateway/
local_tutor_model_gateway_stub.dart:14`), így a Coach felület a
determinisztikus (nem modell-generált) debrief-et adja; a production ág
változatlanul `false`.

‡ A Community kompozíciós rétege (backend router, E15-R12) valós adatot ad,
de a build-idejű alapértelmezés bekapcsolása enélkül is bukna (d)-n — a
dart-define hiányában MINDEN cohortban `false` marad, ez a struktúra
változatlan.

## 3. A kör döntése — ZERO FLIP (E16-R03) és az utólagos tulajdonosi flip (2026-09-15)

**Az E16-R03 kör kimenete ZERO FLIP volt:** akkor egyetlen capability sem
teljesítette mind a négy kritériumot, a `feature_flags.dart` `forEnvironment`
törzse a körben változatlan maradt. Ez nem volt hiányos kör: a round brief
§0.0.1 R3 és az ADR 0492 D1 kifejezetten elfogadott, mért kimenetként
rögzíti ezt az esetet.

**2026-09-15-én a tulajdonos döntött** („az egész app működjön a telepített
development/lab buildekben, a production maradjon változatlan"): a helyi AI
Tutor (`aiTutorEnabled`) és az Audio Analysis V2 hét nem-kísérleti flagje
`nonProd` lett — BE development/lab alatt, `false` production alatt. Ez
tulajdonosi (Termék/User) döntés, nem mérnöki készenlét állítása: az Audio
Analysis (c) kritériuma (Epic 6 release-blokkolók) továbbra is nyitott, a
tábla ezt nem takarja el. Változatlanul KI: Vision (az ML-modelljei
deferred assetek), a recognition recovery hármas (nincs fogyasztója), a
cloud Tutor, a Planner Assist és a két kísérleti analysis-flag; a Community
PREVIEW marad.

A nyolc, korábbi körökben már `nonProd`-dá vált capability (Diagnostics, Lab
mode, Practice Engine V2, Migrated Learn, Practice detailed history, Song
Trainer V2, Practice Generator, Adaptive shell) változatlanul BE marad — ezt
a kör nem mozdítja, csak megerősíti a fenti táblában.

A `production` ág egyetlen mezője sem változott — sem az E16-R03 körben,
sem a 2026-09-15-i tulajdonosi flipben; a GA-scope döntés a Chapter 12 Kör
28 hatásköre (`docs/release/ga-scope.md`, ADR 0489).

## 4. Valódi-sértés próba (round brief §6.1, dokumentálva a §10-ben)

A round brief §6.1 kötelező próbája — `aiTutorCloudEnabled` ideiglenes
`nonProd`-ra állítása, a §7 gate lefuttatása, majd visszaállítás — a round
brief `docs/rounds/e16-r03-capability-rollout-decisions.md` §10
„Implementation handoff" szakaszában van dokumentálva a mért kimenettel
együtt.
