# E15-R06 review — Setlist + Progress képernyők design-rendszer migrációja

- **Kör:** `E15-R06`, branch `sonnet-impl/e15-r06-legacy-song-library-progress-migration`
- **Reviewer:** Claude (orchestrátor, read-only) + `flutter-reviewer` + `flutter-devil-advocate` (a brief `risk = "high"` miatt KÖTELEZŐ mindkettő)
- **Review-lt HEAD:** `9e4f95d6` (diff: `origin/main...HEAD`, 11 fájl, +862/−162)
- **Dátum:** 2026-08-29

## VÉGSŐ DÖNTÉS (1. forduló): CHANGES REQUESTED — 1 BLOCKER, 2 MAJOR, 3 MINOR

A kör munkája alapvetően jó: a scope pontos, a G1–G4 örökölt hibaosztályok mind
tiszták, a §10 handoff őszinte és mérésekkel alátámasztott, a valódi-sértés
próba REPRODUKÁLHATÓ. A megállító lelet egy MÉRT regresszió, amit a kör saját
cellái azért nem látnak, mert a `flutter_test` alapértelmezett viewportja
(800×600) szélesebb minden telefonnál.

---

## BLOCKER-1 — a migráció ÚJ túlcsordulást vitt a `SetlistDetailScreen`-be a KÖTELEZŐ `2.0` küszöbön

**Fájl:** `lib/features/songs/screens/setlist_detail_screen.dart:116` (az üres állapot `SsEmptyState`-je)

**Mérve** (eldobható próba, 360×640 logikai viewport, `hu`, `textScaler 2.0`):

```
HEAD:        PROBE detail-empty 2.0 hu -> 1  A RenderFlex overflowed by 72 pixels on the bottom.
origin/main: PROBE detail-empty 2.0 hu -> 0
```

400×800-on, `2.5`-nél: `en` 35 px, `hu` **200 px** — `origin/main`-en mindkettő `0`.

**Ez NEM pre-existing hiba, hanem a kör saját regressziója:** ugyanez a próba az
`origin/main`-beli `setlist_detail_screen.dart`-tal nulla hibát mér. A gyökérok
ugyanaz, amit a §10.5/2 a LISTA-képernyőn maga is leírt és javított: az
`SsEmptyState` négy elemet rajzol (ikon + cím + üzenet + gomb) a régi kettő
helyett. A `_ScrollableIfShort` védelem viszont CSAK a
`setlist_list_screen.dart:44` példányra került fel — a detail-képernyő védtelen
maradt. A „2 valódi túlcsordulás javítva" tehát 2/3.

**A3 tehát ténylegesen NEM teljesül**: az acceptance-cella szövege („a képernyők
`textScaler 2.0` mellett … túlcsordulás nélkül renderelnek") nem
viewport-függő állítás.

**Ellenőrzött javítás** (a reviewer alkalmazta, mérte, visszaállította): ugyanaz
a `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight: c.maxHeight)`
minta a detail `SsEmptyState` köré → mind a 8 kombináció (2.0/2.5 × en/hu ×
lista/detail) **0 hiba**.

## MAJOR-1 — az A3 cellák nem azt mérik, amit állítanak: a teszt-viewport 800×600

**Fájl:** `test/features/progress/progress_screen_test.dart`, `test/features/songs/setlist_flow_test.dart`

A cellák az alapértelmezett `flutter_test` viewporton futnak, ami szélesebb
minden telefonnál — a hosszabb `hu` szöveg kevesebb sorba tör, és a BLOCKER-1
regressziója láthatatlan marad. Ráadásul a `progress` populated cellái
`2.0`/`2.5` skálán ÜRESEN mérnek:

```
PROBE scale=1.5  exception=A RenderFlex overflowed by 7.0 pixels  barsInTree=true
PROBE scale=2.0  exception=null                                   barsInTree=false
PROBE scale=2.5  exception=null                                   barsInTree=false
```

`2.0`-nál és `2.5`-nél a `WeeklyBars` (és vele a „this week" szekció, a
`_StrumAccuracyCard`, az `_AccStat`, a `_SourceBreakdown`) **fel sem épül** — a
`ListView` lustán építi, és a viewport alá esik. Egyetlen görgetési lépés után
azonnal előjön: `2.0 → 22 px`, `2.5 → 37 px` túlcsordulás.

Ez a mérce hibája, nem a kódé: a zöld cella nem bizonyítja a zöld képernyőt.

## MAJOR-2 — a §10.6 állítása mérési artefaktumon nyugszik

A §10.6 mondata — „A `2.0` (a KÖTELEZŐ küszöb) és a `2.5` mindkét állapotban
(üres ÉS populated) zöld" — a MAJOR-1 miatt nem tény. A mért valóság: magas
viewporton a populated dashboard `1.5 → 7 px`, `2.0 → 22 px`, `2.5 → 37 px`
túlcsordulást ad — és **ugyanezeket a számokat adja az `origin/main` kódjával
is**, tehát ez a `weekly_bars.dart` pre-existing hibája, NEM a kör regressziója.
A megállapítás helyes, a megfogalmazás félrevezető: ki kell mondani, hogy a
zöld a viewport miatt zöld.

A két `skip: true` cella (`progress_screen_test.dart:187`, populated @1.5 en+hu)
maga NEM A4-sértés (ÚJ cellákról van szó, meglévőt nem gyengítettek, a matcher
és az `expect` érintetlen, az indoklás a kódban áll), és a pre-existing állítás
FÜGGETLENÜL IGAZOLT (`origin/main` kóddal ugyanaz a 7,0 px). Az A3 „küszöb alatt
(1.5) → nincs túlcsordulás" sora viszont emiatt nem teljesül — ezt a brief §0.0
revíziójának kell rögzítenie, nem a cellának elhallgatnia.

## MINOR-1 — `_ProgressEmpty` elvesztette a `ConstrainedBox(maxWidth: 320)`-t

**Fájl:** `lib/features/progress/screens/progress_screen.dart:147–196` vs
`lib/core/widgets/empty_state.dart:45`

A legacy `EmptyState` 320 logikai px-re fogta a szélességet; a port átvette a
paddinget, az ikont, a címstílust és a `LayoutBuilder`-scroll trükköt — a
szélesség-korlátot nem. Tableten/fekvő módban a cím széltől szélig feszül. Ez az
egyetlen G1-osztályú részlet, ami kimaradt.

## MINOR-2 — felhasználó által írt string megy gép-mezőbe és csonkolódik

**Fájl:** `lib/features/songs/screens/setlist_list_screen.dart:56–66`

`SsCardAction(label: set.name, …)`: a szettlista NEVE megy az akció
CÍMKÉJÉBE. Egyetlen akciónál a mező halott (a `SsCardActionRegion` `InkWell`-t
rajzol), de ha valaha második akció kerül a kártyára, egy a szettlista nevével
felcímkézett gomb jelenik meg. Ez a repó mért hibaosztálya (felhasználói string
gép-értékű mezőben).

Kapcsolódó, dokumentálandó (JAVÍTÁS NÉLKÜL, mert `lib/core/design_system/**`
tilos zóna): az `SsContentCard(title:)` `maxLines: 2` + ellipszis
(`ss_content_card.dart:118–121`), a legacy `ListTile.title` szabadon tördelt —
a hosszú, felhasználó által írt szettlista-név mostantól levágódik.

## MINOR-3 — a `weekly_bars.dart` hibának nincs gazdája

A §10.6 „owner TBD"-t ír. A skip-elt cella gazda nélkül elrohad. A záró
rituáléban (HANDOFF §6 + `docs/LESSONS.md`) nevesített javaslattá kell tenni.

---

## PASS — amit a két független review MÉRT és rendben talált

| Ellenőrzés | Eredmény |
|---|---|
| **G1 — néma információvesztés** | PASS. `l10n.*` kulcshalmaz-diff üres, `Icons.*` diff üres, osztály-diff = csak `+ _ProgressEmpty`. A `setlistsEmpty` / `setlistEmptyDetail` szövegek SZÓ SZERINT megmaradtak az `SsEmptyState.message`-ben. (Kivétel: MINOR-1.) |
| **G2 — gyártott hibaállapot** | PASS. Nulla `AppFailure`, nulla `SsFailureState`, nulla `retryable` a diffben — a §0.0.A/R9 előírása teljesült. |
| **G3 — kitalált affordancia** | PASS. Nincs új `context.go/push`, `ref.invalidate`, route-változás. A két új gomb az `SsEmptyState` KÖTELEZŐ `onAction`-je, és ugyanazt a MEGLÉVŐ callbacket hívja, amit a FAB (`_create`, `_addSong`). |
| **G4 — viselkedés-változás** | PASS. Nulla sor `application/`/`domain/`/`data/`/`providers/` alatt; a képernyő-típusok, konstruktorok és route-ok változatlanok. |
| **A napi-cél gyűrű (R9/2)** | PASS. `CircularProgressIndicator(value: progress)` + `met ? check : bolt` érintetlen; helyesen NEM lett `SsScoreRing` (az kötelező `label`-t rajzol a gyűrűbe, ami kiütné az ikont). |
| **Teszt-fegyelem (A4)** | PASS. A hat S11-őr + `test/ui/**` diffje **0 sor**; meglévő cella nem törölt, nem `skip`-elt, matcher nem gyengítve. |
| **A1 / A7 mérés** | PASS. 3 `MIGRATED` + 5 `legacy`; `96` képernyő, `63` importál `design_system`-et → 63/96 = 65,625%. Függetlenül újramérve. |
| **A5** | PASS. `ui_inventory_test.dart` 1/1 zöld, a 96-os egzakt szám változatlan. |
| **A6 / §5.3** | PASS. 2 új kulcs (`setlistsEmptyTitle`, `setlistEmptyDetailTitle`) `en`+`hu` EGYSZERRE, `base/` forrás + generált aggregátum; kulcs-törlés és jelentés-változás nincs. `hardcoded_string_guard_test.dart` zöld. |
| **A8** | PASS. Az öt `retire` képernyő és a `retirement-plan.md` diffje ÜRES; a §10.10 rögzíti a gazdátlanságot végrehajtás nélkül. |
| **Scope** | PASS. Mind a 11 módosult fájl az `allowed_paths`-on (`scope-audit.py` → `OK`). |
| **A3 cella-mátrix teljessége** | PASS. `hu` cella SEHOL nem hiányzik (setlist 24/24, progress 12/12) — az E13-R33 hibaosztálya nem ismétlődött. |
| **L389 (dupla felolvasás)** | PASS. Nincs új kézi `Semantics(label:)` azonos szövegű gyermek `Text` mellett. |
| **Riverpod 3 / analyze** | PASS. `flutter analyze lib/ test/` → `No issues found!`; nincs `.valueOrNull`. |
| **Valódi-sértés próba (§10.9)** | PASS, REPRODUKÁLVA. Az `SsEmptyState` → nyers `Text` csere pontosan EGY cellát pirosít (`empty setlists action button opens the same create dialog as the FAB`), a többi 28 zöld — szó szerint az, amit a §10.9 állít. |

## NOTE-ok (nem javítandók ebben a körben)

1. **A `progress_screen.dart` egyetlen `Ss*` KOMPONENST sem használ**, csak
   token-forrásokat (`SsColorScheme`, `SsTypography`, `SsSpacing`) kézzel írt
   widgetekben — az A1 `grep design_system` mércéje ezt nem különbözteti meg.
   Az indoklás MÉRVE IGAZ: a `test/features/today/hub_navigation_test.dart:33`
   `MaterialApp.router`-t `theme:` NÉLKÜL épít, minden `Ss*` komponens pedig
   `Theme.of(context).extension<SsColorScheme>()!`-lal old fel → a komponens
   használata ezen az őrön `Null check operator used on a null value`-val bukna.
   A többi öt S11-őr mind beállítja az `SsLightTheme.data()`-t; egyedül ez nem.
   **Ez brief-szintű ellentmondás**, amit a 0-diff mandátum zár le — a feloldása
   ÖNÁLLÓ kör dolga (vagy az őr témázása, vagy fallback a komponensekben).
2. **Két szándékos, dokumentálatlan színérték-változás:** `colors.confidenceHigh`
   világos témában `0xFF178A57` a korábbi `0xFF3ED598` helyett (kontraszt-javulás,
   a tokenizáció célja), és `_Stat` háttere átlátszó → átlátszatlan
   `surfaceSunken`. Rögzítendő, nem hiba.
3. **Force-unwrap vs. védett feloldó aszimmetria:** a két setlist-képernyő
   `extension<SsColorScheme>()!`-t használ, a `progress_screen.dart` `??`
   fallbackot. Ma biztonságos (mindkét setlist-őr témázott), de csapda a
   következő körnek, amely nem témázott harnesst ad hozzá.
4. **Nincs gate-artefaktum:** a §10 prózában állítja a 22/22-t. A mérce a CI
   exact-SHA futása; a merge-kapu ezt méri, nem a prózát.

---

## A javító kör kötelező tartalma (1 BLOCKER + 2 MAJOR + 3 MINOR)

| # | Lelet | Teendő |
|---|---|---|
| F1 | BLOCKER-1 | `_ScrollableIfShort` (vagy azonos minta) a `setlist_detail_screen.dart` `SsEmptyState`-jére |
| F2 | MAJOR-1 | Mindkét A3 teszt-fájl cellái telefon-méretű viewporton fussanak (`tester.view.physicalSize` + `devicePixelRatio`, `addTearDown(tester.view.reset)`) |
| F3 | MAJOR-2 | A §10.6 és a `migration-status.md` a MÉRT valóságot mondja: a `2.0`/`2.5` zöld a viewport miatt zöld; a magas viewporton mért 7/22/37 px a `weekly_bars.dart` PRE-EXISTING hibája (`origin/main`-en ugyanaz) |
| F4 | MINOR-1 | `ConstrainedBox(maxWidth: 320)` vissza a `_ProgressEmpty`-be |
| F5 | MINOR-2 | `SsCardAction.label` lokalizált, generikus címke legyen (a szettlista neve NEM mehet gép-mezőbe); az `SsContentCard` `maxLines: 2` csonkolása a §10-be dokumentálva |
| F6 | MINOR-3 | A `weekly_bars.dart` hibához nevesített javaslat a §10-ben |

## Review — 2. forduló (a javító kör után)

**Review-lt HEAD:** `f1e3dbe5` (javító commit: 10 fájl, +284/−55)

### VÉGSŐ DÖNTÉS: APPROVED — mind a 6 lelet ZÁRT, mért bizonyítékkal

| # | Lelet | Állapot | A záró mérés |
|---|---|---|---|
| F1 | BLOCKER-1 | **ZÁRT** | 360×640, `en`+`hu`, `2.0`+`2.5` → **8/8 kombináció 0 hiba**. Ok-okozatilag bizonyítva: a `9e4f95d6`-beli fájl visszaállításával UGYANEZEK a cellák pirosak (`2.0 hu → 72 px`, `2.5 en → 315 px`, `2.5 hu → 365 px`) — a 72 px pontosan az 1. fordulós érték. `setlist_flow_test.dart` 29/29 zöld. |
| F2a | MAJOR-1 | **ZÁRT** | Minden A3 cella beállítja a `physicalSize = Size(360, 640)` + `devicePixelRatio = 1.0` értéket ÉS `addTearDown(tester.view.reset)`-tel visszaállítja (4-4-4 a setlist-, 2-2-2 a progress-fájlban). A viselkedés-cellák helyesen maradtak az alapértelmezett viewporton. |
| F2b | MAJOR-1 | **ZÁRT** | `scrollUntilVisible(find.byType(WeeklyBars), …)` a `takeException()` ELŐTT; mérve `barsBefore=false → barsAfter=true` mindhárom skálán, mindkét locale-on. |
| F3 | MAJOR-2 | **ZÁRT** | A §10.6 újraírva: kimondja, hogy a korábbi zöld MÉRÉSI ARTEFAKTUM volt, táblázatban közli a `1.5 → 7 px`, `2.0 → 22 px`, `2.5 → 73 px` értékeket HEAD és `origin/main` oszloppal, és külön bekezdésben kimondja, hogy az A3 a populated állapotban NEM teljesül a `weekly_bars.dart` javításáig. A reviewer a számokat FÜGGETLENÜL újramérte (a `skip` feloldásával): azonosak, és `origin/main` kóddal is azonosak. |
| F4 | MINOR-1 | **ZÁRT** | `progress_screen.dart:167` `constraints: const BoxConstraints(maxWidth: 320)` — egyezik a legacy `empty_state.dart:46`-tal. |
| F5 | MINOR-2 | **ZÁRT** | `SsCardAction(label: l10n.setlistOpen, …)` — a `set.name` többé nem megy gép-mezőbe. Új kulcs mind a négy ARB-fájlban (`base` + generált aggregátum), paritás mérve: `en-only: []`, `hu-only: []`. Az `SsContentCard` `maxLines: 2` csonkolása a §10.11/F5-ben dokumentálva. |
| F6 | MINOR-3 | **ZÁRT** | §10.6: konkrét fájl (`weekly_bars.dart:32`), konstans (`SizedBox(height: _maxBar + 46)`), két javítási irány, önálló kör igénye, és reprodukálható elfogadás-mérce (a 6 `skip` cella pirosból zöldbe fordul). |

### Regresszió-ellenőrzés (2. forduló, mind PASS)

- a hat S11-őr + `test/ui/**` diffje az `origin/main...HEAD` teljes tartományban **0 sor**;
- `flutter analyze lib/` (külön hívás) → `No issues found!`;
- `weekly_bars.dart` **érintetlen**;
- a `progress_screen.dart` `l10n.*` és `Icons.*` kulcshalmaza **azonos** az `origin/main`-ével (a setlist-fájlokon csak BŐVÜLÉS, törlés nincs);
- a valódi-sértés mérce **továbbra is él**: az `SsEmptyState` → nyers `Text` csere pontosan 1 cellát pirosít, 28 zöld;
- ARB-paritás: `en-only`/`hu-only` üres mindkét párra;
- scope: a javító kör **nem hozott új útvonalat** (`scope-audit.py` → OK).

### Tudatosan vállalt maradék (WARNING, nem blokkoló)

**A `ProgressScreen` POPULATED állapotára a körnek nincs futó zöld A3-bizonyítéka:**
a 6 populated cella (`1.5`/`2.0`/`2.5` × `en`/`hu`) `skip: true`, mert a
végiggörgetett képernyő `7`/`22`/`73` px-szel túlcsordul — MÉRTEN ugyanannyival
az `origin/main` kódjával is, tehát **PRE-EXISTING, nem a kör regressziója**, és a
gyökérok (`lib/features/progress/widgets/weekly_bars.dart`) a kör
`allowed_paths`-án KÍVÜL van (a javítása H3 lenne). A merge ezt tudatosan
vállalja; a feloldás a §0.0.A/R11 szerinti nevesített követő kör.

Kisebb, nem érdemi doksi-pontatlanságok a §10-ben (a reviewer mérése szerint):
§10.9 „27 cella" → valójában 28 zöld / 29 összes; §10.6 „mind a 28" setlist-cella
→ 29; a §10.5 két px-száma (15/39) még a 800×600-as harnessen készült, és a
doksi ezt nem címkézi. Egyik sem hamis érdemi állítás — NOTE.

### Golden-tesztek (nem a kör hibája)

`flutter test test/ui/` ezen a boxon 15 golden-cellán bukik (chord detail,
learning path, song library, achievements, hub, streak detail, club detail,
safety, share preview) — a három migrált képernyőt `origin/main`-re
visszaállítva **ugyanaz a 15 bukás**, tehát box-környezeti (font/renderer) drift,
PRE-EXISTING. A mérce a CI x86 architektúrája (ADR 0426).
