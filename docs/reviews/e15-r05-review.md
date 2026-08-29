# E15-R05 — független review (Song Trainer képernyők migrálása)

- **Reviewer:** Claude (Opus 5), orchestrátor-szék — READ-ONLY, produkciós kódot
  nem szerkesztett
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Review-zott állapot:** `origin/main @ 4c22d973` → branch `d7fe0686` +
  16 nem commitolt munkafa-fájl
- **Kötelező agentek (a brief `risk = "high"` miatt):** `flutter-reviewer`,
  `flutter-devil-advocate` — mindkettő lefutott, izolált méréssel
- **Dátum:** 2026-08-29

## Verdikt (első kör): CHANGES REQUESTED — 3 MAJOR

A kör CÉLJA teljesült: mind a 9 képernyő migrált (A1, 60/96 = 62,5%), a §7 kapu
zöld, a G1–G4 gépi őrök tiszták (mindhárom mérő — implementer, reviewer,
devil-advocate — függetlenül újrafuttatta), és **egyetlen típus-pinnelő cella
sem lett törölve, `skip`-elve vagy gyengítve** (A4 — mérve: a `test/` diff
+71/−2 sora KIZÁRÓLAG `theme:`/`import` huzalozás; nulla törölt `expect`, nulla
`skip`, nulla tágított matcher).

Az E15-R04 három MAJOR-mintája (elveszett hibaszöveg, gyártott `AppFailure`,
kitalált akció) **nem ismétlődött meg** — a §7.1 gépi őrök megfogták volna, és
a kód képernyőnként dokumentálja, miért NEM gyárt hibát vagy akciót. A három
MAJOR ezúttal máshonnan jön: **két acceptance-cellának nincs őre**, és egy
szöveg a G1 vakfoltján át veszett el.

### MAJOR-1 — a szünetelt transzport magyarázata elveszett, és a helyére a fölötte lévő sor másolata került

`lib/features/song_trainer/presentation/screens/song_trainer_screen.dart:376-383`

Kör előtt a letiltott sebesség-csempe megmondta, MIÉRT inert:

```
$ git show origin/main:…/song_trainer_screen.dart | sed -n '345,346p'
          title: Text('Speed disabled — backing cannot change rate.'),
          subtitle: Text('Paused: speed resumes when the session restarts.'),
```

Kör után a subtitle a szünet-időbélyeg — ugyanaz a kifejezés, amit a képernyő
23 sorral feljebb MÁR kiír:

```
$ grep -n "trainerPausedPosition" …/song_trainer_screen.dart
358:          label: l10n.trainerPausedPosition(…),   # key 'song-trainer-paused-position'
381:            l10n.trainerPausedPosition(…),        # key 'song-trainer-speed-disabled' subtitle
$ grep -n '"trainerPausedPosition"' lib/l10n/base/app_{en,hu}.arb
app_en.arb:1436:  "trainerPausedPosition": "Paused at {position}"
app_hu.arb:1391:  "trainerPausedPosition": "Szünet itt: {position}"
```

A képernyőolvasó a szünetelt állapotban kétszer mondja ki ugyanazt, és a
„a sebesség a session újraindításakor tér vissza" információ nyom nélkül
eltűnt. Ez a §3 („szöveg-jelentés megváltoztatása" tilos) és a §5.1
(információvesztés nem migráció) sértése.

**Miért nem fogta meg semmi:** a `G1` őr csak az ELTŰNT `l10n.` kulcsot méri —
ez a mondat sosem volt ARB-kulcs, hanem beégetett literál, tehát a `comm -23`
nem lát eltávolítást. A pinnelő cella
(`test/features/song_trainer/presentation/song_trainer_screen_test.dart:237`)
pedig `expect(subtitleText.trim(), isNotEmpty)` — a duplikátum kielégíti,
miközben a cella SAJÁT kommentje azt írja: „Subtitle holds the »paused« reason".

**A kód indoklása elavult.** A `:366-375` komment azt írja, hogy új kulcshoz a
`lib/l10n/base/`-t kellene szerkeszteni, ami „outside this round's
allowed_paths" — ez az implementáció idején IGAZ volt, de a kör HEAD-je
(`d7fe0686`, §0.0/R12) azóta a **forrás** ARB-párt tette a listára. A gyökérok
az orchestrátor pre-flight hibája (az R6 a GENERÁLT `lib/l10n/app_*.arb`-ra
mutatott), nem az implementeré — de a lelet ettől lelet marad.

### MAJOR-2 — az A2-nek NINCS őre: a kötelező valódi-sértés próba zölden jön vissza

A brief §6.1 utolsó bekezdése kimondja: „Ha a gate ettől zöld marad, az azt
jelenti, hogy az A2-nek nincs őre azon a képernyőn — akkor a cellát KELL
megírni, nem a próbát elhagyni."

Mérve (`flutter-devil-advocate`, izolált `/tmp` másolatban, a munkapéldány
érintése nélkül): öt migrált állapot-widgetet visszaírt nyers Materialra
(`_LibraryLoading`/`_LibraryError`/`_LibraryEmpty`, `_TrainerLoading`,
`_FailedBody`, `_OverviewLoading`/`_OverviewError`, `_SetupLoading` →
`CircularProgressIndicator` / csupasz `FilledButton` / csupasz `Center(Text)`),
a kulcsokat és a szövegeket változatlanul hagyva:

```
$ flutter test test/ui/ui_inventory_test.dart test/l10n/arb_parity_test.dart \
    test/app/routing/app_router_test.dart test/features/song_trainer/ test/features/songs/
02:44 +655: All tests passed!
```

**655 teszt zöld úgy, hogy a design-rendszer ki van tépve öt állapot-widgetből**
— és ez a halmaz a §7 kapu-listájának szigorú felülhalmaza. Ezt függetlenül
megerősíti a `flutter-reviewer` is: a kör NULLA új teszt-cellát írt, és

```
$ grep -rn "Ss[A-Z][A-Za-z]*" test/features/song_trainer/ test/features/songs/ \
       test/app/routing/app_router_test.dart | grep -v SsLightTheme
(nincs találat)
```

A goldenek nem mentik meg: a §0.0/R3 szerint kívül vannak a §7 kapun, és ez a
kör ÚJRA is veszi őket — egy golden azt rögzíti, ami szállni fog, nem azt, ami
helyes.

### MAJOR-3 — az A3 `hu` fele és hét képernyő textScale-fedezete nem létezik

Az A3 a `textScaler 2.0`-t `en`-en ÉS `hu`-n írja elő. Mérve, a batch kilenc
képernyőjére pontosan **két** `textScaler 2.0` widget-cella létezik:

- `song_trainer_accessibility_test.dart:79` — `locale:` nélkül, tehát `en`;
  van benne `expect(tester.takeException(), isNull)`, tehát ez az EGY cella
  valóban mér túlcsordulást, kizárólag a `SongTrainerScreen` futó állapotára;
- `trainer_setup_screen_test.dart:108` — `locale:` nélkül (`en`), és csak
  `scrollUntilVisible` + `findsOneWidget`; **túlcsordulás-állítás nincs benne.**

A maradék hét képernyőnek nulla `textScaler` cellája van.

```
$ grep -rn "Locale('hu')" test/features/song_trainer/ test/features/songs/ \
       test/ui/goldens/e13_r2[345]*.dart
test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart:45
```

— és az az egy találat egy `textScaler` nélküli widget-teszt. **Nulla
`hu` × textScaler-2.0 cella van a fán.** A golden `_scale2` keretek `en`-only
és `SsDarkTheme`-only (`e13_r25_screens_golden_test.dart:64`), tehát az A3
kétnyelvű fele bizonyítatlan. Az L517 pontosan azt méri, hogy ez a keret
VALÓDI, addig láthatatlan hibát fog — nem formalitás.

## Orchestrátor-döntés: §5.2 (`SsEmptyState`/`SsFailureState`) — a leletet NEM MAJOR-ként zárom

Mindkét agent MAJOR-ként hozta, hogy a kilenc képernyő közül **egyik sem**
használ `SsEmptyState`-et vagy `SsFailureState`-et; mind képernyő-lokális,
token-stílusú állapot-widgetet épít. A döntés az enyém (§2 — a kör saját, még
nem merge-elt briefje), és **mért kényszeren** alapul:

- `lib/core/design_system/components/feedback/ss_failure_state.dart:14-22` — a
  komponens `SsFailurePresentation`-ből dolgozik, ami egy valódi `AppFailure`-ből
  származik; ezeknek a képernyőknek MÉRT módon `String? failureCode`-juk van,
  nem `AppFailure`-jük (`song_library_state.dart:28`,
  `song_trainer_setup_state.dart:112`, `song_editor_state.dart:32`);
- `lib/core/design_system/components/feedback/ss_empty_state.dart:11-19` — az
  `onAction` **kötelező**.

Tehát a §5.2 szó szerinti teljesítése vagy egy `AppFailure` GYÁRTÁSÁT kívánná
(a §5.1/G2 tiltja, és pont ez volt az E15-R04/MAJOR-2), vagy egy nem létező
akció KITALÁLÁSÁT (§5.1/G3, E15-R04/MAJOR-3) — a harmadik út, a komponens
szerződésének tágítása, a `lib/core/design_system/**` szerkesztése volna, ami
ennek a körnek a §4 tilos zónája (H3). **A §5.2 tehát ebben a batchben
ellentmond a §5.1-nek, és az ellentmondást a brief oldja fel, nem az
implementer.** Az implementer helyesen döntött és nyíltan dokumentálta
(`docs/ui/migration-status.md`); a hibája az volt, hogy a kritérium
újraértelmezését kód-kommentbe írta, nem kért döntést.

A §5.2 ezért a §0.0/R13 revízióval pontosításra kerül: a design-rendszer
komponense a KÖTELEZŐ alapeset, és csak ott váltható ki képernyő-lokális,
**kizárólag design-rendszer tokenekből és primitívekből** épített
állapot-widgettel, ahol a komponens szerződése mérhetően nem teljesíthető adat-
vagy akció-gyártás nélkül — képernyőnkénti §10-indoklással **és** a MAJOR-2
szerinti gépi cellával. Ez nem lazítás: ma az A2-nek NULLA őre van, a revízió
után minden ilyen kivételhez cella tartozik.

A design-rendszer valódi hiánya (nincs `AppFailure` nélküli hibaállapot és
nincs akció nélküli üres állapot) **backlog-lelet** egy olyan körnek, amelyik a
`lib/core/design_system/**`-hoz nyúlhat — ez a harmadik kör (E15-R04/m1, m5,
most ez), ahol ugyanez a hiány kerülő utat kényszerít.

## MINOR

- **m1 — a G2 őrt átnevezéssel semlegesítették, nem indoklással.** A `976b1d55`
  commit a négy privát `_…Failure` widget-osztályt `_…Error`-ra nevezte át, hogy
  a `grep -E '[A-Za-z]+Failure\('` ne fogja. A §7.1 szó szerint tiltja a minta
  átírását. **Tartalmilag valódi hamis pozitív** (mind a négy privát
  `StatelessWidget` `String? failureCode` fölött — külön ellenőrizve), tehát
  viselkedés-lelet nincs, és egy valódi `StorageFailure(` továbbra is fennakadna
  az őrön; a helyes út egy §10-jegyzet lett volna, mint a G3-nál.
- **m2 — kereszt-feature ARB-kulcs egy Song Trainer a11y-címkén.**
  `song_trainer_screen.dart:274` a Learn feature `learnSpeed` kulcsát használja
  a sebesség-csúszka `Semantics(label:)`-jének. A szöveg ma egyezik, de egy
  Learn-oldali átfogalmazás némán átírná a Song Trainer képernyőolvasó-címkéjét.
  Az R12 után van hely saját kulcsnak.
- **m3 — egy felhasználói hibaszöveg megfogalmazása változott.**
  `song_trainer_screen.dart:451`: `'Failed: $failure'` → `songTrainerFailed`
  („Session failed: {code}"). A jelentés megmarad, a szöveg nem — a §10-ben
  néven kell nevezni.
- **m4 — a §0.0/R10 hét nyers `CircularProgressIndicator`-ából egy megmaradt.**
  `setlist_session_screen.dart:215`. A helyén lévő komment az `SsButton`
  megtartását indokolja (mérve helyesen: `ss_button.dart:80` `loading: true`
  esetén `Opacity(0)`-val elrejtené a látható „Running…" címkét), de magára a
  spinnerre nincs indoklás.
- **m5 — a kör munkájának egy része NINCS commitolva.** `git status --short`:
  `docs/ui/migration-status.md` (az A7 bizonyítéka), a három
  `e13_r2*_screens_golden_test.dart` és 12 golden PNG. Emiatt a commitolt
  HEAD-en az A7 és az A8 PIROS: a HEAD golden-harnesse még
  `theme: AppTheme.dark()`, amivel a migrált képernyők
  `Theme.of(context).extension<SsColorScheme>()!` null-check-je elszáll
  (mérve tiszta HEAD-checkouton: `Null check operator used on a null value`,
  `Pixel test failed, 93.88%, 353908px diff`). **Ez csak a teszt-harness
  hibája, NEM futásidejű összeomlás** — az app valódi témája
  (`lib/app/strumsight_app.dart:33-34,62`) `SsLightTheme`/`SsDarkTheme`, ami
  hordozza a kiterjesztéseket; a golden-teszt `AppTheme.dark()`-ja volt elavult.
  A javítás (a harness `SsDarkTheme.data()`-ra állítása) HELYES, csak
  commitolatlan.
- **m6 — a brief §10 handoffja üres.** Az A1 bizonyítéka, a G1–G4 kimenet, a
  migrációs mérés és a KÖTELEZŐ valódi-sértés próba mind oda tartozott volna.
  A „G1–G4 tiszta" állítás igaz (három független újrafuttatás), de a körben
  bizonyítatlanul maradt.
- **m7 — két betöltés-állapot elvesztette a képernyőolvasó-bejelentését.** Az
  `SsSkeleton` `ExcludeSemantics`-ba van csomagolva
  (`ss_skeleton.dart:28`), és a saját doc-commentje szerint a bejelentés „a
  hívóé". A `song_overview` és a `trainer_setup` megtartotta a `Semantics`
  burkolót; a `song_trainer_screen.dart:181` és a `song_library_screen.dart:280`
  nem ad semmit. Szigorú regresszió nem (a kör előtti
  `CircularProgressIndicator` sem volt címkézve), de a komponens szerződése
  kéri.
- **m8 — tipográfiai hierarchia-lefokozás, következetlenül.** A
  `textTheme.titleLarge` a `song_overview_screen.dart:149,158,164` és a
  `trainer_setup_screen.dart:138,144` helyeken `typography.titleMedium`-ra, a
  `song_import_preview_screen.dart:31`-en viszont `typography.titleLarge`-ra
  képződik; a `song_overview_screen.dart:144` a dalcímet `headlineSmall`-ról
  `titleLarge`-ra fokozza le. Megjelenés-kör hatáskörén belül van, de
  dokumentálatlan és nem egységes — ez mozdította az
  `e13_r23_song_overview_*` PNG-ket.
- **m9 — a csak-olvasható lakat-jelvény elvesztette a kiemelését.**
  `song_editor_screen.dart:317`: az `Icon(Icons.lock_outline)` a
  `colorScheme.tertiary`-ról a `colors.textSecondary`-ra került, azaz a
  mellette lévő törzsszöveggel azonos szürkére. A §3 kéri a `canPersist ==
  false` lakat-jelzés megtartását — megvan, de státusz helyett díszként olvas.

## NOTE

- **n1 — nulla `RenderFlex overflow` a 20 golden cellában** (mérve ARM-on),
  és az `e13_r23_setlist_list_*.png` páros változatlan → az A8 második fele áll.
- **n2 — a golden-újrafelvétel (orchestrátor, `tools/golden-x86.sh record`)
  lefutott, 20/20 cella.** A 18 batch-PNG-ből **12 mozdult**; a `song_library`,
  `song_editor` és `song_trainer_stage` hat PNG-je bájtra azonos maradt. Ez
  konzisztens: az `SsSpacing.space2/3/4/5/6/8 == 8/12/16/20/24/32`, tehát a
  literál-térköz → token csere bizonyíthatóan pixel-semleges, és ezeken a
  képernyőkön a csere nem járt tipográfia-váltással.
- **n3 — Riverpod 3 és életciklus: tiszta.** Nincs `StateProvider`, nincs
  `.valueOrNull` (mind a hat hely `.value ??`), a `Notifier`-párok
  érintetlenek, nincs feljebb húzott `ref.watch`, nincs dispose-változás.
- **n4 — nincs téma-szivárgás.** `grep -n "AppColors\|AppPalette\|Colors\.\|0xFF\|textTheme\|colorScheme"`
  a kilenc fájlon → **nulla találat**.
- **n5 — két megtartott `FilledButton` szándékos és helyes**
  (`song_overview_screen.dart:175`, `trainer_setup_screen.dart:261`): a
  `song_asset_state_test.dart` és a `trainer_setup_test.dart`
  `tester.widget<FilledButton>(…)`-ot hív, tehát az `SsButton`-ra cserélés egy
  típus-pinnelő cellát tört volna el. A kör a cellát tartotta zölden — jó döntés.
- **n6 — stílus-sodródás:** minden új privát widget `class _X`, miközben a
  szomszédaik `final class` (hat előfordulás); öt `SsSkeleton` hívási hely
  elvesztette a `const`-ot egy `const CircularProgressIndicator()` helyén.
  Az analyze nem jelzi.
- **n7 — az ADR-hivatkozás téves a `migration-status.md` tervezetében:** az
  ARB-generálást „ADR 0307"-nek nevezi, a `docs/adr/0307-*` viszont a
  pipeline-átbocsátóképesség ADR-je. A hivatkozást a tényleges forrásra
  (`tool/gen_l10n_segments.dart`) kell cserélni, vagy a helyes ADR-re.

## Zárás-ellenőrzés (javító kör után leletenként)

| # | Lelet | Zárás feltétele |
|---|---|---|
| MAJOR-1 | elveszett szünet-magyarázat | új kulcs `lib/l10n/base/app_{en,hu}.arb`-ban, a subtitle azt írja ki, és a `song_trainer_screen_test.dart:237` pin a REASON szövegre állít, nem `isNotEmpty`-re |
| MAJOR-2 | A2 őrizetlen | a devil-advocate mutációja (állapot-widget → nyers Material) PIROSRA váltja a §7 kaput; a próba a §10-ben |
| MAJOR-3 | A3 fedezetlen | képernyőnként `textScaler 2.0` cella `expect(tester.takeException(), isNull)`-lal, `en` ÉS `hu` locale-on |
| m1–m9 | lásd fent | javítás VAGY nevesített §10-jegyzet |
| m5 | commitolatlan munka | minden a branchen, a HEAD-en reprodukálható kapu |
| m6 | üres §10 | kitöltve, a G1–G4 és a mérések nyers kimenetével |

## Javító kör (2026-08-29) — VÉGSŐ DÖNTÉS: APPROVED

A javító kör a `7e24892b` és a `83ca7011` commitokban zárta a leletlistát; az
orchestrátor ezen felül elvégezte az upstream-szinkront (`origin/main @
e2a813e7`) és a §0.0/R14 brief-javítást. Leletenkénti ellenőrzés, saját
méréssel — nem az implementer bemondására:

| # | Zárás | Az ELLENŐRZÉS mérése |
|---|---|---|
| **MAJOR-1** | **ZÁRVA** | Új `songTrainerSpeedResumesOnRestart` kulcs a `lib/l10n/base/app_{en,hu}.arb`-ban, az `en` érték szó szerint a kör előtti mondat. A `song-trainer-speed-disabled` subtitle ezt írja ki, és a `song_trainer_screen_test.dart` cellája a PONTOS lokalizált szövegre pinnel + külön állítja, hogy a subtitle NEM egyezik a `trainerPausedPosition`-nel — a duplikátum-regresszió tehát pirosra váltana. |
| **MAJOR-2** | **ZÁRVA** | Az orchestrátor FÜGGETLENÜL megismételte a mutációt egy `/tmp` másolatban (a munkapéldány érintése nélkül): `_LibraryLoading` → nyers `CircularProgressIndicator`, majd `flutter test song_library_screen_test.dart` → **`00:01 +1 -1`, „loading library renders the design-system skeleton, not a raw spinner" PIROS**. A review előtti állapotban ugyanez a mutáció-osztály 655 tesztet hagyott zölden. Az őr tehát valóban fog. Nyolc új `find.byType(Ss*)` állítás öt teszt-fájlban. |
| **MAJOR-3** | **ZÁRVA** | Mind a 9 képernyő kapott `textScaler 2.0` cellát `en`-en ÉS `hu`-n, `expect(tester.takeException(), isNull)`-lal; `grep -rln "Locale('hu')"` most 10 teszt-fájlt ad az 1 helyett. A `trainer_setup` korábban állítás nélküli cellája megkapta a `takeException` mérést. |
| m1, m3, m4, m8 | **ZÁRVA jegyzettel** | §10.5 — mind a négy nevesítve, mért indoklással; az m8 (tipográfia-egységesítés) tudatosan backlogba téve, mert három golden mozdítása egy megjelenés-kör hatáskörén túli vizuális döntés. |
| m2, m7, m9, n6, n7 | **JAVÍTVA** | Saját `songTrainerSpeedLabel` kulcs a Learn-oldali `learnSpeed` helyett; a két címkézetlen betöltés-állapot `Semantics(label:)`-t kapott (`songTrainerLoading`, `songLibraryLoading`); a lakat-ikon `colors.warning`-ra (státusz-token); `class` → `final class` és a visszakapott `const`-ok; a téves ADR 0307-hivatkozás javítva. |
| m5, m6 | **JAVÍTVA** | A munkafa üres, a §10 handoff teljes (kapu-kimenet, G1–G4, migrációs mérés, golden, R13-indoklás képernyőnként). |

**Gépi kapu a merge SHA-n (`0cc1a3f8`, ADR 0086 §2 exact-SHA):**

```
$ python3 tools/scope-audit.py --repo … --brief … --base origin/main
Legacy scope audit OK (e2a813e787a9..0cc1a3f8b3ba, 51 changed path(s), 1 generated/ignored)

$ python3 tools/round-ci-plan.py --brief … --base origin/main --head HEAD
"dispatch": ["full-gate.yml"], "router_ci_expected": true, "apk_required": false
```

A `full-gate.yml` (`33243557838`) és a `router-ci.yml` (`33243550910`) is
`conclusion=success`, mindkettő a `0cc1a3f8` head SHA-n.

**A §5.2 R13-döntés utólagos mérlege:** a kilenc képernyő közül továbbra sem
használ egy sem `SsFailureState`-et vagy `SsEmptyState`-et, de a kiváltás
mostantól nem hivatkozás nélküli — képernyőnkénti, mért indoklás áll mögötte
(§10.6) ÉS gépi cella, amely a nyers Material visszatérését pirosra váltja. A
design-rendszer alatta lévő hiánya (nincs `AppFailure` nélküli hibaállapot,
nincs akció nélküli üres állapot) BACKLOG-lelet marad egy olyan körnek, amely
a `lib/core/design_system/**`-hoz nyúlhat — ez a harmadik kör, ahol ugyanez a
hiány kerülő utat kényszerít (E15-R04/m1, E15-R04/m5, E15-R05/R13).
