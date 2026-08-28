# Kill switch útvonalak — StrumSight feature flag katalógus

**Kör:** `E12-R05` (Feature flag registry és emergency kill switch).
**Normatív forrás:** [ADR 0446](../adr/0446-feature-flag-registry-and-emergency-kill-switch.md).
**Gépi katalógus:** `lib/core/feature_flags/feature_flag_registry.dart` (40
bejegyzés — a `dart run tool/check_feature_flags.dart` a szállított fán a
`lib/app/config/feature_flags.dart` SOURCE-ából mért mezőnevek ellenében
tartja teljesnek; drift esetén nem-nulla kilépési kóddal bukik).

Ez a dokumentum a katalógus emberi olvasatú vetülete — az igazság forrása a
Dart katalógus (`lib/core/feature_flags/feature_flag_registry.dart`). Ez a
tábla ennek **kézi vetülete** (nem generált): a Dart-oldali driftet (hiányzó
katalógus-bejegyzés, lejárt flag, hiányzó owner/kill-switch-út) a `dart run
tool/check_feature_flags.dart` gépileg fogja, de magát ezt a markdown táblát
ma semmi nem méri — frissen tartása szerkesztői fegyelem kérdése.

## 1. A feloldási lánc (ADR 0446 D1–D2)

```
emergency (csak KI)  >  remote (aláírt)  >  capability  >  local/define  >  FeatureFlagDefinition.failClosedDefault
```

- **`emergency` ASZIMMETRIKUS:** kizárólag `false`-t érvényesíthet. A `true`
  értéke figyelmen kívül marad — nem kapcsol be semmit, és nem is hiba
  (`lib/core/feature_flags/feature_flag_source.dart`, `FeatureFlagResolver.resolve`).
- **Hiányzó/ismeretlen forrás NEM esik vissza „utolsó ismert értékre":** a
  lánc a következő gyengébb forrásra lép; ha egyik sem szolgáltat értéket, a
  bejegyzés `failClosedDefault` mezője nyer.
- **A bukott aláírású remote payload figyelmen kívül marad, NEM fatális**
  (nem dob, nem állítja meg az appot) — a lánc úgy folytatódik, mintha a
  forrás nem is válaszolt volna.
- **A kikapcsolás NEM töröl adatot** (ADR 0446 D7): egy capability
  kikapcsolása elrejti a felületet, a felhasználó adatai (felvételek,
  gyakorlás-előzmény, community tartalom) érintetlenek maradnak, és
  visszakapcsoláskor ismét elérhetők.

**Ami MA valós:** a `remote` forrás ebben a körben kizárólag interfész-szintű
(`RemoteFeatureFlagSource`, `SignedFeatureFlagPayload`) — nincs hálózati
csatorna vagy tényleges aláírás-ellenőrzés a fán (ADR 0446 D3). Az `emergency`
és `capability` forrásoknak sincs ma konkrét, éles implementációja — a
tényleges kill switch ma a `local`/define szinten operábilis (a meglévő
`bool.fromEnvironment` út és a `feature_flags.dart` konstruktor-alapértékei).

## 2. A katalógus — mind a 40 mért `FeatureFlags` mező

**Mérési korrekció:** a kör briefjének pre-flightja (§0.0 R1) 37 mezőt (3
kötelező + 34 alapértelmezett) állított; egy közvetlen újraszámolás ugyanazon
a commiton (`grep -c 'final bool ' lib/app/config/feature_flags.dart`) **40**
mezőt mér (3 kötelező + 37 alapértelmezett). A katalógus ezért mind a 40 valós
mezőt tartalmazza — ez tartja zölden a `dart run tool/check_feature_flags.dart`
futást a szállított fán (részletek: a round brief §10).

Az „ADR" oszlop csak akkor tölt, ha `lib/app/config/feature_flags.dart` MAGA
hivatkozik egy ADR-re az adott mező doc-commentjében vagy a közvetlenül fölötte
álló blokk-kommentben — a „—" NEM azt jelenti, hogy nincs kapcsolódó döntés,
csak azt, hogy a forrás nem nevez meg egyet.

| Flag | Owner | Risk | ADR | Kill-switch út |
|---|---|---|---|---|
| `accountEnabled` | lib/features/auth (account layer) | high | — | STRUMSIGHT_ACCOUNT dart-define, read at lib/core/api/api_config.dart:19; already off by default — omit the define at build time to keep it off. |
| `diagnosticsEnabled` | lib/features/diagnostics | high | — | gated by `environment != AppEnvironment.production` at feature_flags.dart:76; a production release build already resolves this to false. |
| `labModeAvailable` | lib/features/settings (Lab-mode toggle) | low | — | gated by `environment != AppEnvironment.production` at feature_flags.dart:77; a production release build already resolves this to false. |
| `practiceEngineV2Enabled` | lib/features/practice (Practice Engine V2) | medium | — | gated by `environment != AppEnvironment.production` at feature_flags.dart:78; a production release build already resolves this to false. |
| `migratedLearnEnabled` | lib/features/learn | medium | — | gated by `environment != AppEnvironment.production` at feature_flags.dart:79; a production release build already resolves this to false. |
| `practiceDetailedHistoryEnabled` | lib/features/practice (detailed history store) | low | — | gated by `environment != AppEnvironment.production` at feature_flags.dart:80; a production release build already resolves this to false. |
| `songTrainerV2Enabled` | lib/features/song_trainer | medium | ADR 0197 | gated by `environment != AppEnvironment.production` at feature_flags.dart:81; a production release build already resolves this to false. |
| `aiTutorEnabled` | lib/features/ai_tutor | medium | ADR 0132 | hardcoded to `false` in every environment at feature_flags.dart:82; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `aiTutorCloudEnabled` | lib/features/ai_tutor (cloud capability) | high | ADR 0213 | hardcoded to `false` in every environment at feature_flags.dart:83; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `practiceGeneratorEnabled` | lib/features/practice_generator | medium | ADR 0255 | hardcoded to `false` in every environment at feature_flags.dart:84; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `plannerAssistEnabled` | lib/features/practice_generator (planner assist) | medium | ADR 0270 | hardcoded to `false` in every environment at feature_flags.dart:85; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionEnabled` | lib/features/vision | medium | ADR 0178 | hardcoded to `false` in every environment at feature_flags.dart:86; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionSetupEnabled` | lib/features/vision (setup flow) | low | — | hardcoded to `false` in every environment at feature_flags.dart:87; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionHandTrackingEnabled` | lib/features/vision (hand tracking) | low | — | hardcoded to `false` in every environment at feature_flags.dart:88; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionPoseTrackingEnabled` | lib/features/vision (pose tracking) | low | — | hardcoded to `false` in every environment at feature_flags.dart:89; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionGuitarGeometryEnabled` | lib/features/vision (guitar geometry) | low | ADR 0187 | hardcoded to `false` in every environment at feature_flags.dart:90; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionPracticeIntegrationEnabled` | lib/features/vision (Practice integration) | medium | — | hardcoded to `false` in every environment at feature_flags.dart:91; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionSongIntegrationEnabled` | lib/features/vision (Song Trainer integration) | medium | — | hardcoded to `false` in every environment at feature_flags.dart:92; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionTutorIntegrationEnabled` | lib/features/vision (AI Tutor integration) | medium | ADR 0194 | hardcoded to `false` in every environment at feature_flags.dart:93; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionAnalysisIntegrationEnabled` | lib/features/vision (Analyze integration) | medium | ADR 0194 | hardcoded to `false` in every environment at feature_flags.dart:94; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionExperimentalFineFretEnabled` | lib/features/vision (experimental fine-fret) | low | — | hardcoded to `false` in every environment at feature_flags.dart:95; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `visionLabCaptureEnabled` | lib/features/vision (Lab-only camera capture diagnostics) | high | — | hardcoded to `false` in every environment at feature_flags.dart:96; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `audioAnalysisV2Enabled` | lib/features/audio_analysis (V2 route) | medium | ADR 0220 | hardcoded to `false` in every environment at feature_flags.dart:97; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisBeatGridEnabled` | lib/features/audio_analysis (beat-grid evidence) | low | ADR 0220 | hardcoded to `false` in every environment at feature_flags.dart:98; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisPitchEnabled` | lib/features/audio_analysis (pitch evidence) | low | ADR 0220 | hardcoded to `false` in every environment at feature_flags.dart:99; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisPreprocessingExperimentalEnabled` | lib/features/audio_analysis (experimental preprocessing) | low | — | hardcoded to `false` in every environment at feature_flags.dart:100; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisExperimentalFusionEnabled` | lib/features/audio_analysis (experimental DSP/ML fusion) | low | — | hardcoded to `false` in every environment at feature_flags.dart:101; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisTechniqueProxiesEnabled` | lib/features/audio_analysis (Lab technique-proxy calculators) | low | ADR 0236 | hardcoded to `false` in every environment at feature_flags.dart:102; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisComparisonEnabled` | lib/features/audio_analysis (session comparison/trend) | medium | ADR 0246 | hardcoded to `false` in every environment at feature_flags.dart:103; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisPracticeIntegrationEnabled` | lib/features/audio_analysis (Practice evidence adapter) | medium | — | hardcoded to `false` in every environment at feature_flags.dart:104; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `analysisTutorIntegrationEnabled` | lib/features/audio_analysis (Tutor evidence adapter) | medium | — | hardcoded to `false` in every environment at feature_flags.dart:105; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `recognitionRecoveryEnabled` | lib/features/live (recognition recovery, not yet wired) | low | ADR 0271 | hardcoded to `false` in every environment at feature_flags.dart:106; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `recognitionShadowModeEnabled` | lib/features/live (recognition recovery, not yet wired) | low | ADR 0271 | hardcoded to `false` in every environment at feature_flags.dart:107; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `newLiveStageEnabled` | lib/features/live (recognition recovery, not yet wired) | low | ADR 0271 | hardcoded to `false` in every environment at feature_flags.dart:108; no dart-define or environment boundary can turn it on today — enabling it requires a source change. |
| `communityEnabled` | lib/features/community | high | ADR 0395 | STRUMSIGHT_COMMUNITY dart-define at feature_flags.dart:113; already off by default — omit the define at build time to keep the whole Community surface off. |
| `communityWritesEnabled` | lib/features/community (writes) | high | ADR 0395 | STRUMSIGHT_COMMUNITY_WRITES dart-define at feature_flags.dart:114-116; already off by default — omit the define at build time. |
| `communityMediaEnabled` | lib/features/community (media uploads) | high | ADR 0395 | STRUMSIGHT_COMMUNITY_MEDIA dart-define at feature_flags.dart:117-119; already off by default — omit the define at build time. |
| `communityLeaderboardEnabled` | lib/features/community (leaderboard) | medium | ADR 0395 | STRUMSIGHT_COMMUNITY_LEADERBOARD dart-define at feature_flags.dart:120-122; already off by default — omit the define at build time. |
| `communityClubsEnabled` | lib/features/community (clubs) | medium | ADR 0395 | STRUMSIGHT_COMMUNITY_CLUBS dart-define at feature_flags.dart:123-125; already off by default — omit the define at build time. |
| `adaptiveShellEnabled` | lib/app (adaptive shell — home_shell.dart, routing/*) | medium | ADR 0275 | hardcoded to `false` in every environment at feature_flags.dart:129; no dart-define exists on purpose — enabling it requires a source change. |

## 3. Amit ez a kör NEM vezetett be

- **Valódi hálózati remote-flag csatorna vagy aláírás-ellenőrzés** — a
  `RemoteFeatureFlagSource`/`SignedFeatureFlagPayload` interfész-szintű (ADR
  0446 D3); a tényleges csatorna a rollout-körök (SDD Ch12 Kör 30/31) dolga.
- **A `tools/round-gate.sh` bővítése** a `check_feature_flags.dart`-tal (ADR
  0446 D7 utolsó pontja) — az audit-eszköz futtatása ma kézi/CI-lépés, nem a
  kör-gate része.
- **A `lib/app/config/feature_flags.dart` módosítása** — a katalógus a
  MEGLÉVŐ mezőkre hivatkozik, a fájl ebben a körben nem változott.

## 4. Hogyan olvasd, ha incidens van

1. Keresd meg az érintett capability `FeatureFlags` mezőjét ebben a
   táblában (vagy a Dart katalógusban, `lib/core/feature_flags/feature_flag_registry.dart`).
2. A „Kill-switch út" oszlop megmondja, van-e ÉLŐ dart-define (a legtöbb
   flagnek MA nincs — l. fent) vagy forráskód-módosítás szükséges.
3. A kikapcsolás **nem töröl adatot** (ADR 0446 D7) — a felhasználói adat a
   capability visszakapcsolásakor ismét elérhető.
