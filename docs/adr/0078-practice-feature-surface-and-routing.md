# ADR 0078 — A Practice feature belépési felülete: flag mögötti routing, tipizált argumentum és a Setup parancs-határa

**Státusz:** elfogadva (E02-R12 pre-flight, 2026-07-31).
Épít az [ADR 0059](0059-route-catalogue-and-onboarding-redirect.md) (route-katalógus
+ onboarding-redirect), [ADR 0065](0065-practice-engine-v2-parallel-rollout.md)
(párhuzamos rollout + flagek), [ADR 0068](0068-practice-domain-model-contracts.md)
(domain-szerződések), [ADR 0070](0070-builtin-practice-catalog-contract.md)
(katalógus) és [ADR 0077](0077-practice-session-controller.md) (session controller)
döntéseire.
Kör: [`docs/rounds/e02-r12-practice-hub-and-setup.md`](../rounds/e02-r12-practice-hub-and-setup.md).

## Kontextus

Tizenegy kör után a Practice Engine V2 **teljesen láthatatlan**: mérve (`main` @
`f2fc758`) a `lib/features/practice/` alatt nincs `presentation/` könyvtár,
nincs `public.dart`, és a `lib/l10n/app_en.arb` **273 kulcsa** között
**egyetlen `practice*` prefixű sincs**. A feature három rétege (20 domain-modell
+ 2 service, 10 application-fájl, 2 data-fájl + 4 adapter) készen áll, de
felhasználó nem éri el.

Ez a kör nyitja meg a felületet — Hub + Setup, **pontozó UI nélkül**. Négy
mérési eredmény határozza meg a döntéseket, és mindegyik ellentmond egy
kézenfekvő feltételezésnek:

1. **Nincs `practiceSessionControllerProvider`.** Az R11 szándékosan nem
   definiálta (`practice_session_providers.dart` záró megjegyzése: „The Kör 13
   pre-flight will define the auto-dispose `family`"). A Setup tehát **nem tud**
   a provider-gráfból controllert kérni.
2. **A `PracticeSessionConfig`-ban nincs `meter` mező** — a `Meter` a
   `PracticeDefinition`-é (`practice_definition.dart:44`). A Setup az
   ütemmutatót *megjeleníti*, nem állítja.
3. **A `PracticeSessionConfig`-ban nincs Speed-Builder mező** — a fájl doc-je
   kimondja: „Speed Builder policy is intentionally absent until its dedicated
   round", és az SDD **Kör 17** hozza a `SpeedBuilderPolicy` validátort.
4. **A loop nem bool, hanem `loopCount` (1–32)**
   (`practice_session_config.dart:33-34`).

## Döntés

### 1. A Practice felület flag mögött regisztrálódik

A `/practice` és `/practice/setup` route **csak akkor** kerül a `GoRouter`
`routes` listájába, ha `appConfigProvider.flags.practiceEngineV2Enabled` igaz
(non-prod `true`, production `false` — `feature_flags.dart`, dart-define
override nincs).

Flag OFF mellett a `/practice*` cím a router **meglévő** szabálya szerint
kezelődik: `onException: (_, _, router) => router.go(AppRoutes.live)`
(`app_router.dart:40`). Tehát fehér képernyő és kivétel helyett a Live jön —
és ez a viselkedés **nem új kód**, hanem a meglévő ág mérése.

**Miért nem `redirect`-tel:** a `redirect` minden navigációnál fut és az
onboarding-redirect tulajdona (ADR 0059); egy második, feltételes ág ott
összefonódna vele. A route-lista feltételes építése lokális és a flag
elolvasásán kívül nulla futásidejű költségű.

### 2. A Practice NEM lesz shell-tab ebben a körben

Az `AppRoutes.shellTabs` **ötelemű marad** (`live`, `analyze`, `learn`,
`library`, `settings`). A Hub teljes képernyős route. A navigációs hely a
rollout döntés része (Kör 19/20) — addig a felület fejlesztői buildben
mély-linkkel érhető el, és ez a kör **nem** ad neki belépőt a meglévő
képernyőkről.

**Következmény, kimondva:** a felület egy fejlesztői buildben is csak
mély-linkkel érhető el. Ez szándékos: a rollout-döntésig nem akarunk
félig kész felületet a navigációban.

### 3. Tipizált route-argumentum, feloldás a katalógusból

A Setup a definíció **azonosítóját** kapja query-paraméterként
(`/practice/setup?id=<definitionId>`), és a képernyő oldja fel a
`practiceCatalogRepositoryProvider.byId(id)`-vel. A `byId` szerződése
(`practice_catalog_repository.dart`) kimondja: ismeretlen id → `null`,
**soha nem** dob és **soha nem** tippel.

Feloldhatatlan (hiányzó vagy ismeretlen) azonosító → **lokalizált hibaállapot +
„vissza a Hubra" út**. Sem kivétel, sem üres képernyő.

**Miért query-paraméter és nem path-szegmens:** a `byId` `null`-ja így a
képernyő belső hibaállapota marad; path-szegmensnél a `GoRouter` mintaillesztése
és az `onException` Live-fallbackja nyelné el a hibát, és a felhasználó
magyarázat nélkül másik képernyőn kötne ki.

### 4. A UI nem definiál validációs szabályt

Minden mező-korlát a domainből jön:

| Setup-vezérlő | Igazságforrás | Mért határ |
|---|---|---|
| BPM | `Tempo.minimumBpm` / `maximumBpm` + `Tempo.validate()` | 30–300 **zárt** |
| count-in ütem | `PracticeSessionConfig.minimumCountInBars` / `maximumCountInBars` | 0–4 **zárt** |
| loop | `PracticeSessionConfig.minimumLoopCount` / `maximumLoopCount` | 1–32 **zárt** |
| ütemmutató | `PracticeDefinition.meter` | **kijelzés**, nem beállítás |
| scoring profil | `PracticeDefinition.scoringProfile.id` | **kijelzés**, seedeli a configot |

A Start gomb tiltása **ugyanannak** a `PracticeSessionConfig.validate()`
hívásnak az eredményén áll, amit a `compilePracticeTarget` is lefuttat
(`practice_target_compiler.dart:32-39`). A UI legfeljebb *megjeleníti* a
`PracticeValidationCode`-hoz tartozó lokalizált szöveget — küszöböt nem másol
és nem szigorít.

### 5. A Start parancs-határa: `PracticePrepareSink`

Mivel `practiceSessionControllerProvider` nem létezik (Kontextus 1.), a Start
gomb a validált configból **`PreparePractice` parancsot állít elő**, és azt egy
injektálható **nyelőnek** adja át:

```dart
typedef PracticePrepareSink = void Function(PreparePractice command);
final practicePrepareSinkProvider = Provider<PracticePrepareSink>(...);
```

- **Production alapértelmezés:** a parancs tényeit (definitionId, effectiveTempo,
  countInBars, loopCount) a `appLoggerProvider`-en keresztül naplózó nyelő.
  **Nem** no-op: a hívás nyomot hagy, tehát a kör után egy fejlesztői buildben
  a Start megnyomása mérhető.
- **Teszt:** felülírva egy hívásnaplózó fake-kel — így az „pontosan **egy**
  `PreparePractice`" állítás gépi mérce, nem szöveges ígéret.
- **Kör 13:** ugyanez a provider mutat majd a session-controllerre. A Setup
  hívási helye **nem** változik — a nyelő cseréje a teljes bekötés.

A Setup ebben a körben **nem navigál** (a session-képernyő még nem létezik), és
ezt a tényt a felhasználó felé is jelezni kell: a Start megnyomása után a
képernyő marad, és lokalizált visszajelzést ad (a kör nem hazudik befejezett
folyamatot).

### 6. Két SDD Kör-12 tétel tudatosan a Kör 17-be csúszik

Az SDD Kör 12 feladatlistája tartalmazza a „Speed Builder entry" (Hub) és
„Speed Builder config" (Setup) tételeket, a teszt-listája a „Speed Builder
validation"-t. **Ez a kör ezeket nem valósítja meg**, mert:

- a `PracticeSessionConfig`-ban nincs hova tenni őket (Kontextus 3.), és a
  `domain/**` ebben a körben zárolt zóna;
- a `target < start` ordering-szabály **új validációs szabály** volna, amit a
  §4 döntés kifejezetten tilt a UI-ban;
- a szabály tulajdonosa az SDD szerint a Kör 17 `SpeedBuilderPolicy` validátora.

Ha a Setup most kapna egy saját Speed-Builder szabályt, a Kör 17-ben **két**
igazságforrás versenyezne — pontosan az a duplikált szerződés, amit az
[ADR 0065](0065-practice-engine-v2-parallel-rollout.md) rollout-modellje kizár.

**Következmény:** a Kör 17 briefjének a Speed Builder **UI-felületét is** magába
kell foglalnia, nem csak a policy-t. Ez a kör-jelentésben és a HANDOFF
follow-up listáján rögzített kötelezettség.

### 7. Accessibility és lokalizáció alapkövetelmény, nem utólagos csiszolás

- Minden user-facing szöveg ARB-ból, **mindkét** nyelven kitöltve
  (`test/core/l10n_parity_test.dart` gépi őr: azonos kulcshalmaz + üres
  fordítás tilos).
- Minden interaktív elem **címkéje és akciója EGY** szemantikus node-on — a
  `test/features/chords/chord_tile_a11y_test.dart` (r130/r131) mért tanulsága:
  a címke tap-akció nélkül fél-törött vezérlő.
- Minimum 48×48 dp érintőfelület; a jelentés nem épülhet **csak** színre.
- 200%-os `textScaler` és 320×568 / 915×412 méret mellett nincs
  RenderFlex-túlcsordulás (`test/core/screen_size_guard_test.dart`).

### 8. Nincs business logic a presentation rétegben

A két képernyő forrása nem tartalmaz pontozást, matchert, target-fordítást,
`Stopwatch`-ot és `Timer(`-t, és nem importál `domain/service/`-t. **Egyetlen
kivétel**, a ház mintája szerint (`progress_screen.dart:30`,
`streak_screen.dart:29`): a Hub injektálható `DateTime? now` paramétere és annak
`now ?? DateTime.now()` alapértelmezése — ez az egy hívás a Daily Challenge
napjához kell, tesztből felülírható, és a Setup képernyőn **nulla** példány
megengedett.

## Következmények

**Jó:** a feature először látható; a flag OFF út a router meglévő,
mért ágán fut; a Setup nem duplikál validációt; a Start határa egyetlen
provider-cserével válik teljes bekötéssé a Kör 13-ban.

**Ár:** a Start ebben a körben nem indít sessiont — a felület fél lépés, és ezt
a UI-nak őszintén kell kommunikálnia. A Speed Builder felület egy körrel
későbbre csúszik, ami a Kör 17 scope-ját növeli.

**Kockázat:** a `practicePrepareSinkProvider` production alapértelmezése egy
naplózó nyelő; ha a Kör 13 elfelejti kicserélni, a Start csendben csak naplóz.
Ellenszer: a Kör 13 briefjének acceptance-cellája legyen a nyelő cseréjének
mérése, és a provider doc-commentje nevezze meg a Kör 13-at.
