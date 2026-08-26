# E13-R20 — Review (Chord Library, Learning Path és Lesson UI)

- **Reviewer:** Claude (Opus 5), orchestrátor-ülés — read-only review (ADR 0055)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Branch:** `sonnet-impl/e13-r20-chords-and-learning-ui`
- **Review-elt HEAD:** `2b949692` (induló HEAD: `89a36dc8`, a pre-flight commit)
- **Dátum:** 2026-08-26
- **VERDIKT (1. kör):** ⛔ **CHANGES REQUESTED** — 1 MAJOR, 2 MINOR

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
