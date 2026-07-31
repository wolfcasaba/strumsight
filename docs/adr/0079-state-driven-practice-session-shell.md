# ADR 0079 — Állapotvezérelt practice-session shell: presentation-oldali session-határ, parancs-táblás kilépés, egyszer ható effektek

**Státusz:** elfogadva (E02-R13 pre-flight, 2026-07-31).
Épít az [ADR 0073](0073-practice-session-state-machine.md) (állapotgép + átmenettábla),
[ADR 0074](0074-practice-observation-gateway.md) (capture-aktivációs tábla),
[ADR 0077](0077-practice-session-controller.md) (session controller) és
[ADR 0078](0078-practice-feature-surface-and-routing.md) (flag mögötti routing,
parancs-határ a Setupon) döntéseire.
Kör: [`docs/rounds/e02-r13-session-ui-shell.md`](../rounds/e02-r13-session-ui-shell.md).

## Kontextus

Az Epic 2 tizenkét köre után a Practice V2-nek **van** állapotgépe, controllere,
gateway-e, matchere és négy scorere — de **nincs session-képernyője**. A
felhasználó a Hubról a Setupra jut, ott a Start egy `PreparePractice`
parancsot ad egy injektálható nyelőbe (ADR 0078 §5), és **ott a felület
véget ér**.

Ez a kör a közös session-héjat hozza. A héj tétje nem a látvány (a
mode-specifikus vizuál a Kör 14–16), hanem az **életciklus**: ki birtokolja az
órát, ki állítja le a mikrofont, és mi történik, amikor a felhasználó
visszalép vagy a telefon háttérbe kerül.

A döntéseket **hat mérés** határozza meg, és mindegyik ellentmond egy
kézenfekvő feltételezésnek. Minden mérés `main` @ `bc7beb8`:

1. **`practiceSessionControllerProvider` ma sem létezik.** Az R11 a Kör 13
   pre-flightjára hagyta (`practice_session_providers.dart:110-114`), a valódi
   `PracticeObservationGateway` provider pedig a `data/` réteg + az audio-lease
   bekötését igényli (uo. 17–21. sor). Ez a kör **nem** nyúlhat az
   `application/`-höz (kör-brief §4 tilos zóna).
2. **A `PreparePractice` parancsot a reducer KIZÁRÓLAG `idle` és
   `permissionRequired` állapotból fogadja el**
   (`practice_session_reducer.dart:238-241`). A `GrantPermission` viszont
   `permissionRequired → preparing`-be visz **anélkül, hogy bármi újrafordulna**
   (uo. 256–268), és a controller az újrafordítást **csak** `PreparePractice`
   bemenetre futtatja (`practice_session_controller.dart:222-224`). Tehát a
   `GrantPermission` a felületről **zsákutca**.
3. **A `RetryPractice` ugyanígy zsákutca:** `failed → preparing`
   (`practice_session_reducer.dart:502-518`), de `preparing`-ből a
   `PreparePractice` már **elutasított** — a merge-elt R11 controller nem
   fordít újra.
4. **A `CancelPractice`, `PausePractice` és `FinishPractice` tisztán az
   `allowedTransitions` táblán kapuzódik** (uo. 471, 487, 324) — nincs extra
   feltétel. Ebből a kilépési szabály **levezethető**, nem kitalálandó:
   cancel-elhető `permissionRequired`, `ready`, `countIn`, `running`, `paused`;
   `preparing`, `finishing` és a három terminális állapot **nem**.
5. **A terminális takarítás már megtörtént.** A controller
   `completed`/`cancelled`/`failed` státuszon lefuttatja a
   gateway-leállítást és az erőforrás-takarítást
   (`practice_session_controller.dart:249-255`) — ezekben az állapotokban a
   kilépéskor kiadott parancs nem takarítana, csak **elutasítva** eldobódna.
6. **A pontszám nincs a state-en.** A `PracticeSessionState`-nek nincs
   score-mezője; az élő aggregátum a controller `liveScore` gettere
   (`practice_session_controller.dart:144`), típusa a `domain/service/`
   alatt lakó `PracticeScoreAggregation`.

Egy hetedik, negatív mérés: **haptika-beállítás nincs** az appban (a
`lib/features/settings/` és a `lib/core/` alatt nulla `haptic` találat), a
legacy képernyők közvetlenül hívják a `HapticFeedback` statikusait
(`learn_screen.dart:484`, `live_screen.dart:114`, `tuner_screen.dart:58`).

## Döntés

### 1. A képernyő állapotvezérelt — egyetlen igazságforrás a session-state

A képernyő **nem tart** párhuzamos session-állapotot: nincs saját „isPlaying"
bool, nincs saját eltelt idő, nincs saját pontszám. Minden megjelenített
érték a kapott `PracticeSessionState` (illetve az élő pontszám-pillanatkép)
függvénye.

`Ticker`, `Timer`, `Stopwatch` **kizárólag** renderelési interpolációra
használható, és soha nem hajthat scorert, órát vagy státuszváltást. A legacy
`learn_screen.dart` pontosan az ellenkezőjét csinálja (saját `Ticker`, a
`_onTick` hajtja a scorert és az időt, a widget példányosít `LessonScorer`-t és
`Metronome`-ot) — az a fájl **ellenpélda, nem minta**.

### 2. A session-határ a presentation rétegben van (`PracticeSessionHost`)

Mivel a controller-provider nem létezik és az `application/` ebben a körben
tilos zóna (1. mérés), a képernyő **nem** hivatkozik közvetlenül a
`PracticeSessionController` osztályra. A határ egy presentation-oldali,
minimális interfész:

```dart
abstract interface class PracticeSessionHost {
  Stream<PracticeSessionState> get states;   // broadcast
  PracticeSessionState get state;            // aktuális pillanatkép
  Stream<PracticeSessionEffect> get effects; // broadcast
  int? get liveOverallPerMille;              // egész ezrelék vagy null
  void send(PracticeSessionCommand command); // csak parancs mehet be
}
```

Három tulajdonsága kötött:

- **Csak parancs mehet be.** A `PracticeSessionSignal` ág (`ClockAdvanced`,
  `PreparationSucceeded`, …) a controlleré — a felület környezeti tényt nem
  gyárt.
- **A pontszám egész ezrelékben, primitívként jön át** (6. mérés) — így a
  presentation nem importál `domain/service/`-t.
- **A `states`/`effects` broadcast**; a képernyő az `initState`-ben iratkozik
  fel és a `dispose`-ban mond le.

**Production default: `null`.** A `practiceSessionHostProvider` alapértéke
`null`, mert ebben a körben nincs, ami valódi controllert állítson össze (1.
mérés). A képernyő ilyenkor **lokalizált „a session még nem elérhető"
állapotot** renderel — nem üres képernyőt, nem kivételt. A valódi host
(controller + gateway + audio-lease bekötés) a Kör 14+ dolga; ez ADR-szintű
kötelezettség, nem opció.

**Miért nem `PracticeSessionController` közvetlenül:** azon kívül, hogy a
fájlja tilos zóna, a controller `dispatch`-e `PracticeSessionInput`-ot vesz és
`Future<void>`-ot ad — a felület mindkettőnél szűkebb szerződést kap, így a
„a widget jelet küldött be" hiba **fordítási hiba**, nem review-lelet.

### 3. A widget nem példányosít motort, és az effekt-kimenet injektálható

A presentation rétegben **nincs** `LessonScorer`, `StrumEngine`, `Metronome`,
matcher, gateway vagy audio-lease. Az effektek végrehajtása egy injektálható
kimeneten megy:

```dart
abstract interface class PracticeFeedbackOutput {
  void haptic();
  void countInClick(int beatIndex);
  void announce(String message);
  void openPermissionSettings();
}
```

Production default: `HapticFeedback.mediumImpact()`,
`SystemSound.play(SystemSoundType.click)`,
`SemanticsService.announce(...)`, `openAppSettings()` — mind
platform-hívás, **nulla saját erőforrás-tulajdonlás**. A count-in valódi
metronóm-hangja az audio-bekötés körével jön; addig a rendszer-kattanás az
őszinte minimum.

A haptika `practiceHapticsEnabledProvider` (bool) mögött kapuzódik,
**alapértéke `true`** (7. mérés: beállítás ma nincs; a hiánya nem jelenthet
néma haptikát).

### 4. A kilépés parancs-táblán megy, és a tábla `const`

A rendszer-back, az AppBar-vissza és a `PopScope` út **ugyanazt** a
kilépés-kezelőt hívja. A kezelő két `const` táblát olvas:

| Státusz | Kilépéskor kiadott parancs | Megerősítés kell? |
|---|---|---|
| `idle` | — | nem |
| `preparing` | — (a tábla nem enged cancelt) | nem |
| `permissionRequired` | `CancelPractice` | nem |
| `ready` | `CancelPractice` | nem |
| `countIn` | `CancelPractice` | **igen** |
| `running` | `CancelPractice` | **igen** |
| `paused` | `CancelPractice` | **igen** |
| `finishing` | — (a kilépés **blokkolt**, amíg a státusz tart) | — |
| `completed` · `cancelled` · `failed` | — (a takarítás megtörtént, 5. mérés) | nem |

A parancs-oszlop **levezetett**: pontosan azok az állapotok kapnak
`CancelPractice`-t, amelyekből az `allowedTransitions` a `cancelled`-be enged
(4. mérés). Egy elutasítás-ba futó parancs kiadása tilos: az néma no-op, ami
„megtörtént a takarítás" látszatát kelti.

**A kilépés legfeljebb egy parancsot ad ki.** Egy kilépés-folyamatban lévő
képernyő további kilépési kísérlést nem indít újra (egyszeri kapu).

**A `finishing` blokkol:** a session ekkor épp az eredményt zárja le, és a
`finishing`-ből nincs `cancelled` él. A back gomb ilyenkor nem tesz semmit; a
státusz továbblép `completed`/`failed`-be, és onnan a kilépés szabad.

### 5. Megerősítés csak futó sessionből

`countIn`, `running`, `paused` állapotban a kilépés lokalizált megerősítést
kér. **Elutasított megerősítés = nulla parancs és a képernyő marad** — ez a
cella az, ami a néma parancs-kiadást szokta elfedni, ezért gépi mérce méri.

### 6. A recoverable hiba nem dob ki; a `failed` panel egyetlen parancsa a `RetryPractice`

`ShowRecoverableError` → panel a képernyőn belül, a session **marad** (SDD
§21.6). A panel a hiba lokalizált üzenetét mutatja (failure-kód alapján), és
elbocsátható.

A `failed` **státusz** panelje két utat kínál: „újra" → `RetryPractice`, és
„kilépés" → a képernyő elhagyása parancs nélkül (5. mérés).

**Kimondott korlát (3. mérés):** a `RetryPractice` a merge-elt R11
controllerben `preparing`-be visz, de az újrafordítás nem indul el, mert a
`PreparePractice`-t a reducer `preparing`-ből elutasítja. A `failed → futó
session` út tehát **ma nem zárul**; a lezárása annak a körnek a feladata,
amelyik a `practiceSessionControllerProvider`-t definiálja (a host
újraépítheti a sessiont). Ez a kör ezt a hiányt **nem takarja el** — nem ad ki
látszatparancsot, és nem ígér a felületen olyat, amit nem mértünk.

### 7. Az engedélykérő út egyetlen parancsa a `PreparePractice`

`permissionRequired` állapotban az „engedély megadása" akció a
`PreparePractice(state.definition!, state.config!)` parancsot adja ki — ez az
egyetlen, amit a reducer ebből az állapotból elfogad, és ez az, ami a
controllernél ténylegesen újrakéri az engedélyt
(`practice_session_controller.dart:364-372`).

**A `GrantPermission` a felületről tilos** (2. mérés): `preparing`-be vinne,
ahonnan már semmi nem indítja újra a fordítást — néma beragadás.

A `ShowPermissionSettings` effekt az injektálható kimenet
`openPermissionSettings()` hívásává fordul; a képernyő emellett a meglévő
`MicPermissionBanner`-t is mutatja, amelynek saját, kézi útja is van.

### 8. Az effekt pontosan egyszer hat

Az effekt-előfizetés az `initState`-ben jön létre és a `dispose`-ban szűnik
meg — **soha nem a `build()`-ben**. Minden effekt pontosan egyszer dolgozódik
fel; újraépítés nem játssza le újra a haptikát és nem navigál másodszor.

A navigációs kérés (`NavigateToResult`) egy injektálható nyelőn megy ki
(az ADR 0078 §5 `PracticePrepareSink` mintája szerint), és a képernyő
**egyszeri kapuval** védi: a második `NavigateToResult` ugyanarra a sessionre
**nem** ad újabb kérést. A Result képernyő a Kör 18; addig a képernyő
lokalizált placeholdert mutat, amely **pontszámot nem állít**.

A `dispose()` után érkező effekt nulla hívást és nulla kivételt eredményez.

### 9. Az életciklus továbbítva, nem értelmezve

Háttérbe kerüléskor (`isBackgroundLifecycleState`, `app_lifecycle.dart:20`) a
képernyő `PausePractice(cause: PauseCause.interruption)` **parancsot** ad ki —
és csak azokból az állapotokból, ahonnan a tábla a `paused`-ot engedi
(`countIn`, `running`). Minden más állapotban **nulla parancs**.

**Automatikus resume nincs.** Előtérbe visszatéréskor a képernyő semmit nem
küld: a mikrofon visszakapcsolása a felhasználó döntése. (A capture a
`practiceCaptureActiveByStatus` táblán a `paused`-ban ki van kapcsolva — ADR
0074 —, tehát a szünet valódi.)

A képernyő wakelockot **nem** vesz fel ebben a körben: az erőforrás-tulajdonlás
a valódi session-bekötés körével kerül helyére.

### 10. Reduced motion, nem-csak-szín, ARB

- `MediaQuery.disableAnimations == true` → nincs animált átmenet; a count-in
  overlay statikus, de az **információt nem veszti** (a hátralévő ütések száma
  látszik).
- Státusz/verdikt jelentése soha nem csak színnel: szöveg vagy ikon is hordozza.
- Minden vezérlő ≥ 48×48 dp, címke és akció **egy** szemantikus node-on.
- Minden felhasználó-látható szöveg ARB-ból, `en` és `hu` egyaránt; a
  státuszok neve **nem** szivároghat ki nyers enum-névként.

## Következmények

**Nyerünk:**

- A session-héj a merge-elt állapotgép mért szemantikáját követi, nem egy
  réteg-diagram feltételezését — a három zsákutca (GrantPermission,
  RetryPractice, elutasított CancelPractice) a felületről nem érhető el.
- A kilépés `const` táblás, tehát cellánként tesztelhető; a „néma no-op
  parancs" osztály szerkezetileg kizárt.
- A presentation nem importál `domain/service/`-t és nem példányosít motort,
  így a Kör 14–16 mode-specifikus nézetei ugyanerre a héjra épülhetnek.

**Fizetünk:**

- A production úton a képernyő **még nem futtat sessiont** (host = `null`) —
  a felület a flag mögött van, a valódi bekötés külön kör. Ez tudatos:
  a bekötés `application/` + `data/` + audio-lease döntés, nem UI-döntés.
- A `failed → futó session` út nyitva marad (6. döntés) — nyilvántartott
  hiány, nem elrejtett hiba.
- A count-in hangja átmenetileg rendszer-kattanás.

**Nyitott, nevesített follow-upok:**

1. `practiceSessionControllerProvider` + valódi `PracticeSessionHost`
   (controller + `LivePracticeObservationGateway` + `AudioOwner.practice`
   lease) — az R11 review §11.4/4 tétele.
2. A `failed`-ből induló újrafordítás lezárása (3. mérés).
3. Valódi count-in metronóm-hang és a haptika felhasználói beállítása.
4. A Setup → session route navigáció bekötése (a Setup fájlja ebben a körben
   tilos zóna).
