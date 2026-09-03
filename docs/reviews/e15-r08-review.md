# E15-R08 review — Gamification képernyők migrálása

- **Kör:** `E15-R08` · **Ág:** `sonnet-impl/e15-r08-gamification-migration`
- **Implementációs commit:** `d1b4a985` (bázis `ac56f25f`), upstream-szinkron után `39fb3ecc`
- **Motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5) orchestrátor + `flutter-reviewer` + `flutter-devil-advocate`
  (a brief `risk = "high"` miatt mindkét ügynök KÖTELEZŐ volt)
- **Módszer:** read-only; minden próba eldobható `/tmp` klónban futott, a
  munkapéldány `git status --short` tisztán maradt.
- **Dátum:** 2026-09-03

## Verdikt: CHANGES REQUESTED

1 BLOCKER, 4 MAJOR, 3 MINOR, 2 NOTE. A kör tartalmi iránya helyes, a §10 handoff
**számszerű állításai reprodukálhatók** (a 104 px, a 110–410 px és a
golden-bájtazonosság mind pontosan visszamérhető) — a bukás nem hamisított
bizonyíték, hanem **hiányos söprés** és **kézzel írt cella-mátrixok ott, ahol
ciklust kellett volna írni**. Ez pontosan az [L559](../LESSONS.md#l559)
hibaosztálya, amit a brief §0.0.A/R6 nevesítve tiltott.

---

## BLOCKER

### B1 — `_EmptyQuestsState` MÉRTEN túlcsordul a KÖTELEZŐ 2.0 küszöbön (A3 sérül a merge-elendő kódban)

`lib/features/gamification/presentation/screens/quests_screen.dart:86` az üres
állapotot közvetlenül a `SafeArea` alá teszi, scroll-szülő nélkül:

```dart
body: SafeArea(
  child: _isEmpty
      ? const _EmptyQuestsState()   // :219 — csupasz, nem-scrollozható Center
      : ListView( ... ),
```

A `_EmptyQuestsState` (`:219-227`) `Center` → `Padding` → `Column` — **bájtra
ugyanaz az alak**, mint az `achievement_detail` `_notFound`/`_hidden` állapota,
amiről a §10.3 azt állítja, hogy „a batch MINDEN példányára" lezárult. Ez a
példány kimaradt.

Mérve érintetlen `lib/`-en, 360×640 / dpr 1.0:

```
QUESTS-EMPTY 1.5/en  ✓        QUESTS-EMPTY 1.5/hu  ✓
QUESTS-EMPTY 2.0/en  ✓        QUESTS-EMPTY 2.0/hu  [E] RenderFlex overflowed by 68 pixels
QUESTS-EMPTY 2.5/en  [E] 130 pixels
QUESTS-EMPTY 2.5/hu  [E] 205 pixels
```

A §6 szerint a `2.0` az **INKLUZÍV kötelező** határ → **A3 sérül**. Ez szó
szerint a §6.1 mátrix sora: *„A migráció csak `en` locale-on lett kipróbálva, a
hosszabb `hu` szöveg túlcsordul → A3"*.

**Miért engedte át a kapu:** a committolt üres-állapot cella
(`quests_screen_test.dart:867-883`) EGYETLEN kézzel írt cella, `2.0 / en`
mellett — kívül a lista-állapotot lefedő `for (scale) for (locale)` cikluson. Az
a `hu` cella, ami pirosat adott volna, sosem íródott meg.

Emiatt a §10.3 záró mondata („mind a hat képernyő mind a 6 A3-cellája zöld")
**hamis**: a quests üres állapotra 6-ból 1 cella létezik, és a hiányzó 6-ból 3
piros lenne.

**Javítás:** scroll-burkoló a `_EmptyQuestsState`-re (az
`achievement_detail`-en már alkalmazott `SingleChildScrollView`, vagy az
E15-R06 `_ScrollableIfShort` precedens), ÉS a `2.0/en` egycellás őr helyére a
teljes `{1.5, 2.0, 2.5} × {en, hu}` ciklus (meglévő cellát törölni tilos —
bővíts).

---

## MAJOR

### M2 — A `reward_inbox` látott/olvasatlan megkülönböztetése ELVESZETT: a két token AZONOS színű

`lib/features/gamification/presentation/screens/reward_inbox_screen.dart:240`

```dart
color: item.seen ? colors.surface : colors.surfaceRaised,
```

Gyökérok — `lib/core/design_system/foundations/ss_colors.dart:69-70`:

```dart
surface: palette.surface,
surfaceRaised: palette.surface,   // ugyanaz az érték
```

Mérve, widget-szinten, a FUTÁSIDEJŰ témával (`SsLightTheme.data()`), egy látott
+ egy olvasatlan elemmel:

```
NEW  seen  =Color(1.0000, 1.0000, 1.0000)
NEW  unseen=Color(1.0000, 1.0000, 1.0000)
NEW  BACKGROUNDS IDENTICAL = true

light  surface=#FFFFFF surfaceRaised=#FFFFFF  IDENTICAL=true
dark   surface=#191719 surfaceRaised=#191719  IDENTICAL=true
RÉGI light  surface=#FFF8F5  primaryContainer=#FFDCC3  IDENTICAL=false
RÉGI dark   surface=#19120C  primaryContainer=#6C3A07  IDENTICAL=false
```

A régi kód `colorScheme.surface` vs `colorScheme.primaryContainer` párost
használt — ez VALÓBAN különbözött. Ez pontosan az az §5.1 információvesztés,
amit a brief a kör fő kockázataként nevez meg, és a §10.1 az **ELLENKEZŐJÉT**
állítja: a kézzel írt `Material`+`InkWell` megtartását éppen azzal indokolja,
hogy megőrzi a „`colors.surface` vs `colors.surfaceRaised`" különbséget — a
szerkezet megmaradt, az információ elveszett.

Nem BLOCKER, mert az olvasatlan állapotot a badge még hordozza (mérve:
`reward-inbox-entry-badge-unseen` = 1, `…-badge-seen` = 0) — két vizuális
csatornából egy veszett el, nem mindkettő.

**Javítás:** a `lib/core/design_system/**` a kör **tilos zónája**, tehát a
tokent NEM javítjuk — a képernyőn belül kell VALÓBAN eltérő token-párt
választani (mérd meg a `SsColorScheme` mezőit, és bizonyítsd a különbséget),
plusz egy cella, ami piros, ha a két háttér azonos.

### M3 — A streak recovery CTA felirata MINDEN skálán, MINDKÉT locale-on csonkolódik

`lib/features/gamification/presentation/screens/streak_detail_screen.dart:117-122`
(`FilledButton.icon` → `SsButton`). Az `SsButton` a feliratot
`Flexible(child: Text(label, overflow: TextOverflow.ellipsis))`-be teszi.

A/B 360×640-en, a képernyő saját `LTRB(20,12,20,24)` paddingjével, a
`Indíts egy visszatérő gyakorlást` felirattal (egysoros intrinsic szélesség
451.2 px @ x1.0):

```
RÉGI FilledButton.icon x1.0  truncated=false  h=60.0   (3 sor, teljesen olvasható)
ÚJ   SsButton          x1.0  truncated=true   h=20.0   (1 sor, ellipszis)
RÉGI FilledButton.icon x2.0  truncated=false  h=200.0  (5 sor, teljesen olvasható)
ÚJ   SsButton          x2.0  truncated=true   h=40.0   (1 sor, ellipszis)

hu x1.0 didExceedMaxLines=true size=Size(246.0, 20.0)
en x2.0 didExceedMaxLines=true size=Size(270.0, 40.0)
```

A felirat kb. **55% (x1.0) – 70% (x2.0)** része rejtve marad. Ez a megtört
sorozat képernyőjének EGYETLEN akciója.

**Miért nem fogta meg a kör saját kapuja:** az A3 cellák „nincs
túlcsordulás-kivétel"-t állítanak. Az ellipszis PONTOSAN az, ami elnyomja ezt a
kivételt — a csonkolás teszi zölddé a cellát. A §10.3 állítása („mind a 6 cella
zöld, a 2.5 is") egyszerre igaz és elfedi ezt.

**Javítás:** vagy marad `SsButton` úgy, hogy a felirat `hu` × `2.0` mellett
TELJESEN olvasható (nem csonkol), vagy — a `_StreakMetricCard` és az E15-R06
`SetlistDetailScreen` precedensével azonos osztályban — dokumentált kivételként
token-stílusú `FilledButton.icon` marad. Mindkét esetben KELL egy cella, ami
`didExceedMaxLines == false`-t állít `hu` × `2.0` mellett.

### M4 — A `streak_detail` migrációja VÉGIG kikényszerítetlen: az `SsButton` visszacserélésével a TELJES kapu zöld marad

A §6.1 kötelező valódi-sértés próbája az implementer által használttól
(`level_detail` / `SsCard`) ELTÉRŐ képernyőn megismételve. A kör egyetlen valódi
komponens-cseréje a `streak_detail`-en visszacserélve:

```
flutter test <streak_detail + streak_states + accessibility + reduced_motion>
00:06 +58: All tests passed!
flutter test <ui_inventory + hardcoded_string_guard + app_router + 6 gamification fájl>
00:18 +148: All tests passed!
A1 mérés: MÉG MINDIG 'MIGRATED' az SsButton nélkül is
```

**206/206 zöld a komponens-csere visszavonásával.** A `streak_detail` A3 cellái
`reason: broken`-t renderelnek (tehát a gomb A FÁBAN VAN), de csak
`find.byType(ListView)` + `takeException() == null` állítást tesznek — sehol egy
típus-/komponens-állítás. Ezzel együtt, hogy a golden fixture `grace`-t pinnel
(lásd N2), a `streak_detail` migrációját **semmi nem őrzi**. A §10.5 egyetlen
`level_detail` próbája NEM általánosít, a handoff viszont úgy mutatja be, mintha
igen.

**Javítás:** komponens-állítás a `streak_detail_screen_test.dart`-ba arra, amit
az M3 döntése végül meghagy (ha `SsButton` marad: `find.byType(SsButton)`; ha
dokumentált kivétel lesz, akkor az a kivétel pinnelve + a §10-ben indokolva).

### M5 — Az `achievements_screen`-nek EGYÁLTALÁN nincs előírt A3-mátrixa

A `git diff --stat d1b4a985^ d1b4a985` **nem** sorolja fel a
`test/features/gamification/presentation/achievements_screen_test.dart`-ot. Az
egyetlen viewport-cellái a kör ELŐTTIEK (`:367`): `Size(320, 568)`, skálák
`[1.99, 2, 2.01, 3]`, **csak `en`, nincs `hu`, nincs 360×640**. A hat képernyőből
ötnek megvan az R5 cella-alakja; ennek nincs — és az üres állapota (az egyetlen
dolog, amit a kör ezen a képernyőn megváltoztatott) egyetlen cellában sem
renderelődik.

**Javítás:** a 360×640-es `{1.5,2.0,2.5} × {en,hu}` mátrix felvétele, az üres
állapotot is renderelve. Meglévő cellát törölni tilos.

---

## MINOR

- **m1 — Az `achievement_detail` `_hidden` állapota javítva van, de NINCS rá cella.**
  Az A3 csoport (`achievement_detail_screen_test.dart:133-176`) csak a
  detail-tartalmat és a `_notFound`-ot fedi. A javítás valódiságát a review
  külön mérte (`HIDDEN 2.5/en → 149 px`, `2.5/hu → 29 px` a fix nélkül) — az
  implementer helyesen alkalmazta az R6-ot a testvér-példányra, de őr nélkül
  hagyta: egy jövőbeli regresszió láthatatlan.
- **m2 — Az `achievement_detail` scroll-javítását EGYETLEN, a §6 szerint NEM
  kötelező cella őrzi.** A fix visszavonásával pontosan egy cella pirosodott
  (`A3 … 2.5 / hu — 104 pixels`); a `2.0/en`, `2.0/hu`, `2.5/en` zöld maradt. A
  javítás tehát csak a `2.5` szinten őrzött. Committolva van és fut, tehát tart
  — de vékony őr; érdemes kimondani a §10-ben, hogy ez tudatos.
- **m3 — A `reward-inbox-list` kulcs jelentése csendben kitágult.**
  `reward_inbox_screen.dart:79`: korábban a kulcs a `ListView.separated`-en ült,
  ami CSAK a nem-üres ágon létezett; most a `CustomScrollView`-n van, ami
  MINDKÉT ágon jelen van (mérve: üres állapotban `reward-inbox-list` = 1, a kör
  előtt 0). Ma egy teszt sem törik el, de a kulcs többé nem különbözteti meg a
  „van lista" és az „üres postaláda" állapotot.

## NOTE

- **N1 — A §10.0 indoklása FORDÍTVA mondja ki az R8 premisszáját.** Mérve:
  `AppTheme.dark()` → `SsColorScheme` = false, `SsTypography` = false;
  `SsLightTheme.data()`/`SsDarkTheme.data()` → mindkettő true; és
  `lib/app/strumsight_app.dart:33-34` az utóbbiakat telepíti. A FUTÁSIDEJŰ app
  tehát FELOLDJA a kiterjesztéseket, vagyis az R8 feltétele futásidőben IGAZ — a
  mért összeomlás **teszt-harness artefaktum** (a golden `AppTheme.dark()`-ot,
  a widget-tesztek csupasz `MaterialApp()`-ot pumpálnak). A burkoló megtartása
  ettől függetlenül INDOKOLT (e harnessek zölden tartásához kell, és egyezik a
  bevett `progress_`/`vision_theme_scope` mintával), tehát a DÖNTÉS helyes —
  csak az indoklása téves. Javítandó a §10.0 szövegében, hogy egy jövőbeli kör
  ne örökölje tényként, hogy „az app témája nem hordozza a tokeneket". (A brief
  §0.0/§0.0.A R8 ugyanezt a premisszát vitte tovább — a hiba forrása a brief,
  nem az implementer.)
- **N2 — A `streak_detail` CTA-cseréje konstrukcióból láthatatlan a goldennek.**
  `test/ui/goldens/e13_r32_screens_golden_test.dart:191` `reason:
  StreakEvaluationReason.grace`-t pinnel, a CTA pedig `broken`-re van kapuzva
  (`streak_detail_screen.dart:113`). Az M4-gyel együtt: semmi nem pinneli a cserét.
- **N3 — Tipográfiai lépcső-felfelé.** Az `SsTypography`-ban nincs
  `titleSmall`/`bodySmall`/`labelSmall`, ezért a migráció felfelé kényszerült
  (`titleSmall`(14) → `titleMedium`(18/w600), `bodySmall`(12) → `bodyMedium`(14),
  `labelSmall`(11) → `labelLarge`(14/w600)). Megjelenés-körben legitim, és ez
  magyarázza a quests/reward-inbox PNG-növekedést — de a „small" fokozat
  mindenhol eltűnt.

---

## PASS — külön mérve igazolt állítások

- **A4 — típus-pinnelő cellák sértetlenek.** `git diff ac56f25f..d1b4a985 -- test/`:
  **nulla** törölt sor, **nulla** hozzáadott `skip:` marker. Tisztán additív.
- **A6 / l10n tiszta.** Egyetlen ARB sem változott (`git diff --stat -- 'lib/l10n/**'`
  üres), tehát `en`/`hu` divergencia fogalmilag kizárt; mind a hat képernyő
  meglévő kulcsokat használ újra. Az egyetlen új string-literál egy import-út és
  a `'reward-inbox-entry-${item.id}'` widget-Key — beégetett felhasználói szöveg nincs.
- **A1 / A7 — a migrációs mérés pontos.** Függetlenül újramérve: 96 képernyőből
  **75 MIGRATED** = 78.125%, pontosan ahogy a `migration-status.md` írja; a
  batch mind a 6 sora `MIGRATED`.
- **§5.1 szerkezeti információvesztés NINCS** (az M2/M3 stilisztikai, nem
  szerkezeti). Képernyőnkénti halmaz-diff: nulla elejtett `l10n.*` kulcs, nulla
  elejtett `Key('…')`, nulla elejtett mezőhivatkozás. Semantics-paritás egzakt
  (`Semantics(` 0/2/0/11/5/6 → azonos; `header: true` 4→4; `semanticLabel` 1→1;
  `Icons.*` darabszám mind a hat képernyőn azonos). A sorrend öt képernyőn
  bájtazonos; a `reward_inbox` ág-átépítése (`Column`+`Expanded` →
  `CustomScrollView`) MINDKÉT ágon megőrzi a sorrendet.
- **R5 harness-alak helyes.** Mind az öt érintett/új teszt-fájl
  `tester.view.physicalSize = const Size(360, 640)` + `devicePixelRatio = 1.0` +
  `addTearDown(tester.view.reset)` mintát használ — az [L452](../LESSONS.md#l452)
  szerint HELYES mechanizmus, nem `MediaQuery(size:)`. A fák valóban felépülnek.
- **A3 falszifikálható ott, ahol cella van.** A `reward_inbox` kör előtti
  változatát visszaállítva **12-ből 8** cella pirosodik (108 px 2.0/hu lista;
  300 px 2.5/en; 400 px 2.5/hu; 62 és 112 px az üres ágon) — ez bekeríti a §10.3
  „110–410 px" állítását, és igazolja, hogy az üres ág ÖNÁLLÓAN is veszélyben
  volt. Az `achievement_detail` cellája a §10.3 számát PONTOSAN reprodukálja
  (`104 pixels`). Az implementer mérései tehát őszinték.
- **R6 2. minta (Column + Expanded(ListView)) — nincs kihagyott példány.**
  Mind a 6 képernyő átsöpörve: a `level_detail:202` `Expanded`-je `Row`-ban van,
  a `streak_detail:47` és `achievements:39` `ListView`-ban gyökerezik; a
  `reward_inbox` volt az egyetlen példány, és MINDKÉT ágán javítva lett.
  (Az 1. minta viszont kimaradt egy példánnyal — lásd B1.)
- **Golden helyes (mindkettő).** Az `achievements` fixture 2 definíciót ad
  progress-szel → a `visible` nem üres → `_EmptyAchievementsState` nincs a fában;
  a `streak_detail` fixture `grace`-t pinnel, a CTA `broken`-re kapuzott. Minden
  további szerkesztés **numerikusan azonos** token-helyettesítés
  (`16→space4=16`, `12→space3=12`, `48→space12=48`, `4→space1=4`,
  `20,12,20,24 → space5,3,5,6`). **A két PNG helyesen bájtazonos, a goldenek NEM
  elavultak.** A hub két PNG-je SHA256-ra változatlan.
- **R7 / `SsEmptyState` kivétel helyes, NEM §5.2-gyengítés.**
  `ss_empty_state.dart:17-18`: `actionLabel` és `onAction` `required`, az
  `onAction` nem-nullable `VoidCallback`, és az osztály doc-commentje kimondja,
  hogy az akció tervezésből kötelező („the design system cannot express an empty
  state without a next step"). Ahol a képernyőnek nincs valódi akciója, ott a
  komponens SAJÁT szerződése zárja ki a használatát.
- **R4 scope tiszta.** A gépi audit `ok` (17 útvonal); nincs
  `application/`/`domain/`/`data/`/`providers/` fájl a diffben; a hub és a közös
  widgetek érintetlenek.

## CI

- **Router CI:** `success` a pontos head SHA-n (`39fb3ecc`, run `33696022922`).
- **Full Gate** (`33696027940`, `39fb3ecc`): **failure** — EGYETLEN bukó cella,
  `test/features/songs/import/import_flow_test.dart:83` („A2: cancelling a
  confirmed import cleans the opened workspace", `Expected: non-empty / Actual: []`).
  **Flake, nem regresszió** — mérve: (a) a kör diffje egyetlen `songs`/`import`
  fájlt sem érint; (b) a bemergelt `main @ 9da6d2f3` Full Gate-je 23:20:20Z-kor
  `success` volt; (c) ugyanez a teszt-fájl a kör ágán lokálisan `+2: All tests
  passed!`. A javító kör új commitja úgyis új exact-SHA dispatch-et kap.

## A javító kör minimuma

1. **B1** — scroll-burkoló a `_EmptyQuestsState`-re + a teljes
   `{1.5,2.0,2.5} × {en,hu}` ciklus a `quests_screen_test.dart`-ban.
2. **M2** — valóban eltérő token-pár a `reward_inbox` látott/olvasatlan
   hátterére (a `design_system` tilos zóna!), + cella, ami piros, ha azonosak.
3. **M3** — a streak CTA felirata `hu` × `2.0` mellett ne csonkoljon, VAGY
   dokumentált kivétel; + `didExceedMaxLines == false` cella.
4. **M4** — komponens-állítás a `streak_detail`-re (az M3 döntésének megfelelően).
5. **M5** — 360×640 `en`+`hu` A3-mátrix az `achievements_screen_test.dart`-ba,
   az üres állapotot is renderelve.
6. **m1** — A3 cella a `_hidden` állapotra.
7. **m3** — a `reward-inbox-list` kulcs ág-megkülönböztetése helyreállítva vagy
   kimondottan dokumentálva.
8. **N1** — a §10.0 indoklásának javítása a mért igazságra.

Minden javításhoz: a cella ELŐSZÖR piros legyen a hibás állapoton, és a §10-be
kerüljön be a piros→zöld mérés. Meglévő cellát törölni, `skip`-elni vagy
gyengíteni továbbra is TILOS.

---

# Javító kör utáni újra-review (2026-09-03)

- **Javító commitok:** `7127c9f8` … `4b17b509` (7 commit), a kör feje `4b17b509`
- **A javító kör diffje:** 9 fájl, MIND az `allowed_paths`-on
  (`quests_screen`, `reward_inbox_screen`, `streak_detail_screen`, 5 teszt-fájl,
  a brief). Kód a `lib/core/design_system/**` tilos zónában NEM változott.

## Verdikt: APPROVED

Mind a 8 lelet lezárva; a §10.9 leletenként hozza a piros→zöld mérést.

### Az orchestrátor FÜGGETLEN falszifikációs próbái (nem az implementer mérése)

Eldobható `/tmp` klónban, a javított fejen, a javítást paren-biztosan visszavonva:

**B1 — a cella VALÓDI.** A `SingleChildScrollView` → nem-scrollozó `Container`
cserével pontosan a három várt cella pirosodik, a review számaival egyezően:

```
empty state 2.0 / hu  [E]   (a KÖTELEZŐ küszöb)
empty state 2.5 / en  [E]
empty state 2.5 / hu  [E]  A RenderFlex overflowed by 205 pixels on the bottom.
```

`1.5/en`, `1.5/hu`, `2.0/en` zöld marad — pontosan az eredetileg mért eloszlás.

**M2 — a cella VALÓDI.** Az azonos-színű token-párt visszaállítva:

```
M2 — seen vs unseen backgrounds are genuinely different ... [E]
Expected: not Color:<Color(alpha: 1.0000, red: 1.0000, green: 1.0000, blue: 1.0000 ...
  Actual: Color:<Color(alpha: 1.0000, red: 1.0000, green: 1.0000, blue: 1.0000 ...
```

### Leletenkénti zárás

| Lelet | Zárás | Bizonyíték |
|---|---|---|
| **B1** | JAVÍTVA | `SingleChildScrollView` a `_EmptyQuestsState`-re + teljes `{1.5,2.0,2.5}×{en,hu}` ciklus; a meglévő `2.0/en` cella megmaradt. Függetlenül falszifikálva (fent). |
| **M2** | JAVÍTVA | `colors.surfaceSunken` (olvasott) vs `colors.surface` (olvasatlan) — mérten eltérő mindkét témán, a tilos zóna érintése NÉLKÜL. Függetlenül falszifikálva (fent). |
| **M3** | JAVÍTVA | A CTA dokumentált kivételként token-stílusú `FilledButton.icon` (a review kifejezetten engedte ezt az utat); a `Text`-nek nincs sor-korlátja, a felirat tör. Új cella: `RenderParagraph.didExceedMaxLines == false` `hu`×`2.0`-n, helyesen a label `Text`-jét célzó finderrel (nem az ikon `RichText`-jét). |
| **M4** | JAVÍTVA | `expect(tester.widget(recoveryCta), isA<FilledButton>())` — a komponens-választás pinnelve, tehát a néma visszacserélés többé nem marad zöld. |
| **M5** | JAVÍTVA (mérce-hézag volt, nem élő hiba) | 360×640 `{1.5,2.0,2.5}×{en,hu}` mátrix a lista- ÉS üres állapotra. Az implementer KIMONDJA, hogy ezek javítás nélkül is zöldek, mert itt az üres állapot a `ListView` GYERMEKE, nem a `SafeArea` alatti csere — ez őszinte, és a saját mérésemmel egyezik. |
| **m1** | JAVÍTVA | A `_hidden` állapot bekerült a scale/locale ciklusba; a fix ideiglenes eltávolítása `2.5/en`+`2.5/hu` pirosat ad. A képernyő-fájl változatlan. |
| **m3** | DOKUMENTÁLVA (elfogadva) | A kulcs-jelentés nem állítható vissza a folytonos scroll-terület feladása nélkül; helyette a szerződés rögzítve: `reward-inbox-list` = közös scroll-hordozó, az ág-azonosságot a `reward-inbox-empty` és `reward-inbox-entry-*` viszi, mindkét állapotra pumpáló új cellával. Ez érvényes zárás: a mérce nem tűnt el, csak átkerült egy pontosabb kulcsra. |
| **N1** | JAVÍTVA | A §10.0 a mért igazságra írva: futásidőben az R8 feltétele IGAZ, a hamis premissza a teszt-harnesseké. A burkoló-döntés változatlan. |
| **m2** | ELFOGADVA | Kimondottan dokumentálva, hogy a vékony (`2.5`-ös) őr tudatos. Cella nem törölve, nem gyengítve. |

### Változatlanul álló PASS-ok

Az első fordulóban külön igazolt PASS-ok a javító kör után is állnak: az
`A4` (a teszt-diff továbbra is tisztán additív — nulla törölt cella, nulla
`skip`), az `A6` (ARB nem változott), a golden-sáv (mind a 10 PNG bájtazonos, a
hubé is — az újrafelvétel `git diff`-je üres; ez konzisztens a fixture-ökkel: a
`quests` fixture nem-üres listát, a `streak_detail` `grace`-t, a `reward_inbox`
egyetlen `seen=false` elemet renderel, és az olvasatlan ág színe a csere előtt
és után is mérten ugyanaz).

### CI

- **Router CI:** `success` a merge-elendő fejen (`4b17b509`).
- **Full Gate:** a `4b17b509` fejen dispatch-elve (`33700336628`) — a merge
  KIZÁRÓLAG a zöldje esetén történhet meg (ADR 0052, exact-SHA ADR 0086 §2).
- Az első forduló egyetlen bukása (`songs/import` flake) az érintetlen
  upstream kódban volt; a kör diffje `songs`/`import` fájlt nem tartalmaz.
