# Review — E02-R14 (Strum Pattern & Chord Progression módok)

- **Branch:** `codex/e02-r14-strum-progression-modes`
- **Reviewelt HEAD:** `9488507` (impl `5f8de89` + §10 handoff `9488507`, pre-flight `479cb68`)
- **Implementer:** MiniMax M3
- **Reviewer:** Claude (Opus 4.8), read-only, izolált `/tmp/review-e02r14` klón
- **ADR:** [0080](../adr/0080-practice-highway-rendering.md)
- **Verdikt:** **CHANGES REQUESTED** — 2 MAJOR + 3 MINOR + 1 NOTE
- **CI:** build-apk run [30676650652](https://github.com/wolfcasaba/strumsight/actions/runs/30676650652) (dispatch a `done` után, headSha `9488507` = HEAD)

## 1. Gate (reviewer, saját kézzel, izolált klón)

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart
→ format zöld · analyze zöld · test (mind külön) zöld · architecture zöld · GATE_EXIT=0
```

A zöld gate azonban **nem bizonyíték** — az alábbi két MAJOR minden teszt mellett
zöld maradt, mert a hozzájuk tartozó cellák nem a valódi szerződést mérik.

## 2. Scope-audit

`git diff --stat main...HEAD`: mind a 16 érintett fájl a brief §4 listáján belül;
`domain/`, `application/`, `data/`, `lib/features/learn/` **0 sor** (A10 ✓ a
diffstat szintjén). Az egyetlen listán-kívüli fájl a `practice_highway_import_guard_test.dart`
(A8 guard) — a brief A8 „saját tesztfájlt" ír elő, csak a nevét nem sorolta fel;
test-only, elfogadható (NOTE-szint, nem lelet).

## 3. Leletek

| # | Súly | Fájl:sor | Lelet |
|---|---|---|---|
| MAJOR-1 | MAJOR | `practice_chord_lane.dart:146-156` | A6: a `ChordOutcome` négy értéke nem kap négy KÜLÖNBÖZŐ megjelenítést |
| MAJOR-2 | MAJOR | `practice_highway.dart:259` | A3/D7: a beat/ütem-rács 120 BPM-re drótozva, a valós tempótól elcsúszik |
| MINOR-1 | MINOR | `practice_highway.dart:179` | A7: a brief-nevezte `PracticeTargetMarker` handle hiányzik (privát `_Marker`) |
| MINOR-2 | MINOR | `practice_chord_lane.dart:95-102` | A6: az „upcoming bar" a `_nextChord`-dal azonos értéket ad |
| MINOR-3 | MINOR | `strum_pattern_view_test.dart` / `chord_progression_view_test.dart` | A9: nincs balkezes cella és nincs layout/textScale overflow-őr; a `leftHanded` a highway-en holt paraméter |
| NOTE-1 | NOTE | `practice_highway_test.dart` A4 | A4 „parancs/verdict-lista/HUD score változatlan" fele nincs explicit állítva |

### MAJOR-1 — A6: nincs négy különböző `ChordOutcome`-megjelenítés (probe-igazolt)

A brief A6: *„A `chordOutcome` négy értéke **négy különböző** megjelenítést kap
(correct / wrong / insufficientData / notApplicable)…"*. A `_outcomeColor`
(`practice_chord_lane.dart:146-156`) viszont `insufficientData`, `notApplicable`
**és** `noDetection` értéket **azonos** `theme.colorScheme.outline` színre képezi
— így a négy közül **kettő pixelre azonos**, összesen csak három megkülönböztethető
megjelenítés van (green / red / outline). A `_Cell` semmilyen más jelet
(ikon, szöveg, tooltip) nem ad az outcome szerint.

Az A6 guard-teszt (`chord_progression_view_test.dart:222-273`) ezt **nem fogja
meg**: cellánként csak azt méri, hogy a `'C'` címke megjelenik (`findsWidgets`),
azt nem, hogy a négy megjelenítés **eltér**.

**Reviewer-próba** (eldobható, `zz_probe_a6_outcome_distinct_test.dart`, a klónban
futtatva, merge előtt törölve):

```
PROBE A6 insufficientData colors=[Color(… red:0.4745 green:0.4549 blue:0.4941 …)]
PROBE A6 notApplicable  colors=[Color(… red:0.4745 green:0.4549 blue:0.4941 …)]
Expected: not [ … ]  → A6 requires four DIFFERENT renderings; these two are identical
00:01 +0 -1: Some tests failed.
```

**Irány:** adj `insufficientData`-nak és `notApplicable`-nek eltérő, de **nem
hibás** (nem error-színű) jelet — pl. külön ikon/másodlagos jelölés, vagy külön
semleges szín —, és bővítsd az A6 tesztet úgy, hogy a négy megjelenítés
**páronkénti eltérését** mérje (ne csak a címke jelenlétét). A „latter two not as
error" feltétel maradjon.

### MAJOR-2 — A3/D7: a beat/ütem-rács 120 BPM-re drótozva

`_HighwayBackgroundPainter.paint` (`practice_highway.dart:259`):
`const secPerBeat = 0.5; // 120 BPM`. A **markerek** a valós `event.time`-ból
pozicionálódnak (helyes, bármely tempónál), a **háttér beat/ütemvonalai** viszont
egy 120 BPM-es feltevésből — miközben a beépített katalógus minden gyakorlata
60–90 BPM (a 3/4 keringő 90 BPM, `builtin_practice_catalog.dart:173`). Így a
downbeat/ütemvonalak minden valós gyakorlatnál elcsúsznak a tényleges hangoktól
(90 BPM-nél a 2. ütem downbeatje 2,0 s-nál van, a rács 1,5 s-ra rajzolja).

A festő ráadásul **figyelmen kívül hagyja a `target.barBoundaries`-t** — ami a
compiler által, tetszőleges tempóra/méterre kiszámolt, hiteles ütemhatár-idő.

Az A3 teszt (`practice_highway_test.dart` „3/4 and 4/4 meter support") ezt **nem
méri**: csak `tester.takeException(), isNull` (3/4 „builds cleanly") és a 6/8-nál
`meter.beatsPerBar == 6` (modell-ellenőrzés, nem renderelés). A brief A3 „az
ütemvonalak a `barIndex` váltásainál jelennek meg, és egy ütemre **három** ütés
esik" cellája így nincs valóban mérve.

**Irány:** a festő kapja meg a `target.tempo`-t és számoljon
`secPerBeat = 60 / tempo.bpm`-mel, **vagy** (jobb) rajzolja az ütemvonalakat a
`target.barBoundaries` időpontjaiból a `targetX`-en át. Egészítsd ki az A3
tesztet egy nem-120-BPM (pl. 90 BPM, 3/4) céllal, ami az ütemvonal x-pozícióját
a marker x-pozíciójához **egzaktan** köti (a downbeat a bar első eseményével
essen egybe).

### MINOR-1 — A7: hiányzó `PracticeTargetMarker` handle

A brief A7 mérőeszköze: `find.byType(PracticeTargetMarker)`. Az implementáció a
markert privát `_Marker`-ként adja (`practice_highway.dart:179`), és a skálázási
teszt a `lastExaminedRecordCount` számlálót méri. Mivel a felépített markerek
száma ≤ examined mindig, az `examined ≤ 64` **erősebb**, tehát az A7 szerződés
(korlátos felépítés) teljesül és nem gamelhető. De a brief-nevezte, típus szerinti
marker-számlálás nem lehetséges. **Irány:** nevezd a markert `PracticeTargetMarker`
publikus (vagy `@visibleForTesting`) widgetté, és add hozzá a „felépített
markerek ≤ 64" cellát is (`find.byType(PracticeTargetMarker)`), a brief A7
1. és 3. sora szerint.

### MINOR-2 — A6: „upcoming bar" == „next"

`_upcomingBar` (`practice_chord_lane.dart:95-102`) kiszámolja a `playheadBar`-t,
majd **eldobja**, és ugyanazt adja vissza, mint `_nextChord` (az első `start >
playhead` szegmens akkordja). A brief A6 szerint az „upcoming bar" a **következő
ütem** akkordja — ez több-akkordos ütemnél eltér a „next"-től. A beépített
progresszióknál (egy akkord/ütem) egybeesik, ezért ma nem látszik, de a
szerződés pontatlan. **Irány:** a `playheadBar`-ból a **következő** ütem
(`barBoundaries`) első expected-chord szegmensét vedd, ne az első jövőbeli
szegmenst; teszttel egy két-akkord-egy-ütem esetre.

### MINOR-3 — A9: balkezes cella és layout-őrök hiánya; holt `leftHanded`

- `leftHanded: true` egyetlen tesztben sem szerepel — az A9 „balkezes mód:
  tükrözött elrendezés, **változatlan** irány-jelentés (külön cella)" nincs mérve.
- Nincs 320×568 / 915×412 overflow-cella és nincs 200%-os textScale cella (A9).
- A highway `leftHanded` paramétere **holt**: a `_HighwayBackgroundPainter.paint`
  és a `_Marker.build` sehol nem alkalmazza (csak `shouldRepaint`-ben szerepel).
  A D8 a tükrözést *megengedi* (nem kötelezi), és nem-tükrözésnél az irány-jelentés
  triviálisan változatlan — ezért ez nem MAJOR, de a holt paraméter félrevezető
  és az A9-cella hiányzik. **Irány:** vagy alkalmazd a tükrözést és mérd a
  változatlan irány-jelentést, vagy vedd ki a holt paramétert; és add hozzá a
  layout/textScale overflow-cellákat (az R13 L22-tanulsága: UI-kör kötelező
  eleme).

### NOTE-1 — A4 invariancia-fél

Az A4 pure-függvény cellái (x-eltolódás visualOffset-tel) megvannak és egzaktak.
Az A4 másik fele („a parancsok száma, a verdict-lista és a HUD score változatlan")
nincs explicit állítva — de a highway/feedback widgetekben **nincs** pontozó vagy
parancs-kiadó út (a verdict/metrika bemenet), ezért a szivárgás strukturálisan
lehetetlen. Nem blokkol; egy invariancia-cella jó lenne a regresszió ellen.

## 4. Ami rendben van (bizonyítékkal)

- **A1** pure `targetX` mátrix egzakt egyenlőséggel (`time==playhead → strikeX`,
  matcher a `strikeX` double, **nem** `closeTo`) — `practice_highway_test.dart:93`.
- **A2** rest slot külön ikon (`Icons.remove`) + két azonos irányú marker külön
  (`downCount == 2`) — `practice_highway_test.dart:207,239`.
- **A5** perfect/early/late/wrong verdict-copy + `expectedDirection` a rossz
  iránynál + combo a `maxCombo`-ból (`find.text('3')`) — `strum_pattern_view_test.dart:189-233`.
- **A7** binary-search korlátos ablak, `lastExaminedRecordCount ≤ 64` 2000 eseményen,
  a lista végén és 100 lépésen kumulálva is — genuine mérés (a nem-virtualizált
  út ~2000-et vizsgálna). (A marker-handle hiánya MINOR-1.)
- **A8** import-guard: `features/learn/`, `LessonScorer`, `LessonEvent`, `Lesson(`,
  `domain/service/` = 0 az új fájlokban.
- **A10** motor-réteg 0 sor (diffstat).
- **i18n:** minden új kulcs en+hu párban, `l10n_parity_test` zöld.
- **Architektúra:** a `visualLatencyProvider` a `settings/public.dart` sankcionált
  barrelből jön (ADR 0057), a `ChordDiagram` a `chords/public.dart`-ból — megengedett
  kereszt-feature importok; a session-screen diff kizárólag a mód-nézet becsatolása.

## 5. Döntés

**CHANGES REQUESTED.** A két MAJOR (A6 négy-megjelenítés, A3 tempó-rács) merge-blokkoló.
Javító kör #1 ugyanazzal a motorral (MiniMax M3), a fenti leletlistával; a MINOR-okat
is kérjük a körben, ha nem hizlalják érdemben a diffet. A javítás után a review
frissül és a záró cellák mutációs próbával hitelesülnek.

## 6. Javító kör #1 verifikáció (HEAD `6e81c8e`, gate zöld `GATE_EXIT=0`, izolált klón)

Minden zárást friss `/tmp` klónban, mutációs próbával ellenőriztem.

| Lelet | Állapot | Bizonyíték |
|---|---|---|
| MAJOR-1 (A6 négy megjelenítés) | **ZÁRVA** | négy distinct `_OutcomeStyle` (szín+ikon+címke); `insufficientData`/`notApplicable` neutrális, eltérő ikon. **Mutáció:** `notApplicable` → `insufficientData` stílus ⇒ „four … pairwise distinct signals" teszt **PIROS** (`+2 -1`). |
| MINOR-1 (A7 marker-handle) | **ZÁRVA** | `PracticeTargetMarker` publikus widget; a skálázási teszt `find.byType(PracticeTargetMarker) ≤ 64` cellát is méri. |
| MINOR-2 (upcoming bar) | **ZÁRVA** | két-akkord-egy-ütem teszt: bar0 = C+G, bar1 = Am; `find.text('Am') findsOneWidget` (upcoming ≠ next=G). |
| MINOR-3 (A9) | **ZÁRVA** | 320×568 / 412×915 / 915×412 overflow + 200% textScale cellák; `leftHanded` `Transform`-mal alkalmazva. |
| **MAJOR-2 (A3 tempó-rács)** | **KÓD ZÁRVA, DE A TESZT TAUTOLÓGIA → ÚJRANYITVA** | lásd lent. |

### MAJOR-2 újranyitás — az A3 „bar line x" teszt tautológia

A **kód** helyes: a `_HighwayBackgroundPainter` a beat-rácsot `secPerBeat = 60/bpm`-mel
számolja, és az ütemvonalakat a `target.barBoundaries`-ból, a markerekével **azonos**
`xAt` transzformmal rajzolja (`practice_highway.dart:291,311-323`). **De a guardoló
teszt semmit nem mér a festőből:**

```dart
final firstEventX      = targetX(targetTime: Duration.zero, playhead: playhead, …);
final firstBarBoundaryX = targetX(targetTime: Duration.zero, playhead: playhead, …); // ← azonos hívás
expect(firstBarBoundaryX, firstEventX);              // targetX(0) == targetX(0) — tautológia
expect(secondBarBoundaryX - firstBarBoundaryX, 2*pps); // szintén tiszta targetX-matek
```

A teszt pumpolja a widgetet, de **soha nem olvassa ki a festett ütemvonalakat** — csak a
pure `targetX`-et hívja újra (amit az A1 már fed). **Mutációs bizonyíték:** a festő
`secPerBeat`-jét visszaírtam `0.5`-re, majd külön az ütemvonal-forrást 120 BPM-es
drift-re — **mindkét mutáció mellett a teszt ZÖLD maradt** (`All tests passed`). Tehát
egy jövőbeli painter-regresszió (a pontosan javított hibaosztály) **nem bukna el**.

A brief A3 gépi mércét kíván (a review-alapelv: minden tartalmi előírás mellé gépi
mérce). A tautologikus teszt = nincs mérce → **A3 érdemben méretlen**.

**Irány (javító kör #2):** mérd a festő tényleges kimenetét — vagy (a) emeld ki az
ütemvonal-x-eket tiszta függvénybe (`barLineXs(barBoundaries, playhead, visualOffset,
pps, strikeX)`) és teszteld közvetlenül, vagy (b) rögzítő/mock `Canvas`-szal fogd meg a
`drawLine` hívásokat és állítsd, hogy a 90 BPM 3/4 ütemvonal-x-ek a `barBoundaries`-ból
jönnek (a **második** ütemvonal 2 s-ra jobbra), és egy 120 BPM-es feltevés mellett a
teszt PIROS lenne. Egészítsd ki egy „egy ütemre három ütés" (beat-rács) állítással is,
hogy a `secPerBeat = 60/bpm` regressziója is bukjon.

**Döntés fix #1 után:** **CHANGES REQUESTED** marad — egyetlen blokkoló: a MAJOR-2 hiteles
teszt-lezárása. Javító kör #2 ugyanazzal a motorral (MiniMax M3).

## 7. Javító kör #2 verifikáció (HEAD `6f1c6ea`, gate zöld `GATE_EXIT=0`, izolált klón) → **APPROVED**

A festő ütemvonal-/beat-geometriája **pure függvényekbe** került (`barLineXs`,
`beatLineXs`, `practice_highway.dart:33,52`), és a festő ezeket hívja (uo. 336, 358) —
a viselkedés bitre változatlan, de most **közvetlenül mérhető**. Az új A3 cella
(„90 BPM 3/4 bar and beat lines use the painter geometry") a valós geometriát méri:

- `barLineXs([0 s, 2 s], …)` → két ütemvonal, `bars[1] − bars[0] == 2 * pps` (a 90 BPM
  3/4 ütem pontosan 2 s);
- `beatLineXs(Tempo(90), …)` → **pontosan két** belső beat-vonal a downbeatek között
  (a „egy ütemre három ütés" előírás), egyenként **160 px** (`= 60/90 · 240`) osztással.

**Mutációs verifikáció (reviewer, izolált klón):**

| Mutáció | Eredmény |
|---|---|
| `secPerBeat` → `0.5` (120 BPM feltevés a beat-rácsban) | A3 cella **PIROS** (`-1`) |
| `barLineXs` boundary-forrás 120 BPM-es driftre rontva | A3 cella **PIROS** (`-1`) |

Mindkét, korábban rejtett regresszió most bukik — a MAJOR-2 hitelesen **ZÁRVA**.

### Záró mérleg

| Lelet | Végállapot |
|---|---|
| MAJOR-1 (A6 négy megjelenítés) | ZÁRVA (mutáció-igazolt) |
| MAJOR-2 (A3 tempó-rács + hiteles teszt) | ZÁRVA (mutáció-igazolt, két regresszió) |
| MINOR-1 (A7 `PracticeTargetMarker`) | ZÁRVA |
| MINOR-2 (upcoming bar) | ZÁRVA |
| MINOR-3 (A9 balkezes + layout/textScale) | ZÁRVA |

Izolált gate (fix #2): `format · analyze · test (mind külön) · architecture` — mind
**zöld**, `GATE_EXIT=0`. Scope tiszta (a fix-diffek a §4 listán belül; motor-réteg 0 sor).

**Verdikt: APPROVED.** Merge a zöld kapu (ADR 0052) CI-igazolása után.
