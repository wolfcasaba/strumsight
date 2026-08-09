# ADR 0197 — Practice V2 és Song Trainer V2 elérhetővé tétele: a rollout-határ áthelyezése és a belépési pont mint a rollout része

- **Státusz:** Elfogadva (GOV-05a pre-flight, 2026-08-09)
- **Kör:** GOV-05a — Practice V2 + Song Trainer V2 shipping rollout
  (governance-kör, nem SDD-fejezet)
- **Implementer motor:** Terra (Codex CLI, `~/.codex-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Opus 5) írta a
  pre-flightban ([ADR 0055](0055-agent-role-protocol.md)).
- **Kontext-ADR-ek:** [0052](0052-round-green-gate.md) (zöld kapu),
  [0053](0053-ci-full-test-suite.md) (CI-oldali teljes suite),
  [0087](0087-autonomous-round-pipeline.md) (kör-pipeline)
- **User-döntés, amit végrehajt:** 2026-08-07, `HANDOFF.md` §6 „Kötelező
  sorrend" 3. pont — „a shipping kört először", azaz a már kész, de
  elérhetetlen kód termékké tétele.

## Kontextus

**Mért a pre-flightban 2026-08-09-én, `main @ bbc95187`** (minden állítás
grep-elve, nem a dokumentációból feltételezve):

1. **A `lib/` 43%-a elérhetetlen.** `HANDOFF.md` §3 rögzíti: `song_trainer` V2
   (25 308 sor), `ai_tutor` (14 091), `vision` (5 132). A GOV-05a a
   Song Trainer V2-t célozza.

2. **A flag-állapot nem az egyetlen zár.** `lib/app/config/feature_flags.dart:60`
   szerint `practiceEngineV2Enabled: nonProd` — a Practice Engine V2 flagje
   **ma is `true`** `development` és `lab` környezetben, és a `/practice*`
   route-ok regisztrálva vannak (`lib/app/routing/app_router.dart:62–66`).
   A feature ennek ellenére **elérhetetlen a felhasználó számára**.

3. **A mérés, ami ezt kimondja.** A gated route-okra mutató hivatkozások
   száma a `lib/` fában, az útvonal-katalógust és a routert kizárva
   (`grep -rn "AppRoutes.<név>" lib/ --include=*.dart`, majd
   `app_route.dart` + `app_router.dart` kiszűrve):

   | Route-konstans | Találat a `lib/`-ben | Mi ez |
   |---|---|---|
   | `practiceHub` | 1 — `practice_setup_screen.dart:104` | **belső** `context.go` a setupról visszafelé, nem belépési pont |
   | `songTrainerLibrary` | 0 | nincs belépési pont |
   | `tutorHome` | 0 | nincs belépési pont |
   | `visionSetup` / `visionSession` | 0 / 0 | nincs belépési pont |

   A navigációs héj (`lib/app/home_shell.dart:69–95`) öt desztinációt kínál —
   Live, Analyze, Learn, Library, Settings —, és az `AppRoutes.shellTabs`
   (`lib/app/routing/app_route.dart:40–46`) ezt a sorrendet pinneli. Egyik
   sem vezet a Practice Hubhoz vagy a Song Trainerhez.

4. **Következmény:** egy pusztán flag-átbillentő „rollout" kör **nem**
   tenné elérhetővé a kódot. A flag a route-regisztráció feltétele; a route
   önmagában viszont csak URL, amit a felhasználó nem tud beírni. Az
   E02-R12-ben rögzített viselkedés szerint egy nem regisztrált `/practice*`
   URL a router `onException` ágán Live-ra esik — vagyis a hiányzó belépési
   pont nem hibaüzenet, hanem **néma elérhetetlenség**.

5. **A meglévő őr, amit nem szabad eldobni.**
   `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart:244–267`
   („E03-R01 rollout guard") azt állítja, hogy `songTrainerV2Enabled` **minden**
   `AppEnvironment`-ben `false`, és hogy az alapértelmezett konstruktor is
   OFF-on hagyja. Az őr indoklása a tesztben: „a flaget NEM szabad implicit
   módon bekapcsolni azzal, hogy a build production-ön kívül fut".

6. **A `forEnvironment` sugara mérve:** 8 tesztfájl hívja
   (`test/app/app_config_test.dart`, `test/app/feature_flags_test.dart`,
   `test/features/auth/auth_controller_test.dart`,
   `test/features/learn/learn_migration_parity_test.dart`,
   `test/features/learn/learn_rollback_test.dart`,
   `test/features/settings/settings_sync_test.dart`,
   `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`,
   `test/features/vision/vision_offline_regression_test.dart`), a `lib/`-ben
   két hívó van: `app_bootstrap.dart:49` és `app_config.dart:194`.

7. **Az i18n nem igényel új kulcsot:** `practiceHubTitle` és `songTrainerTitle`
   **mindkét** ARB-ben létezik (`app_en.arb:499` / `:975`,
   `app_hu.arb:433` / `:909`).

## Döntés

### Döntés 1 — A `songTrainerV2Enabled` rollout-határa „mindenhol OFF"-ról „production-ben OFF"-ra kerül

`FeatureFlags.forEnvironment` a `songTrainerV2Enabled` értékét ezentúl a
`nonProd` predikátumból származtatja, azaz `development` és `lab` build
esetén `true`, `production` esetén `false`.

Amit ez **nem** old fel: az alapértelmezett konstruktor paramétere marad
`false`. Egy `FeatureFlags(...)` hívás, amely nem nevezi meg a flaget,
továbbra is kikapcsolva hagyja. A „soha ne kapcsoljon be implicit módon"
elvből tehát a *konstruktor-oldali* fele érvényben marad; a
*környezet-oldali* fele az, amit ez a döntés szándékosan felold, mert a
`lab` környezet létezésének éppen ez a célja
(`lib/app/config/app_environment.dart`: „the user-facing diagnostics build
(Lab APK): like development but meant for a real device").

### Döntés 2 — Az E03-R01 rollout-őr átirányítása, nem törlése

A `legacy_fixture_parity_test.dart` „E03-R01 rollout guard" csoportja
**megmarad**, és a szűkebb, továbbra is érvényes határt méri:
`songTrainerV2Enabled` `false` **`AppEnvironment.production`-ben**, és a
default konstruktor is OFF-on hagyja. Az őr törlése vagy tartalom nélküli
átnevezése nem elfogadható feloldás — a rollout határa nem szűnik meg, csak
elmozdul, tehát az őrnek is el kell mozdulnia, nem eltűnnie.

### Döntés 3 — A belépési pont a rollout elválaszthatatlan része

Egy availability-flag átbillentése önmagában **nem** minősül rolloutnak
ebben a projektben. A kör akkor teljesíti a célját, ha a képesség a
felhasználói felületről elérhető. A Practice Hub és a Song Trainer belépési
pontja a **Learn fülre** kerül (`lesson_list_screen.dart`), mert az a héj
egyetlen olyan desztinációja, amely már ma is gyakorlásra mutató
hivatkozásokat gyűjt (`/songs`, `/chords`).

Minden belépési pont **a saját flagjéhez van kötve** külön-külön: a Practice
Hub kártya `practiceEngineV2Enabled`, a Song Trainer kártya
`songTrainerV2Enabled` mögött. Két flag — két független feltétel; nem egy
összevont „V2 be van kapcsolva" predikátum. Így a későbbi rollback egyetlen
flaget érint, és a mérés cellánként elkülöníthető.

### Döntés 4 — Az információs architektúra NEM változik ebben a körben

A legacy „Dalaim" (`/songs`, `SongListScreen`) és az új Song Trainer könyvtár
(`/song-trainer`, `SongLibraryScreen`) **egymás mellett** marad. A két
dal-könyvtár összevonása termékdöntés, nem rollout-lépés; külön körben
kezelendő. Ez a kör az *elérhetőséget* változtatja, nem a navigáció
szerkezetét.

### Döntés 5 — Ez a döntés a vision-re NEM terjed ki

`visionEnabled`, `aiTutorEnabled`, `aiTutorCloudEnabled` és
`migratedLearnEnabled` értéke **változatlan `false` minden környezetben**.
Az AI Tutor és a Learn-migráció saját körben megy (GOV-05b, GOV-05c). A
vision rollout mért blokkolón áll: az `assets/ml/model_manifest.json`
`vision_models` mindkét bejegyzése (`hand_landmarker`, `pose_landmarker`)
`status: "deferred"`, `sha256` csupa nulla, és a hivatkozott
`.tflite` fájlok nincsenek a repóban (`ls assets/ml/` — négy audio `.bin`
és a manifest, semmi más). A `NativeHandLandmarkProvider` /
`NativePoseLandmarkProvider` `deferred` bejegyzésre `AppResult.failure`-t ad
(`native_hand_landmark_provider.dart:77`, `native_pose_landmark_provider.dart:76`),
tehát a `visionEnabled` bekapcsolása egy zsákutcába futó setup-folyamatot
tenne láthatóvá. A vision flag-flip előfeltétele a modell-binárisok
beszerzése és licenc-átvezetése — külön kör.

## Következmények

**Pozitív**

- Egy `lab` APK-ban a Practice Engine V2 és a Song Trainer V2 valóban
  kipróbálható; a HANDOFF §3-ban rögzített „43% elérhetetlen" arány mérhetően
  csökken.
- A rollback egyetlen sor: a `nonProd` visszaírása `false`-ra a
  `songTrainerV2Enabled` sorban; a belépési kártya a flagjével együtt eltűnik.
- A production build viselkedése bizonyíthatóan változatlan marad.

**Negatív / kockázat**

- A `development` környezet is bekapcsolja a Song Trainert, tehát minden
  fejlesztői és CI dev-build hordozza. Ez szándékos: a `nonProd` predikátum a
  projekt bevett rollout-alakja (`practiceEngineV2Enabled`,
  `diagnosticsEnabled`, `labModeAvailable` mind így működik), és a
  production-határt az őr méri.
- Két dal-könyvtár él egymás mellett (Döntés 4) — ismert, tudatosan vállalt
  UX-adósság, follow-up körben oldandó.
- A Song Trainer V2 valós eszközön eddig nem futott. A kör elfogadási
  bizonyítéka ezért nem merül ki a zöld kapuban: a device-mátrix sorai
  PENDING-ként nyílnak, és a user valós-gitáros menete zárja őket.
