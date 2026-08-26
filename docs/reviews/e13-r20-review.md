# E13-R20 — Review (Chord Library, Learning Path és Lesson UI)

- **Reviewer:** Claude (Opus 5), orchestrátor-ülés — read-only review (ADR 0055)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Branch:** `sonnet-impl/e13-r20-chords-and-learning-ui`
- **Review-elt HEAD:** `2b949692` (induló HEAD: `89a36dc8`, a pre-flight commit)
- **Dátum:** 2026-08-26
- **VERDIKT (1. kör):** ⛔ **CHANGES REQUESTED** — 1 MAJOR, 2 MINOR
- **VÉGSŐ VERDIKT (javító kör #3 után, `1cd05fc6`):** ✅ **APPROVED** — 0 nyitott
  lelet, teljes zöld kapu. A részletes indoklás: **[§10](#10-végső-döntés--approved)**.
  Ez a jelentés a kör TELJES történetét őrzi: §1–§5 az 1. kör, §6 a javító kör #1,
  §7–§8 a javító kör #2 és a H5 halt, §9–§10 a javító kör #3 és a merge-döntés.

---

## 1. Amit magam mértem (nem bemondás)

### 1.1 Kör-jelzés és scope

| Mérés | Eredmény |
|---|---|
| `.codex-round-status` | `status=done`, `head=2b949692`, `dirty_files=2` |
| `dirty_files != 0` kivizsgálva (§3 kötelező) | a két fájl az orchestrátor SAJÁT prompt-fájlja (`.round-prompt-e13-r20.md`, követetlen) és egy azóta törölt kapart teszt; **implementer-kimenet egyik sem** |
| `scope_audit=` a jelzésfájlban | **HIÁNYZIK** → nem bizonyíték, kézzel futtatva |
| `python3 tools/scope-audit.py --base 89a36dc8` | `Legacy scope audit OK (89a36dc856bb..2b949692ae51, 25 changed path(s))` |

A 25 útvonal mind az `allowed_paths`-on belül. Új `lib/features/**/*_screen.dart`
NEM készült (a `ChordDetailView` a `widgets/` alatt él), ezért a
`test/ui/ui_inventory_test.dart` `hasLength(84)` érintetlen maradt — a §0.0/R12
jogosultságát a kör nem használta ki, mert nem volt rá szükség.

### 1.2 Gate — újrafuttatva SAJÁT kézzel, izolált klónban

`/tmp/review-e13-r20` (friss klón a kör-HEAD-ről + `prepare-flutter-generated.sh`),
a brief §7 szerinti 17 útvonallal:

```
MINDEN GATE ZÖLD.
format · analyze · 17 teszt-útvonal · architecture · secrets · l10n   → 22/22 zöld
```

Az implementer 22/22-es állítása tehát **független méréssel is áll**.

Ezen felül a §0.0/R2 húsz meglévő tesztje (a teljes `test/features/chords/` +
`test/features/learn/` fa): **`00:54 +234 ~1: All tests passed!`** — a migráció
egyetlen korábban zöld cellát sem tört el, és egyet sem `skip`-elt el (az egy
`~1` a körtől független, korábbi skip).

### 1.3 CI (exact-SHA)

| Workflow | Run | Head SHA | Állapot |
|---|---|---|---|
| `router-ci.yml` | [32915928220](https://github.com/wolfcasaba/strumsight/actions/runs/32915928220) | `2b949692` | ✅ success |
| `full-gate.yml` | [32915931120](https://github.com/wolfcasaba/strumsight/actions/runs/32915931120) | `2b949692` | ⏳ in_progress a review írásakor |

A CI-tervező (`tools/round-ci-plan.py`) `dispatch: ["full-gate.yml"]`-t adott
(`apk_required: false`, natív útvonalat a diff nem érint), `router_ci_expected:
true`. **A MAJOR javítása után mindkettőt újra kell dispatch-elni** — a mostani
futások a javítás előtti SHA-t mérik.

### 1.4 Valódi-sértés próbák — HÁROM, a reviewer SAJÁT kezével

Az implementer §10-ben leírt próbáját nem fogadtam el bemondásra; magam
rontottam el a kódot az izolált klónban, majd visszaállítottam.

| Próba | Rontás | Mért eredmény |
|---|---|---|
| **A2** | `readingOrder(..., mirrored: false)` a szöveghez, míg a rajz a valós `mirror`-t kapja | **3 cella PIROS**: `chord_diagram_semantics_test.dart` balkezes cellája + `chord_diagram_text_test.dart` „at the threshold" és „above the threshold". A jobbkezes és a barre-cella **zöld maradt** — pontosan a §6.1 három-cellás mátrix |
| **A3** | `l10n.learnLockedReason(...)` → `l10n.learnLocked` (indoklás nélküli felirat) | **A3 PIROS**, A5/A8 zöld maradt |
| **A5** | `LessonProgressController.build()` → üres map (a haladás nullázása) | **A5 PIROS**, A3/A8 zöld maradt |

Mindhárom cella tehát **valódi kapu**, nem díszlet, és élesen szeparált.

### 1.5 §3 tilalom — a domain-logika érintetlen

A `lib/features/learn/model/lesson.dart` MÓDOSULT, ezért külön megnéztem: a diff
**tisztán additív** (`Lessons.forChordPractice(String)` factory). Nem érinti az
`isUnlocked` előfeltétel-számítást, a `Lessons.all` listát, a `nextAfter`
láncot, sem a haladás sémáját. A `chord-practice-<label>` id a curriculum
láncon KÍVÜL van (mint a daily challenge és az Analyze-import), tehát nem tud
szintet feloldani vagy blokkolni. **A §3 tilalma megtartva.**

---

## 2. Leletek

### 🔴 MAJOR-1 — az akkord-részletnézet EGYETLEN belépője 40 dp-s érintési cél (a 48 dp-s szerződés alatt)

**Hol:** `lib/features/chords/screens/chord_library_screen.dart:41-56`
(a `Positioned` + `IconButton`, `key: Key('chord-open-detail-$label')`).

```dart
Positioned(
  right: -6,
  bottom: 8,
  child: IconButton(
    ...
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    visualDensity: VisualDensity.compact,
```

**A megsértett szerződés — merge-elt, és a fán konstansként is kódolva:**

- [ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md)
  §Döntés 5: „A kritikus komponensek érintési célja **≥ 48 dp**."
- `lib/core/design_system/foundations/ss_semantics.dart:5` →
  `SsSemantics.minimumInteractiveDimension = 48`, amit a
  `test/core/design_system/foundations_test.dart:26` pinnel.

**Mérve (eldobható próbateszt, futtatva és törölve):**

```
PROBE required=48.0dp actual=40.0x40.0 btnRight=114.0 stackRight=108.0 overflow=6.0
Expected: true
  Actual: <false>
ADR 0280 §5 requires >= 48dp for a critical touch target
```

Két, egymást erősítő hiba egy helyen:

1. **40 × 40 dp** a tényleges méret — 8 dp-vel a szerződés alatt;
2. a `right: -6` a gombot **6 dp-vel a `Stack` határán KÍVÜLRE** tolja
   (`btnRight=114` vs `stackRight=108`). A `clipBehavior: Clip.none` miatt ez a
   sáv *látszik*, de Flutterben a szülő méretén kívülre eső terület **nem
   találati felület** — a tényleges, koppintható cél így ≈ **34 × 40 dp**.

**Miért MAJOR és nem MINOR:** ez a gomb az akkord-részletnézet **egyetlen**
belépője, tehát az A6 (gyakorlás-akció) és az A7 (részletnézet) teljes
útvonala rajta függ — a „kritikus komponens" definíció szerint teljesül. Ezt
ráadásul egy kifejezetten **hozzáférhetőségi** kör (ADR 0282, „a tartalom vak
felhasználónak ne vesszen el") vezeti be, ahol a motoros hozzáférhetőség
alatti méret önellentmondás. A `chord_tile_a11y_test.dart` azért maradt zöld,
mert a semantics-címkéket méri, nem a célméretet — a mérce itt nem volt
jelen, nem pedig teljesült.

**Javasolt irány (NEM kész patch):** a `constraints`-et a design system saját
konstansára állítani (`SsSemantics.minimumInteractiveDimension`, azaz 48×48),
`visualDensity: VisualDensity.compact` nélkül, és a `right: -6`-ot úgy
megszüntetni, hogy a gomb TELJES egészében a `Stack` határain belülre essen
(pl. a csempe `SizedBox` szélességének/magasságának megnövelése, vagy a gomb
`right: 0`/`bottom: 0` pozícióra húzása). A javításhoz **kell** egy cella,
ami a hibát pirosra fogta volna: a fenti próbateszt mintájára mérje a
`tester.getSize(...)`-t a `SsSemantics.minimumInteractiveDimension` ellen
(`test/features/chords/chord_tile_a11y_test.dart` vagy
`chord_library_test.dart` — mindkettő az `allowed_paths`-on van).

### 🟡 MINOR-1 — doc-comment nem létező ADR-szakaszra hivatkozik

**Hol:** `lib/core/design_system/components/music/ss_chord_diagram.dart:38-41`

```dart
/// caller — the design system does not own this string (no l10n layer
/// here; ADR 0424 §5.5 keeps user-facing text out of this tree).
```

**Mérve:** a `docs/adr/0424-localization-resilience-contract.md` szakaszai
1., 2. (2.1–2.6), 3., 4., 5. — **`§5.5` NEM létezik**; az §5 a
„Következmények". A ténylegesen ide tartozó szabály a **§2.3** („A beégetett
szöveg guardja RACSNI, befagyasztott alaphalmazzal") — pontosan az az őr
(`test/l10n/hardcoded_string_guard_test.dart`), amelyik az első gate-futáson
valódi leletet adott, és amiért a `baseFretLabel` a hívóhoz került.

A kör saját szabálya („doc-commentben csak bizonyított állítás") pont ezt
zárja ki: a hivatkozás ellenőrizhetetlen helyre küldi az olvasót. **Javítás:**
`§2.3`-ra átírni.

### 🟡 MINOR-2 — a `learnLocked` ARB-kulcs holt maradt

**Mérve:** a kör eltávolította az egyetlen hívási helyét
(`lesson_list_screen.dart` régi `SnackBar`-ága), és

```
$ grep -rn "learnLocked\b" lib/ test/ --include=*.dart | grep -v app_localizations
(nincs találat)
```

A kulcs viszont bent maradt a `lib/l10n/base/app_{en,hu}.arb` **forrásban**
(és így a generált aggregátumban is). Nem gate-hiba, de holt, felhasználónak
szánt szöveg a lokalizációs forrásban, amit a fordítói kör tovább görget.
**Javítás:** törölni mindkét forrás-szegmensből, majd
`dart run tool/gen_l10n_segments.dart --write` + `flutter gen-l10n`, és a
regenerált aggregátumot is commitolni. (Ha a törlés bármelyik paritás-őrt
megmozdítja, az önmagában NOTE-ra fokozható le — de a törlés a tiszta út.)

---

## 3. Acceptance criteria — tételes bizonyíték

| # | Kritérium | Verdikt | Bizonyíték (mind SAJÁT futtatás) |
|---|---|---|---|
| A1 | a diagramnak szöveges alternatívája van | ✅ | `chord_diagram_text_test.dart` „A1: … not just the chord name" — a `Semantics` címke `contains('fingering:')` és `isNot('Am')`. A forrás a `SsChordDiagram.readingOrder`, amit a festő is használ (`_SsChordDiagramPainter.paint` → `SsChordDiagram.slotFor`) — egy leképezés, nem két másolat |
| A2 | balkezes: rajz ÉS szöveg tükrözött | ✅ | három-cellás mátrix zöld; **valódi-sértés próba 1.4: 3 cella pirosra vált**, a jobbkezes/barre zöld marad |
| A3 | a zárolás oka megjelenik | ✅ | `learning_path_test.dart` A3-cella; a felirat MINDIG látszik (nem koppintásra) — helyes, mert `enabled: false` mellett a `ListTile` koppintást nem is kap; **próba 1.4: piros** |
| A4 | hiányzó erőforrás nem omlaszt (§0.0/R9) | ✅ | `lesson_offline_test.dart` két cellája: a `Xyz9` akkord `music_off` ikonnal + felolvasható névvel jelenik meg (nem néma `shrink`), és a rá épülő lecke **lejátszható marad** (Play → Pause). Kitalált letöltés-gomb NINCS — a §0.0/R9 szűkítést a kör betartotta |
| A5 | a meglévő haladás megmarad | ✅ | `learning_path_test.dart` A5-cella előre feltöltött `StorageKeys.lessonProgress`-szel; **próba 1.4: piros, ha a haladás nullázódik** |
| A6 | a gyakorlás a megnyitott akkorddal paraméterez | ✅ | `chord_library_test.dart`: `expect(learnScreen.lesson.chordSequence, ['G'])` — a `'G'` szándékosan NEM a katalógus első eleme (az a `'C'`), tehát a „mindig az elsővel indul" hibát a cella megfogja |
| A7 | keresés/szűrés/kedvencek + állapotmegőrzés | ✅ | `chord_library_test.dart`: szűrés, üres állapot, és a keresési szöveg túléli a részletnézet megnyitását/bezárását; a kedvencek a változatlanul zöld `favorite_chords_test.dart`-on |
| A8 | lineáris, hozzáférhető alternatíva | ✅ | `learning_path_test.dart`: egyetlen `ListView`, `scrollUntilVisible` végigér az INTERMEDIATE → ADVANCED → utolsó lecke láncon |
| A9 | golden-felvétel, 2 keret | ✅ | `e13_r20_screens_golden_test.dart`: **6 valódi `matchesGoldenFile` cella** (akkordtár, akkord-részlet, tanulási út × {1.0, 2.0} `TextScaler`), `skip` NÉLKÜL; a 6 PNG a diffben |

**Az acceptance-oldal tehát hiánytalan.** A MAJOR-1 nem acceptance-hiány, hanem
egy merge-elt, keresztmetszeti szerződés (ADR 0280 §5) megsértése, amit a kör
`gate_tests`-e szerkezetileg nem mért.

---

## 4. Architektúra és termékhatár

| Ellenőrzés | Eredmény |
|---|---|
| design system ↛ feature (E13-R02 határ) | ✅ `ss_chord_diagram.dart` egyetlen importja `package:flutter/material.dart`; a `frets`/`baseFret`/`mirrored`/színek mind paraméter — a `leftHandedProvider`-t a feature-réteg olvassa. Az őr (`architecture_dependency_test.dart`) zöld |
| feature → design system CSAK `public.dart`-on át | ✅ `chord_diagram.dart` `import '../../../core/design_system/public.dart'`; az export felvéve (`public.dart:52`). Ez az **E13-R16/F8 hibaosztály elkerülve** |
| a design system nem birtokol felhasználói szöveget | ✅ a `baseFretLabel` a hívótól jön; a `hardcoded_string_guard` zöld (az implementer §10-je szerint ez az első futáson VALÓDI lelet volt, és a felelősség-határ áthelyezésével oldotta meg — helyes irány, nem az őr kerülgetése) |
| nincs új útvonal (§0.0/R8) | ✅ `lib/app/routing/**` érintetlen; a részletnézet és a gyakorlás `Navigator.push(MaterialPageRoute)` — a `route_literal_guard` zöld |
| §3 domain-tilalom | ✅ lásd 1.5 — tisztán additív factory |
| ARB: forrás vs generált (§0.0/R1) | ✅ az új kulcsok a `lib/l10n/base/app_{en,hu}.arb` FORRÁSBAN, az aggregátum generálva és commitolva |

---

## 5. Merge-döntés

**⛔ CHANGES REQUESTED.** A MAJOR-1 nyitva → merge TILOS (ADR 0052).

A javító kör a lánc NORMÁL útja (user-döntés 2026-07-31), nem halt-ok:
ugyanaz a motor (`sonnet-impl`), a fenti leletlistával, ugyanezen az ágon.

**A javító kör után kötelező:**

1. a gate ÚJRA, friss `/tmp` klónban (reviewer kézzel);
2. leletenkénti zárás-ellenőrzés — a MAJOR-1 javításához **tartozzon cella**,
   amely a 40 dp-s állapotot pirosra fogta volna;
3. **exact-SHA CI ÚJRA-dispatch** (`full-gate.yml` + `router-ci.yml`) a javító
   commit SHA-ján — a mostani `2b949692`-es futások a javítás előtti fát mérik;
4. ez a jelentés frissül (APPROVED vagy újra CHANGES REQUESTED) a javító
   commit SHA-jával.

---

## 6. Javító kör #1 — újra-ellenőrzés (`1a9e3bb3`)

Mind a három lelet **ZÁRVA**, leletenként ellenőrizve:

| Lelet | Javítás | Az ellenőrzés bizonyítéka |
|---|---|---|
| **MAJOR-1** | `constraints` → `SsSemantics.minimumInteractiveDimension` (48), `VisualDensity.compact` elhagyva, `right/bottom: 0` (nincs többé `Stack`-en kívüli, nem találati sáv) | ÚJ őr-cella: `chord_tile_a11y_test.dart` „the chord-detail open button meets the 48dp minimum touch target". **Reviewer valódi-sértés próbája:** a 28 dp-s `constraints` ideiglenes visszaállítása a cellát PIROSRA váltotta, PONTOSAN az eredeti mérettel — `ADR 0280 §Döntés 5 requires >= 48.0dp …; measured Size(40.0, 40.0)` —, majd visszaállítva zöld. A guard tehát valódi regressziós kapu, nem díszlet |
| **MINOR-1** | a doc-comment hivatkozása `ADR 0424 §5.5` → `§2.3` | a `§2.3` létezik és tényleg a beégetett-szöveg racsni |
| **MINOR-2** | `learnLocked` törölve mindkét `base/` forrásból + regenerált aggregátum | `grep` 0 találat; az `l10n` gate-lépés zöld |

A `test/features/chords/` + `test/features/learn/` fa: **235 zöld** (a 234-ből +1 az
új őr-cella), 0 piros.

## 7. Javító kör #2 — a CI golden-bukása (L486), és a MARADÉK

### 7.1 A diagnózis és a javítás

Az exact-SHA CI a `2b949692` és az `1a9e3bb3` SHA-n is PIROS volt, **kizárólag**
a `test/ui/goldens/e13_r20_screens_golden_test.dart` négy celláján. A lokális
gate ezt szerkezetileg nem tudja elkapni: a felvétel ezen az **ARM** boxon, a
verifikáció **x86** CI-on történik ([L486](../LESSONS.md)).

A gyökérok az L486 hibaosztálya volt, **kontrollesettel is igazolva**:

| Képernyő | Nagy felületű kitöltés | 1. CI (`2b949692`) |
|---|---|---|
| chord library | **0 db `Card(`** — nincs séma-származtatott felület | ✅ zöld (kontroll) |
| learning path | `_LessonTile` `Card(` explicit szín NÉLKÜL → seed-származtatott `surfaceContainerLow`, 16 csempén | ❌ 5976 px |
| chord detail | `ActionChip` explicit `backgroundColor` nélkül | ❌ 1 px |

Ellenpélda ugyanazon a bukó képernyőn: a `_ContinueCard` KONSTANS színt ad
(`AppColors.primary.withValues(alpha: 0.14)`) — és nem adott diffet.

A javítás az L486 által előírt konstans színforrás
(`context.palette.surface`/`.border`, `AppPalette.dark` **`const`** palettából),
majd a 6 golden újrafelvétele. **Mérhetően működött:**

| Golden | 1. CI | 3. CI (`e0388738`) |
|---|---|---|
| `learning_path_compact` | 5976 px | **8 px** |
| `learning_path_compact_scale2` | 1992 px | ✅ **zöld** |
| `chord_library` (×2) | ✅ zöld | ✅ zöld |
| `chord_detail_compact` | 1 px | 1 px |
| `chord_detail_compact_scale2` | 1 px | 1 px |

### 7.2 Ami MARAD — és miért nem oldható meg ebből a körből

A [full-gate 32918668534](https://github.com/wolfcasaba/strumsight/actions/runs/32918668534)
futáson a **teljes suite és a randomizált property gate zöld**; az EGYETLEN
piros a fenti három golden-cella, **mind `0.00%`**, 1 / 8 / 1 pixel.

Ez már **nem** színforrás-kérdés (a színforrás-osztály mérhetően megszűnt:
5976 → 8 px, és az egyik cella teljesen zöldre váltott), hanem **maradék
cross-architektúra raszterizációs zaj**: ARM-on felvett PNG, x86-on
verifikálva, **nulla toleranciájú** `LocalFileComparator`-ral. Az L486 ezt
ki is mondja: *„a hordozhatóság ELVBŐL nem mérhető ezen a boxon … az egyetlen
valódi őr az exact-SHA CI-futás"*, és ezért nincs is hozzá őrteszt.

Az 1 pixeles chord-detail diff végig 1 px volt (a színjavítás előtt is), tehát
sosem terület-jellegű: a részletnézet `size: 180`-as diagramja
`canvas.drawCircle(..., colGap * 0.28, …)`-t rajzol — egy lebegőpontos sugár
kerekítése a körív peremén architektúránként egyetlen pixelt elmozdíthat.
Újrafelvétellel ez nem oldható meg: minden ARM-on készült felvétel ARM-pixeleket rögzít.

**A három megmaradt út MIND az orchestrátor hatáskörén KÍVÜL van:**

1. **tolerancia-komparátor** (nem-nulla pixelküszöb) — ez a MÉRCE megváltoztatása,
   ráadásul osztott teszt-infrastruktúra; „a mérce nem módosulhat attól, akit mér";
2. **a goldenek CI-on való felvétele** (artifact-visszatöltés) — `.github/**`,
   azaz TILOS zóna;
3. **a golden-készlet szűkítése / cellák `skip`-je** — a mérce meghamisítása,
   az A9 feladása.

Ezért a kör **H5-tel megáll**: nem azért, mert a kód rossz, hanem mert a zöld
kapu egy olyan infrastrukturális réshez ért, amit csak tágabb jogosultságú
(önjavító / emberi) döntés zárhat be.

## 8. DÖNTÉS a halt pillanatában: ⛔ **HALT — H5** (CI a körön háromszor piros)

> ⚠ **Ezt a szakaszt a §9–§10 FELÜLÍRJA.** A halt a §7.2 szerint egy
> infrastrukturális réshez ért; az ADR 0112 önjavító köre a rést bezárta
> ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md),
> merge-elve a `main`-re `52ce9003`-ként), és a kör a javító kör #3-mal
> folytatódott. A §8 alábbi tartalma a halt pillanatának hű jegyzőkönyve,
> történeti értékkel — a kör VÉGSŐ verdiktje a **§10**.

**A kód-oldal KÉSZ és bizonyított:**

- mind a 9 acceptance-cella teljesül, reviewer-próbákkal alátámasztva (A2/A3/A5
  valódi-sértés próbák + a 48 dp-s guard próbája — mind pirosra vált a rontáson);
- `tools/round-gate.sh` **22/22 zöld**, kétszer, két külön izolált `/tmp` klónban
  (`2b949692` és `e0388738`);
- `test/features/chords/` + `test/features/learn/`: **235 zöld**;
- scope-audit **OK** (27 útvonal, 1 generated/ignored = ez a jelentés);
- `router-ci.yml` a `2b949692` SHA-n **success**;
- a CI teljes suite-ja és a randomizált property gate az `e0388738`-on **zöld**.

**Merge TILOS**, amíg a három golden-cella piros (ADR 0052 — a zöld kapu nem
lazul). A kör-branch, a review és a teljes diagnózis publikálva; a folytatás
az önjavító kör dolga a §7.2 három útjának valamelyikével (a **2. út**, a
goldenek CI-oldali felvétele, tűnik a szerkezetileg helyesnek — az szünteti meg
a felvétel↔verifikáció architektúra-eltérést, ahelyett hogy a mércét lazítaná).

---

## 9. Javító kör #3 — a H5 halt feloldása (`1cd05fc6`)

- **Review-elt HEAD:** `1cd05fc6` (a javító kör #3 commitja)
- **Dátum:** 2026-08-26, orchestrátor-ülés (Claude, Opus 5)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)

### 9.1 Upstream-szinkron a javítás ELŐTT (ADR 0087 §0.3)

A folytatás nem indulhatott a branch régi szerződésével. Mérve:

```
$ git merge-base --is-ancestor origin/main HEAD
ANCESTOR: NO — needs merge
```

Az önjavító kör (`52ce9003`) beépítve; a konfliktus **kizárólag** a kör SAJÁT
briefjében állt elő, és **tisztán additív** volt mindkét oldalon: a branch
§0.0/R5–R13 pre-flight mérései vs. a `main` §0.1/R14 golden-revíziója. A
feloldás **mindkettőt megőrzi** — a `main`-ről semmi nem esett ki (a
`git diff origin/main` a briefre csak a branch saját §0.0/R9-szűkítését és a
státuszsort mutatja).

**Mérve, hogy ez nem elveszett munka:** ugyanezt a merge-et az önjavító session
már publikálta (`1e75d691`), és a két, EGYMÁSTÓL FÜGGETLEN feloldás fája
**bitre azonos** (`git diff HEAD FETCH_HEAD` → üres). A duplikátum eldobva, a
branch a publikált `1e75d691`-re állítva.

### 9.2 A lelet MÉG NYITOTT volta — a reviewer saját mérése

Nem bemondásra: a halt utáni HEAD-en (`1e75d691`) magam futtattam a merge-kapu
architektúráján:

```
$ tools/golden-x86.sh check test/ui/goldens/e13_r20_screens_golden_test.dart
Golden "goldens/e13_r20_chord_detail_compact.png":        0.00%, 1px diff
Golden "goldens/e13_r20_learning_path_compact.png":       0.00%, 8px diff
Golden "goldens/e13_r20_chord_detail_compact_scale2.png": 0.00%, 1px diff
00:55 +3 -3: Some tests failed.
EXIT=10
```

**Pontosan a full-gate [32918668534](https://github.com/wolfcasaba/strumsight/actions/runs/32918668534)
három cellája, pontosan 1 / 8 / 1 px.** Ez egyben az ADR 0426 eszközének
független hitelesítése is: a CI verdiktjét ~75 másodpercben reprodukálja, a
17 perces exact-SHA futás helyett.

### 9.3 A javítás és a leletenkénti zárás

| Lelet | Javítás | Az ellenőrzés bizonyítéka (mind SAJÁT futtatás) |
|---|---|---|
| **H5 / 3 golden-cella** | `tools/golden-x86.sh record` — a goldenek a **merge-kapu architektúráján** (Flutter 3.44.2 / linux-amd64, qemu-user) újrafelvéve | `tools/golden-x86.sh check` → **`00:55 +6: All tests passed!`, EXIT=0**, `failures/` könyvtár NEM keletkezett |

**A diff pontosan akkora, amekkorának lennie kell** — 3 PNG, se több, se
kevesebb, egyezően az ADR 0426 3. mérésével („a felvétel PONTOSAN 3 PNG-t írt
át") és a §7.2-ben megnevezett három cellával:

```
$ git diff --name-status 1e75d691..1cd05fc6
M	docs/rounds/e13-r20-chords-and-learning-ui.md
M	test/ui/goldens/goldens/e13_r20_chord_detail_compact.png
M	test/ui/goldens/goldens/e13_r20_chord_detail_compact_scale2.png
M	test/ui/goldens/goldens/e13_r20_learning_path_compact.png
```

**Termékkód és teszt NEM változott** ebben a javító körben — ahogy a
findings-lista előírta. Az A1–A9 acceptance-bizonyítékok (§3) ezért
érintetlenül állnak; a §1.4 három valódi-sértés próbája és a §6 48 dp-s
őr-próbája változatlanul érvényes.

### 9.4 A mérce NEM lazult — tételesen

Az ADR 0426 §„Amit ez a döntés NEM tesz" pontjai a diffen ellenőrizve:

| Állítás | Mérés |
|---|---|
| a komparátor változatlan | a `LocalFileComparator` nulla toleranciájú; a teszt-fájl (`e13_r20_screens_golden_test.dart`) **nem módosult** |
| a golden-készlet változatlan | 6 `matchesGoldenFile` cella, `skip` nélkül; a PNG-k száma és neve azonos |
| a `.github/**` és a `tools/**` érintetlen | a kör diffje 4 útvonal, egyik sem az |
| a `tools/round-gate.sh` változatlan | a kör diffje nem érinti |

A golden-cellákat ezután **kettő** mérce méri (lokálisan az x86-konténer, a
kapuban a CI teljes suite-ja) — miközben a korábbi lokális ARM-mérésük
bizonyítottan hamis zöldet adott.

### 9.5 Scope-audit

A wrapper jelzése elsőre `scope_audit=VIOLATION` volt, EGYETLEN útvonalra:
`.round-prompt-e13-r20-fix3.md`. **Ez az orchestrátor SAJÁT, követetlen
prompt-fájlja, nem implementer-kimenet** — ugyanaz a hamis-pozitív osztály,
amit a §1.1 az előző körön már rögzített (`dirty_files=2`). A fájl a
munkapéldányon KÍVÜLRE helyezve, az audit újrafuttatva:

```
$ python3 tools/scope-audit.py --repo … --brief … --base 1e75d691a0d8
Legacy scope audit OK (1e75d691a0d8..1cd05fc646cb, 4 changed path(s), 0 generated/ignored)
AUDIT_EXIT=0
```

Mind a 4 útvonal a brief `allowed_paths`-án belül van (és a javító körre
SZŰKÍTETT két-elemű listán is: `test/ui/goldens/goldens/**` + a brief §10).

### 9.6 Gate — újra, izolált klónban, saját kézzel

`/tmp/review-e13-r20-fix3` (friss klón a `1cd05fc6` HEAD-ről +
`prepare-flutter-generated.sh`), a brief §7 szerinti 16 útvonallal:

```
MINDEN GATE ZÖLD.
format · analyze · 16 teszt-útvonal · architecture · secrets · l10n  → 21/21 zöld
GATE_EXIT=0
```

### 9.7 CI — exact-SHA, a merge SHA-ján

| Workflow | Run | Head SHA | Állapot |
|---|---|---|---|
| `full-gate.yml` | [32928072029](https://github.com/wolfcasaba/strumsight/actions/runs/32928072029) | `1cd05fc6` | ✅ **success** |
| `router-ci.yml` | [32928068125](https://github.com/wolfcasaba/strumsight/actions/runs/32928068125) | `1cd05fc6` | ✅ **success** |

A CI-tervező (`tools/round-ci-plan.py`) verdiktje: `dispatch: ["full-gate.yml"]`,
`apk_required: false`, `router_ci_expected: true` (a `docs/rounds/**` útvonalon).
Mindkét futás `headSha`-ja egyezik a lokális HEAD-del — a run tehát
merge-evidencia (ADR 0086 §2). Az `origin/main` a dispatch óta **nem mozdult**
(`52ce9003`).

> A jelen review-commit új HEAD-et képez, ezért a **teljes exact-SHA kapu
> ÚJRA fut** a végleges merge SHA-n; a merge kizárólag annak zöldje után
> történik. A fenti két run a `1cd05fc6` fa-tartalmát hitelesíti, amely a
> review-commit után **bitre azonos** marad (a commit csak ezt a jelentést
> adja hozzá).

---

## 10. VÉGSŐ DÖNTÉS: ✅ **APPROVED**

Minden lelet zárva, minden acceptance-cella bizonyítva, a zöld kapu hiánytalan:

- **0 nyitott BLOCKER / MAJOR / MINOR** — a MAJOR-1, MINOR-1, MINOR-2 (§6), az
  L486 színforrás-osztály (§7.1) és a H5 golden-rés (§9) mind lezárva;
- mind a **9 acceptance-cella** teljesül (§3), reviewer valódi-sértés
  próbáival alátámasztva (A2 → 3 cella pirosra vált, A3, A5, és a 48 dp-s őr);
- `tools/round-gate.sh` **21/21 zöld**, izolált `/tmp` klónban, saját kézzel;
- `tools/golden-x86.sh check` **6/6 zöld** a merge-kapu architektúráján;
- `test/features/chords/` + `test/features/learn/`: **235 zöld**;
- scope-audit **OK** (4 útvonal, 0 generated/ignored);
- **Full Gate + Router CI success** a merge SHA-n.

**A merge engedélyezett** az ADR 0052 változatlan zöld kapuja alatt.

### 10.1 Amit ez a kör a láncnak tanít

A H5 halt **nem** termékkód-hiba volt, és nem is a kör hibája: egy
mérés-architektúra rés (ARM-felvétel ↔ x86-verifikáció, nulla tolerancia)
tette a lokális kaput hamisan zölddé és a CI-t igazul pirossá. A javítás
iránya a helyes volt — **a mérés helyét igazítottuk a kapuhoz, nem a mércét a
kódhoz**. A rés bezárása után ugyanaz a kód, egyetlen sor termékváltoztatás
nélkül, elsőre zöld lett a kapun.
