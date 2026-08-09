# E99-R01 (GOV-05a) — Practice V2 + Song Trainer V2 shipping rollout

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-09, kód olvasva:
  `main @ bbc95187`, munkafa tiszta, 0 nyitott PR, a lánc tétlen)
- **Típus:** **governance-kör** (nem SDD-fejezet) — a `HANDOFF.md` §6
  „Kötelező sorrend" (user-döntés 2026-08-07) 3. pontjának első harmada:
  a már kész, de elérhetetlen kód termékké tétele
- **Kör-azonosító:** `E99-R01`. **`E99` nem valódi epic**, hanem a
  governance-körök fenntartott pszeudo-epic kódja. Mérve 2026-08-09: a
  `tools/ai_router/brief.py:19` `TASK_ID = (?i)(e\d{2}-r\d{2})` mintája és a
  `tools/round-pipeline.sh:278` `^[A-Z][0-9]{2}-R[0-9]{2}$` mintája miatt a
  `GOV-05a` alakú fájlnév a gépi kapukból (brief-lint, ai-router, CI-terv,
  scope-audit, inflight-őr) **kiesne** — a GOV-01 még e tooling előtt futott,
  a queue-n kívül. A `E99-R01` azonosító tehát nem kozmetika: ez tartja a
  governance-kört ugyanazon mérce alatt, mint az epic-köröket. A HANDOFF §6
  szerinti emberi neve végig **GOV-05a**.
- **Branch:** `codex/e99-r01-gov-05a-practice-and-song-trainer-shipping-rollout`
- **Előfeltétel:** Epic 5 lezárva (E05-R30 merge-elve, `d3b2caf9`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0197`](../adr/0197-song-trainer-shipping-rollout-boundary.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
  Az implementer ADR-t NEM hoz létre és NEM módosít.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "lib/features/learn/screens/lesson_list_screen.dart",
  "lib/features/practice/presentation/practice_effect_listener.dart",
  "test/app/feature_flags_test.dart",
  "test/features/song_trainer/baseline/legacy_fixture_parity_test.dart",
  "test/features/learn/lesson_list_screen_test.dart",
  "test/features/learn/continue_card_test.dart",
  "docs/manual-testing/practice-engine-device-matrix.md",
  "docs/rounds/e99-r01-gov-05a-practice-and-song-trainer-shipping-rollout.md",
]
gate_tests = [
  "test/app",
  "test/features/learn",
  "test/features/song_trainer/baseline",
  "test/features/auth",
  "test/features/settings",
  "test/features/vision/vision_offline_regression_test.dart",
]
native_gate = true
```

> `native_gate = true` **szándékos**: a kör terméke egy készülékre telepíthető
> APK, amelyben a két képesség elérhető. Az Android-build itt nem a diff natív
> érintettsége miatt kell, hanem mert az APK maga a kör elfogadási bizonyítéka
> (`docs/manual-testing/practice-engine-device-matrix.md`).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl érintése → `stopped`**,
akkor is, ha „csak teszt", és akkor is, ha „csak egy sor". Új fájl létrehozása
szintén scope-sértés — ez a kör **egyetlen új fájlt sem hoz létre**.

## 0.0 Brief-revízió R1 — 2026-08-09, az implementer `stopped` jelzése után (orchesztrátor)

**Az implementer helyesen járt el.** Az OD-05 politikát követve `stopped`-dal
jelzett, ahelyett hogy magától tágította volna a listát:

```
status=stopped
summary=OD-05: test/features/learn/continue_card_test.dart piros; nincs az allowed_paths listán
```

### Mit mértem

A `flutter test test/features/learn` **200 tesztből 1-et** bukott (1 skip,
ami a körtől független, meglévő állapot), és a bukás pontosan egy eset:

```
test/features/learn/continue_card_test.dart:
  „recording a pass MOVES the card — the list rebuilds on progress change"

Expected: exactly 2 matching candidates
  Actual: _TextWidgetFinder:<Found 1 widget with text "Two-Chord Change">
   Which: is not enough
the Continue card must follow the new progress
```

A `flutter test test/app test/features/song_trainer/baseline test/features/auth
test/features/settings` ugyanezen a munkafán **169/169 zöld** — tehát a sugár
nem szélesebb ennél az egy esetnél. (A `test/features/learn` futásban a kör
ÚJ tesztjei — A5 négy cellája, A7, A6 két állítása — mind zöldek.)

### Miért piros, és mi NEM a baj

A teszt azt állítja, hogy a `Two-Chord Change` szöveg **kétszer** szerepel: a
Continue kártyán és a saját listaelemén. A két új belépési kártya a lista
tetején ~180 logikai pixellel lejjebb tolja a tartalmat, így a listaelem
kicsúszik a teszt-viewportból (`ListView` a láthatóságon kívüli gyerekeket nem
építi be a fába), és a `find.text` már csak a Continue kártyát találja meg.

**Ez nem implementációs hiba.** A diff megfelel a brief §5.3–5.4-nek: két
külön `if`, pinnelt kulcsok, `context.push`, meglévő ARB-kulcsok, a kártya
csak a flagtől függ. A `LessonListScreen` bármely, a lista tetejére kerülő
tartalma ugyanezt a hatást váltaná ki.

**A teszt sem hibás.** A tárgya („a Continue kártya követi a haladást") ma is
érvényes; csak a *mérési mechanizmusa* viewport-érzékeny, és eddig azért nem
derült ki, mert a Learn lista teteje sosem változott.

### A feloldás — a lista EGY fájllal bővül, a mérce NEM lazul

A `continue_card_test.dart` nem a rollout-flagekről szól. A helyes feloldás
ezért az, hogy **explicit módon kikösse őket**, és így pontosan azt mérje,
amit a neve ígér — ez a Riverpod-tesztek bevett alakja, és a kör ÚJ tesztje
(`lesson_list_screen_test.dart`) már pontosan ezt a mintát használja:

```dart
appConfigProvider.overrideWithValue(_config(_flags()))  // mindkét flag false
```

**Kötelező alak** (A11): a `continue_card_test.dart` `_pump` segédjébe
bekerül egy `appConfigProvider` override, amely `practiceEngineV2Enabled` és
`songTrainerV2Enabled` értékét egyaránt `false`-ra köti.

**NEM elfogadható feloldás** — bármelyik a mérce lazítása:

- a `findsNWidgets(2)` gyengítése `findsOneWidget`-re (vagy bármi lazábbra);
- a `reason:` szöveg vagy bármely `expect` törlése;
- a teszt vagy a `group` `skip`-elése;
- a belépési kártyák méretének/számának csökkentése azért, hogy a listaelem
  beférjen — a UI nem igazodhat egy teszt viewportjához;
- a teszt-viewport megnövelése (`tester.view.physicalSize`) — ez elrejtené,
  hogy a teszt a láthatóságra épül, és a következő tetejére kerülő elemnél
  újra elhasalna.

### Amit a revízió megváltoztat

1. Az `ai-router` blokk `allowed_paths` listája **egy** bejegyzéssel bővül:
   `test/features/learn/continue_card_test.dart`. Kilenc bejegyzés lesz.
2. Új acceptance-pont: **A11** (§6).
3. Új sor a §6.1 mérce-mátrixban.

A brief minden más előírása változatlan. A lista további tágítása továbbra is
`stopped`-ot kíván.

## 1. Cél

A `HANDOFF.md` §3 mérése szerint a `lib/` 43%-a ma elérhetetlen. Ez a kör
ebből a **Song Trainer V2**-t (25 308 sor) és a **Practice Engine V2**-t teszi
valóban használhatóvá egy `lab` APK-ban — nem új képesség épül, hanem a meglévő
kap rollout-határt és belépési pontot.

A kör két, egymástól elválaszthatatlan mozdulatból áll:

1. **flag:** `songTrainerV2Enabled` `production`-ön kívül `true`;
2. **belépési pont:** a Practice Hub és a Song Trainer könyvtár elérhető a
   Learn fülről.

A második nélkül az első nem rollout — lásd §2.3 mérését, amely megmutatja,
hogy a Practice Engine V2 flagje **ma is ON** `development`/`lab`-ban, a
feature mégis elérhetetlen.

## 2. Jelenlegi állapot (mérve 2026-08-09, `main @ bbc95187`)

### 2.1 A flagek

`lib/app/config/feature_flags.dart` — egyetlen factory,
`FeatureFlags.forEnvironment` (51–78. sor), `final nonProd = environment !=
AppEnvironment.production` (55. sor):

| Flag | Mai érték a factoryban | Sor |
|---|---|---|
| `practiceEngineV2Enabled` | `nonProd` → **dev/lab: true**, prod: false | 60 |
| `songTrainerV2Enabled` | **`false` (hard-kódolt, minden környezetben)** | 63 |
| `migratedLearnEnabled` | `false` | 61 |
| `aiTutorEnabled` / `aiTutorCloudEnabled` | `false` / `false` | 64–65 |
| 11 `vision*` flag | mind `false` | 66–76 |

Dart-define override **egyik** rollout-flagre sincs (a 44–45. sori doc-comment
ezt ki is mondja; a `String.fromEnvironment` egyetlen előfordulása a
`app_environment.dart:29` `STRUMSIGHT_ENV`).

`AppEnvironment` (`lib/app/config/app_environment.dart`) három értéket vesz fel:
`development`, `lab`, `production`. A `lab` a doc-comment szerint „the
user-facing diagnostics build (Lab APK): like development but meant for a real
device".

### 2.2 Az AppConfig validáció

`lib/app/config/app_config.dart:115–122` két függőséget kényszerít:
`migratedLearnEnabled` → `practiceEngineV2Enabled`, és
`practiceDetailedHistoryEnabled` → `practiceEngineV2Enabled`.
**`songTrainerV2Enabled`-re nincs megkötés** — a flag felbillentése nem sért
meglévő validációt, és **nem** kell új szabályt hozzáadni.

### 2.3 A belépési pont hiánya — ez a kör valódi tárgya

`grep -rn "AppRoutes.<név>" lib/ --include=*.dart`, majd a katalógus
(`app_route.dart`) és a router (`app_router.dart`) kiszűrve:

| Route-konstans | Találat | Mi ez |
|---|---|---|
| `practiceHub` | **1** — `lib/features/practice/presentation/screens/practice_setup_screen.dart:104` | belső `context.go` a setupról **visszafelé**; nem belépési pont |
| `songTrainerLibrary` | **0** | nincs |
| `tutorHome` | **0** | nincs (GOV-05b tárgya) |
| `visionSetup` / `visionSession` | **0** / **0** | nincs (blokkolt, §5.5) |

A héj (`lib/app/home_shell.dart:66–95`) öt `NavigationDestination`-t rajzol:
Live, Analyze, Learn, Library, Settings. Az `AppRoutes.shellTabs`
(`lib/app/routing/app_route.dart:40–46`) ugyanezt az ötöt pinneli.

A Learn fül (`lib/features/learn/screens/lesson_list_screen.dart`, 217 sor) az
egyetlen desztináció, amely **már ma is** gyakorlásra mutató hivatkozásokat
gyűjt: az AppBar két `IconButton`-ja (33–46. sor) a `/songs` (legacy „Dalaim",
`SongListScreen`) és a `/chords` útvonalra `push`-ol. A `body` egy `ListView`
(48–70. sor): opcionális `_ContinueCard`, majd `_label(l10n.learnTodaysChallenge)`,
a napi kihívás csempéje, végül nehézségi szintenként a leckék.

### 2.4 A Practice V2 session-út ÉL (a device-mátrix figyelmeztetése avult)

`docs/manual-testing/practice-engine-device-matrix.md` fejléce még azt írja,
hogy „az önálló Practice V2 Hub→Setup→Session út a `practiceSessionHostProvider`
`null` defaultja miatt az élesített appban ma NEM indítható". **Ez már nem
igaz:** az E02-R21 (ADR 0111 §2) bekötötte az éles providert —
`lib/features/practice/presentation/practice_effect_listener.dart:99–104` az
aktív session inputokból származtatja a hostot, és csak `inputs == null`
esetén ad `null`-t. Ugyanennek a fájlnak a **23. sori doc-commentje** viszont
szintén az avult „the production default … is `null`" állítást ismétli.

### 2.5 A meglévő rollout-őr

`test/features/song_trainer/baseline/legacy_fixture_parity_test.dart:244–267`,
`group('E03-R01 rollout guard')`, két teszt:

1. `'songTrainerV2Enabled defaults to false in every environment'` — ciklus
   `AppEnvironment.values` felett, `expect(flags.songTrainerV2Enabled, isFalse,
   reason: 'flag must be OFF in $env')`;
2. `'the default constructor keeps the new flag OFF as well'` —
   `const FeatureFlags(accountEnabled: false, diagnosticsEnabled: false,
   labModeAvailable: false)` → `expect(flags.songTrainerV2Enabled, isFalse)`.

**Az 1. teszt a flag-flip után szükségszerűen piros lesz.** A 2. teszt nem —
azt nem szabad hozzányúlni.

### 2.6 A `forEnvironment` mért sugara

Nyolc tesztfájl hívja `FeatureFlags.forEnvironment`-et (13 hívási hely):
`test/app/app_config_test.dart`, `test/app/feature_flags_test.dart`,
`test/features/auth/auth_controller_test.dart`,
`test/features/learn/learn_migration_parity_test.dart`,
`test/features/learn/learn_rollback_test.dart`,
`test/features/settings/settings_sync_test.dart`,
`test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`,
`test/features/vision/vision_offline_regression_test.dart`.
A `lib/`-ben két hívó: `app_bootstrap.dart:49`, `app_config.dart:194`.
`test/app/routing/app_router_test.dart:102` **nem** a factoryt hívja, hanem
paraméterezett `FeatureFlags`-et épít (`songTrainerV2Enabled: songTrainerEnabled`)
— tehát a flip nem érinti.

### 2.7 i18n — új kulcs NEM kell

| Kulcs | `app_en.arb` | `app_hu.arb` |
|---|---|---|
| `practiceHubTitle` | 499. sor — „Practice hub" | 433. sor — „Gyakorló hub" |
| `songTrainerTitle` | 975. sor — „Song Trainer" | 909. sor — „Song Trainer" |

Mindkét kulcs mindkét nyelven létezik. **A `lib/l10n/` a TILOS zónában van.**

## 3. Scope

**Benne:**

1. `songTrainerV2Enabled` a `nonProd` predikátumra kötése a
   `FeatureFlags.forEnvironment` factoryban + a hozzá tartozó doc-comment
   (46–50. sor) átírása a valós, új határra.
2. Két belépési kártya a Learn fül `ListView`-jának **tetején** (a
   `_ContinueCard` FÖLÖTT), flagenként külön feltétellel.
3. Az E03-R01 rollout-őr **átirányítása** a production-határra (§5.2).
4. A `feature_flags_test.dart` környezet-mátrixának kiegészítése az új
   határral, és a NEM változó flagek (`aiTutor*`, `vision*`, `migratedLearn`)
   kerítés-tesztje.
5. A Learn belépési pontok widget-tesztje 2×2 flag-mátrixszal.
6. `practice_effect_listener.dart:23` avult doc-commentjének javítása és a
   `practice-engine-device-matrix.md` avult §fejléc-figyelmeztetésének
   frissítése (§2.4) + a mátrix Song Trainer soraival való bővítése.
7. A brief §10 handoff kitöltése.

**Kívül (ebben a körben TILOS):**

- **Bármely más flag értékének változtatása.** `aiTutorEnabled`,
  `aiTutorCloudEnabled`, `migratedLearnEnabled` és mind a 11 `vision*` flag
  értéke marad, ahogy van. Külön körök (GOV-05b, GOV-05c, §5.5).
- **A navigációs héj módosítása.** Nem jön új `NavigationDestination`, az
  `AppRoutes.shellTabs` nem változik, a `home_shell.dart` a tilos zónában van.
- **Új route, route-átnevezés, a router szerkezetének módosítása.**
  Az `app_router.dart` és az `app_route.dart` a tilos zónában van — minden
  szükséges route MÁR regisztrálva van a megfelelő flag mögött.
- **A legacy `/songs` képernyő, ikon vagy hivatkozás bármilyen változtatása**
  (ADR 0197 Döntés 4).
- **Új ARB-kulcs, ARB-módosítás, `lib/l10n/` bármely fájlja** (§2.7).
- **Új ADR** — a 0197 megvan, `docs/adr/` tilos zóna.
- Bármilyen érdemi változtatás a Practice vagy a Song Trainer feature belső
  kódjában (domain, application, repository, egyéb presentation fájl). Az
  egyetlen kivétel a `practice_effect_listener.dart` **doc-comment**-je
  (23. sor) — kód nem.
- `.github/`, `tool/`, `tools/` bármely fájlja.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**
(`tools/codex-signal.sh stopped`).

| Útvonal | Miért |
|---|---|
| `lib/app/config/feature_flags.dart` | a `songTrainerV2Enabled` sora + doc-comment |
| `lib/features/learn/screens/lesson_list_screen.dart` | a két belépési kártya |
| `lib/features/practice/presentation/practice_effect_listener.dart` | **CSAK a 23. sori avult doc-comment** (§2.4); kódsor nem módosítható |
| `test/app/feature_flags_test.dart` | környezet-mátrix + kerítés-teszt |
| `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart` | a rollout-őr átirányítása (§5.2) |
| `test/features/learn/lesson_list_screen_test.dart` | belépési pont 2×2 mátrix |
| `docs/manual-testing/practice-engine-device-matrix.md` | avult figyelmeztetés + Song Trainer sorok |
| `docs/rounds/e99-r01-gov-05a-practice-and-song-trainer-shipping-rollout.md` | §10 handoff |

**Tilos zóna:** `lib/app/routing/`, `lib/app/home_shell.dart`,
`lib/app/config/app_config.dart`, `lib/app/bootstrap/`, `lib/l10n/`,
`lib/features/song_trainer/` (a teszt-baseline kivételével),
`lib/features/practice/` (a fenti egy doc-comment kivételével),
`lib/features/vision/`, `lib/features/ai_tutor/`, `docs/adr/`, `.github/`,
`tool/`, `tools/`, `assets/`.

**A fájllista a tervezőt is köti:** ha a kör kivihetetlennek bizonyul a listán
belül, a helyes lépés a `stopped` jelzés indoklással — nem a lista csendes
tágítása.

## 5. Kötött architekturális döntések

Forrás: [ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md).
Ezektől új ADR nélkül nem lehet eltérni.

### 5.1 A flag-határ alakja

`songTrainerV2Enabled: nonProd` — ugyanaz a predikátum, amit a
`practiceEngineV2Enabled`, `diagnosticsEnabled` és `labModeAvailable` már
használ. **NEM** vezetünk be dart-define override-ot, **NEM** vezetünk be új
környezetet, és **NEM** vezetünk be külön „rollout stage" enumot.
Az alapértelmezett konstruktor paramétere (`this.songTrainerV2Enabled = false`,
18. sor) **változatlan marad**.

### 5.2 A rollout-őr átirányítása — a törlés NEM elfogadható feloldás

A `group('E03-R01 rollout guard')` csoport **megmarad** a
`legacy_fixture_parity_test.dart`-ban. Az első teszt átíródik úgy, hogy a
production-határt mérje; a második (default konstruktor) **érintetlen**.

**Nem elfogadható:** a csoport törlése; az első teszt törlése; a teszt
`skip`-elése; a teszt olyan átírása, amely már nem állít semmit
`AppEnvironment.production`-re. A rollout határa nem szűnt meg — elmozdult,
tehát az őrnek is el kell mozdulnia, nem eltűnnie.

### 5.3 A belépési pontok flagenként külön feltétel mögött

Két kártya, **két külön** `if`:

- Practice Hub kártya ⟵ `practiceEngineV2Enabled`, cél: `AppRoutes.practiceHub`
- Song Trainer kártya ⟵ `songTrainerV2Enabled`, cél: `AppRoutes.songTrainerLibrary`

**NEM** összevont predikátum (`if (v2Enabled)`), **NEM** egyetlen kártya két
gombbal. Ok: a rollback egy flaget érint, és a mérés cellánként elkülöníthető
(§6 A5).

A navigáció `context.push(...)` (nem `go`) — egyezik a Learn fül meglévő
AppBar-gombjainak mintájával (39. és 44. sor).

A kártyák **pinnelt widget-kulcsot** kapnak, mert erre mér az acceptance:

- `const Key('learn-entry-practice-hub')`
- `const Key('learn-entry-song-trainer')`

A feliratok a MEGLÉVŐ ARB-kulcsokból: `l10n.practiceHubTitle`, illetve
`l10n.songTrainerTitle` (§2.7). Új kulcs nincs.

A flageket a Learn képernyő ugyanúgy olvassa, ahogy a `learn_screen.dart:367–368`
teszi: `ref.watch(appConfigProvider).flags.<flag>` — a `LessonListScreen` egy
`ConsumerWidget`, tehát `watch` (nem `read`), hogy egy config-változás
újrarajzoljon.

### 5.4 Vizuális forma

A kártyák a meglévő Learn-listaelemek stílusát követik; a kör **nem** vezet be
új közös widgetet, nem nyúl a `core/widgets/`-hez, és nem módosítja a témát.
Ha a meglévő `_ContinueCard` mintája újrahasznosítható a fájlon belül, az a
preferált út.

### 5.5 Ez a kör a vision-t és a tutort NEM kapcsolja be

Mért blokkoló a vision-re: `assets/ml/model_manifest.json` `vision_models`
mindkét bejegyzése `status: "deferred"`, `sha256` csupa nulla, és a hivatkozott
`hand_landmarker_deferred.tflite` / `pose_landmarker_deferred.tflite` **nincs a
repóban** (`ls assets/ml/` → négy audio `.bin` + a manifest). A
`NativeHandLandmarkProvider` (`:77`) és a `NativePoseLandmarkProvider` (`:76`)
`deferred` bejegyzésre `AppResult.failure`-t ad. A flag bekapcsolása tehát
zsákutcát tenne láthatóvá. Az AI Tutor külön kör (GOV-05b).

### 5.6 Nyitott döntések — előre rögzített feloldással (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: >
      A legacy "Dalaim" (/songs) és az új Song Trainer könyvtár (/song-trainer)
      két külön dal-lista lesz a Learn fülön. Össze kell vonni őket?
    blocking: false
    resolution_policy: use_default
    default: >
      NEM. Mindkettő marad, változatlanul; a legacy AppBar-ikon nem módosul
      (ADR 0197 Döntés 4). Az összevonás termékdöntés, follow-up kör.

  - id: OD-02
    question: >
      A két belépési kártya a ListView tetejére kerüljön, vagy a napi kihívás
      alá?
    blocking: false
    resolution_policy: use_default
    default: >
      A ListView TETEJÉRE, a _ContinueCard FÖLÖTT. Ok: a rollout célja az
      elérhetőség, és a lista alján egy kártya mérhetően kevésbé találhatóé.
      A sorrend: [belépési kártyák] → [_ContinueCard] → [napi kihívás] → [tierek].

  - id: OD-03
    question: >
      A Learn belépési kártya megjelenjen-e production buildben, ha a flagje
      valamiért mégis igaz lenne?
    blocking: false
    resolution_policy: use_default
    default: >
      A kártya KIZÁRÓLAG a flagtől függ, NEM az AppEnvironment-től. A
      környezet-függés helye a factory (§5.1); a UI ne duplikálja a
      rollout-logikát — egy második, eltérő feltétel néma divergenciát okozna.

  - id: OD-04
    question: >
      A device-mátrix Song Trainer sorai milyen státusszal nyíljanak?
    blocking: false
    resolution_policy: use_default
    default: >
      PENDING. A valós eszközös bizonyíték a user menete; a PENDING sor NEM
      merge-kapu (az Epic 5 gyakorlata, HANDOFF §5).

  - id: OD-05
    question: >
      Ha a flag-flip a §2.6-ban felsorolt nyolc fájlon KÍVÜL is pirosra vált
      egy tesztet, mi a teendő?
    blocking: true
    resolution_policy: use_default
    default: >
      Ha a piros teszt az engedélyezett listán van → javítsd. Ha NINCS a
      listán → `stopped` jelzés, a piros teszt nevével és a nyers kimenettel.
      A fájllista csendes tágítása scope-sértés; a mérce lazítása (skip,
      `skip`, gyengébb matcher, assert törlése) semmilyen esetben nem
      megengedett.
```

## 6. Acceptance criteria

Minden pont mérhető. A „✅ zöld gate" önmagában NEM acceptance
([`docs/LESSONS.md`](../LESSONS.md) L09).

- [ ] **A1 — Környezet-mátrix a flagre.** `FeatureFlags.forEnvironment(env,
  accountEnabled: false).songTrainerV2Enabled` mind a **három**
  `AppEnvironment`-re, külön cellaként:

  | `AppEnvironment` | elvárt `songTrainerV2Enabled` |
  |---|---|
  | `development` | `true` |
  | `lab` | `true` |
  | **`production`** | **`false`** |

  A `production` cella az egyetlen, ami megkülönbözteti a helyes `nonProd`
  megoldást a hibás „mindenhol `true`"-tól. **A cellák külön `expect`-ek
  legyenek**, ne egy `AppEnvironment.values` fölötti ciklus — a ciklus egyetlen
  hibaüzenetbe olvasztja a három cellát.

- [ ] **A2 — A default konstruktor változatlan.** `const FeatureFlags(
  accountEnabled: false, diagnosticsEnabled: false, labModeAvailable: false)`
  → `songTrainerV2Enabled == false`. Ez a meglévő teszt
  (`legacy_fixture_parity_test.dart:265–267`) **érintetlen** marad.

- [ ] **A3 — A rollout-őr átirányítva, nem törölve.** A
  `group('E03-R01 rollout guard')` továbbra is létezik a
  `legacy_fixture_parity_test.dart`-ban, és **legalább egy** olyan `expect`-et
  tartalmaz, amely `AppEnvironment.production`-re `isFalse`-ot állít. A csoport
  törlése / a teszt `skip`-elése / minden production-állítás eltávolítása
  **nem elfogadható** (§5.2).

- [ ] **A4 — Kerítés: a többi flag NEM mozdult.** A `feature_flags_test.dart`
  mind a három környezetre állítsa, hogy `aiTutorEnabled`,
  `aiTutorCloudEnabled`, `migratedLearnEnabled` és `visionEnabled`
  **`false`**. (A 11 vision flag teljes mátrixát a
  `test/features/vision/vision_offline_regression_test.dart` már méri —
  annak **zölden kell maradnia, módosítás nélkül**; a tilos zónában van.)

- [ ] **A5 — Belépési pont 2×2 flag-mátrix.** A `LessonListScreen`
  widget-tesztje mind a négy cellára, `find.byKey`-jel mérve:

  | `practiceEngineV2Enabled` | `songTrainerV2Enabled` | `learn-entry-practice-hub` | `learn-entry-song-trainer` |
  |---|---|---|---|
  | `false` | `false` | `findsNothing` | `findsNothing` |
  | `true` | `false` | `findsOneWidget` | `findsNothing` |
  | `false` | `true` | `findsNothing` | `findsOneWidget` |
  | `true` | `true` | `findsOneWidget` | `findsOneWidget` |

  A két középső cella az egyetlen, ami megkülönbözteti a helyes, flagenként
  külön feltételt (§5.3) a hibás összevont predikátumtól. **Egyetlen cella
  sem hagyható el.**

- [ ] **A6 — A kártyák tényleg navigálnak.** A `true/true` cellában a
  `learn-entry-practice-hub` megnyomása után a router aktuális útvonala
  `AppRoutes.practiceHub` (`/practice`), a `learn-entry-song-trainer`
  megnyomása után `AppRoutes.songTrainerLibrary` (`/song-trainer`).
  Valódi `GoRouter` a teszt alatt; a puszta „a kártya létezik" állítás
  NEM elegendő (a route-regisztráció és a flag ugyanattól függ, tehát a
  hibás párosítás — pl. mindkét kártya ugyanarra az útvonalra mutat —
  csak így mérhető).

- [ ] **A7 — A production build viselkedése bizonyíthatóan változatlan.**
  `AppEnvironment.production` flagekkel pumpálva a Learn képernyőt **egyik**
  belépési kulcs sem található (`findsNothing` mindkettőre). Ez az A5
  `(false,false)` cellájától különbözik: ott kézzel adott flageken mérünk,
  itt a factory production-kimenetén.

- [ ] **A8 — Nincs új ARB-kulcs.** A diff `lib/l10n/` alatt **nulla** fájlt
  érint. Ha a megvalósításhoz mégis új string kellene → `stopped` (§5.3).

- [ ] **A9 — Avult állítások javítva.**
  (a) `practice_effect_listener.dart:23` doc-commentje már nem állítja, hogy
  „the production default of `practiceSessionHostProvider` is `null`" — a
  99–104. sori kód szerinti valóságot írja le.
  (b) `docs/manual-testing/practice-engine-device-matrix.md` fejléc-figyelmeztetése
  már nem állítja, hogy a Hub→Setup→Session út nem indítható (§2.4), és a
  mátrix tartalmaz Song Trainer V2 sorokat PENDING státusszal (OD-04).

- [ ] **A10 — A gate zöld**, a §7 szerinti egyetlen artefaktum-hívással,
  csővezeték nélkül.

- [ ] **A11 — A `continue_card_test.dart` a flageket kiköti, az állítása
  változatlan** (§0.0 R1). A fájl `_pump` segédje `appConfigProvider`
  override-ot kap, amelyben `practiceEngineV2Enabled` és
  `songTrainerV2Enabled` egyaránt `false`. A „recording a pass MOVES the
  card" teszt `findsNWidgets(2)` állítása és `reason:` szövege **szó szerint
  változatlan** marad; a fájl egyetlen `expect`-je sem gyengül, egyetlen
  teszt sem `skip`-elődik. A diff ebben a fájlban kizárólag a
  `_pump`/override-ot érinti.

> **Miért nincs alatta/rajta/fölötte cellahármas ebben a briefben:** a kör
> egyetlen acceptance-pontja sem numerikus küszöbre mér — minden mérce
> logikai (flag-érték, widget jelenléte, útvonal-egyezés, fájl érintettsége).
> A küszöb-hármas szabálya ([`docs/execution/08-round-brief.md`](../execution/08-round-brief.md)
> §6 4. pont) ezért nem alkalmazható; a helyére a **teljes** logikai
> cellamátrix lép: A1 három környezet-cellája és A5 mind a négy flag-párja
> kötelező, egyik sem hagyható el.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `songTrainerV2Enabled: true` (hard-kódolt, minden környezetben) | **A1 `production` cella** |
| A flip elmarad (marad `false`) | A1 `development` és `lab` cellák |
| A default konstruktor paramétere is `true`-ra írva | **A2** |
| Az E03-R01 őr törölve / `skip`-elve | **A3** (a csoport vagy a production-`expect` hiánya) |
| A flip „ráfut" a tutor/learn flagre is (pl. mind `nonProd`-ra írva) | **A4** |
| Összevont predikátum: `if (practiceV2 \|\| songTrainer)` | A5 `(true,false)` és `(false,true)` cellák |
| Összevont predikátum: `if (practiceV2 && songTrainer)` | A5 `(true,false)` és `(false,true)` cellák |
| A két kártya ugyanarra az útvonalra `push`-ol | **A6** (a második állítás) |
| A kártya feltétele `AppEnvironment`-re néz a flag helyett (OD-03 megsértése) | A5 `(true,true)` cella dev-flageken zöld marad, de **A7** és az A5 kézzel adott flagjei szétesnek |
| Új ARB-kulcs bevezetése | **A8** (`git diff --name-only \| grep '^lib/l10n/'` nem üres) |
| Az avult doc-comment / mátrix-figyelmeztetés érintetlen marad | **A9** (reviewer eldobható próbája: a mondat jelenléte grep-elhető) |
| A `continue_card_test.dart` `findsNWidgets(2)` → `findsOneWidget`-re gyengítve a flag-kikötés helyett | **A11** (reviewer eldobható próbája: `git diff` a fájlra — az `expect` sorainak változatlanságát a diff alakja mutatja) |

**Valódi-sértés próba (guard-teszthez, §10-ben dokumentálandó):** írd át
ideiglenesen a factory `songTrainerV2Enabled` sorát `true`-ra (a `nonProd`
helyett) → az **A1 `production` cellájának PIROSNAK kell lennie** → állítsd
vissza. Ha zöld marad, a mérce nem mér — jelentsd `stopped`-dal.

## 7. Kötelező ellenőrzések

**Egyetlen parancs, csővezeték és `tail` nélkül:**

```bash
tools/round-gate.sh test/app test/features/learn test/features/song_trainer/baseline test/features/auth test/features/settings test/features/vision/vision_offline_regression_test.dart
```

A script a `format` → `analyze` → `test <minden útvonal külön>` →
`architecture` lépéseket **külön processzként** futtatja, csonkítatlan
kimenettel. **Tilos** `| tail`, `| head`, `&&`-lánc vagy bármilyen szűrés —
a csővezeték elrejti a kilépési kódot, és a „minden gate zöld" jelentés
bizonyíthatatlanná válik ([`docs/LESSONS.md`](../LESSONS.md) L09).
A `flutter analyze` és a `flutter test` kézi láncolása ezen a gépen OOM-ot ad
(L05) — ezért is a script.

A teljes suite + randomizált property gate + APK a CI-ban
([ADR 0053](../adr/0053-ci-full-test-suite.md)) — azt az **orchesztrátor**
indítja; az implementer `gh`-t nem hív.

## 8. Implementációs sorrend

1. `feature_flags.dart`: a 63. sor `false` → `nonProd`, és a 46–50. sori
   doc-comment átírása az ADR 0197 Döntés 1 szerinti valós határra.
2. `feature_flags_test.dart`: A1 három külön cellája + A4 kerítés + A7.
3. `legacy_fixture_parity_test.dart`: az E03-R01 őr átirányítása (A3); a
   default-konstruktor teszt (A2) **érintetlenül** hagyása.
4. Itt futtasd a gate-et először — a flag-oldal önmagában zöld kell legyen,
   mielőtt UI-hoz nyúlsz.
5. `lesson_list_screen.dart`: a két belépési kártya (§5.3, OD-02 sorrend).
6. `lesson_list_screen_test.dart`: A5 mátrix + A6 navigáció.
7. `practice_effect_listener.dart` doc-comment (A9a) +
   `practice-engine-device-matrix.md` (A9b).
8. A valódi-sértés próba lefuttatása és visszaállítása (§6.1).
9. Záró gate + §10 handoff + `tools/codex-signal.sh done`.

## 9. Kockázatok

1. **A flip a §2.6-ban nem látott tesztet is pirosra válthat.** Feloldás:
   OD-05 (listán belül javítsd, listán kívül `stopped`).
2. **A Song Trainer V2 valós eszközön még sosem futott.** A zöld gate itt
   szintetikus; a végső elfogadás a user menete (HORIZON-szabály). A
   device-mátrix PENDING sorai ezt teszik láthatóvá — nem merge-kapu.
3. **Két dal-könyvtár egymás mellett** (OD-01) — vállalt UX-adósság,
   follow-up.
4. **A `development` környezet is bekapcsolja a Song Trainert**, tehát minden
   CI dev-build hordozza. Szándékos (ADR 0197 Következmények); a
   production-határt az A1 `production` cellája és az A3 őr méri.
5. **A Learn fül zsúfolttá válhat** két új kártyával a lista tetején. Elfogadott:
   a felfedezhetőség most fontosabb (OD-02), a finomhangolás UI-kör tárgya.

## 10. Implementation handoff — a Codex tölti ki

### Állapot: STOPPED — OD-05

Az implementáció a §8 1–8. lépéséig jutott, de a záró gate a nem engedélyezett
`test/features/learn/continue_card_test.dart` fájlban talált hibát. A brief
OD-05 szabálya miatt ezt a tesztet nem módosítottam és a kört `stopped`
jelzéssel zártam.

### Fájlonkénti összefoglaló

- `lib/app/config/feature_flags.dart`: a Song Trainer V2 factory-értéke
  `nonProd`; a doc-comment az új, production-on kívüli rollout-határt írja le,
  miközben a konstruktor defaultja változatlanul `false`.
- `test/app/feature_flags_test.dart`: A1 külön development/lab/production
  cellái és az A4 kerítés (`aiTutor*`, `migratedLearn`, `visionEnabled`).
- `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`: az
  E03-R01 rollout-őr production-határra irányítva; a default-konstruktor
  tesztje érintetlen.
- `lib/features/learn/screens/lesson_list_screen.dart`: két külön flag-gated,
  pinnelt kulcsú Learn-belépőkártya, `context.push` a megfelelő route-ra.
- `test/features/learn/lesson_list_screen_test.dart`: A5 mind a négy cellája,
  A6 két GoRouter-útvonala és A7 production-factory cellája.
- `lib/features/practice/presentation/practice_effect_listener.dart`: csak a
  23. sori avult doc-comment javult.
- `docs/manual-testing/practice-engine-device-matrix.md`: a már megvalósult
  Practice host-wiringet írja le, és Song Trainer V2 PENDING sorokat ad hozzá.

### Acceptance-bizonyíték és futtatott parancsok

- A1/A4: `/home/ubuntu/flutter/bin/flutter test test/app/feature_flags_test.dart`
  → `+9: All tests passed!` A három külön cella development=`true`, lab=`true`,
  production=`false`; a kerítés mindhárom környezetben false értékeket mér.
- A2/A3: `/home/ubuntu/flutter/bin/flutter test test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`
  → `+9: All tests passed!`; az E03-R01 csoport production `isFalse`-ot mér,
  a default-konstruktor tesztje változatlan.
- A5/A6/A7: `/home/ubuntu/flutter/bin/flutter test test/features/learn/lesson_list_screen_test.dart`
  → `+9: All tests passed!`; a 2×2 cellák, mindkét route-assert és a production
  factoryból épített rejtési cella zöld.
- A8: a diff nem érint `lib/l10n/` fájlt.
- A9: a doc-commentből kikerült a production-null állítás; a device-mátrix
  Practice útvonala elérhetőként, a Song Trainer sorok PENDING-ként szerepelnek.
- A10: nem teljesült. A kötelező gate a következő, listán kívüli teszten állt meg:

  ```text
  test/features/learn/continue_card_test.dart:
  recording a pass MOVES the card — the list rebuilds on progress change

  Expected: exactly 2 matching candidates
    Actual: Found 1 widget with text "Two-Chord Change"
  the Continue card must follow the new progress
  ```

  A gate addigi tényleges eredménye: `format` zöld (1214 fájl, 0 változás),
  `analyze` zöld (`No issues found!`), `test test/app` zöld (`+63: All tests
  passed!`), majd `test test/features/learn` piros, kizárólag a fenti teszt.

### Valódi-sértés próba (§6.1)

Ideiglenesen `songTrainerV2Enabled: nonProd` helyett
`songTrainerV2Enabled: true` szerepelt a factoryban. Ezután:

```text
/home/ubuntu/flutter/bin/flutter test test/app/feature_flags_test.dart --name "remains disabled in production"
Expected: false
  Actual: <true>
test/app/feature_flags_test.dart:84
Some tests failed.
```

A factory sora ezután visszaállt `songTrainerV2Enabled: nonProd`-ra, és a
teljes `test/app/feature_flags_test.dart` futás ismét `+9: All tests passed!`.

### OD-k, eltérés, nem futtatott ellenőrzések és follow-up

- OD-01/OD-02/OD-03/OD-04: a brief defaultjait követtem: két külön Learn-kártya
  a lista tetején, kizárólag saját flaggel, a Song Trainer device-sorok PENDING-ek.
- OD-05: alkalmazva. A `continue_card_test.dart` nincs az allowed_paths listán,
  ezért nincs javítás vagy mérce-lazítás.
- Eltérés: nincs szándékos eltérés; a scope a nyolc megengedett fájlon belül maradt.
- Nem futtatott: a gate hátralévő tesztútvonalai és az architecture lépése a
  `test/features/learn` első piros tesztje miatt nem indulhattak el. CI/APK-t
  az orchestrátor indít, és megállított körhöz nem indítandó.
- Follow-up: a briefet bővíteni kell a `test/features/learn/continue_card_test.dart`
  fájllal, vagy product döntéssel meg kell erősíteni az új kártyák és a Continue
  card viewport-szerződését; csak ezután folytatható a javítás.

> Minden viselkedési állításhoz add meg a tesztet, ami bizonyítja. Állítás
> teszt nélkül = bemondás.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e99-r01-gov-05a-practice-and-song-trainer-shipping-rollout-review.md`
