# E13-R27 review — Analysis Overview, Timeline, Metric és Compare UI

- **Kör:** `E13-R27` · **Brief:** [`docs/rounds/e13-r27-analysis-results-ui.md`](../rounds/e13-r27-analysis-results-ui.md)
- **Implementer motor:** Claude Sonnet 5 (`sonnet-impl`)
- **Reviewer:** Claude (orchestrátor-session), READ-ONLY
- **Ág / HEAD:** `sonnet-impl/e13-r27-analysis-results-ui` @ `39c674b4`
- **Pre-flight bázis:** `71b60bc5`
- **ADR:** [`0286`](../adr/0286-charts-need-a-text-alternative.md) — MÁR MERGE-ELT, a kör csak hivatkozza (§0.0/B/B0)
- **Dátum:** 2026-08-26

## VÉGSŐ DÖNTÉS: APPROVED (javító kör után, `fb0be5ba`)

- **1. kör (`39c674b4`): CHANGES REQUESTED** — 1 MAJOR, 2 MINOR, 2 NOTE.
- **Javító kör (`fb0be5ba`): mind a négy lelet ZÁRVA**, leletenként a SAJÁT
  mérésemmel igazolva (§7). A gate újra 16/16 zöld, a kilenc pin 57/57.

A javító kör a lánc normál útja (ADR 0087 §2), nem halt-ok.

---

## 1. Amit MAGAM mértem (nem bemondás)

### 1.1 Gate-újrafuttatás izolált klónban

`/tmp/review-e13-r27` (friss `git clone` a kör-ágról +
`tools/prepare-flutter-generated.sh`), majd a brief §7 gate-sora **egyben**:

```
[1] format ZÖLD · [2] analyze ZÖLD
[3] metric_missing_test.dart ZÖLD (6)
[4] timeline_virtualization_test.dart ZÖLD (5)
[5] chart_semantics_test.dart ZÖLD (6)
[6] compare_compatibility_test.dart ZÖLD (4)
[7] test/features/audio_analysis/presentation/ ZÖLD (57)  ← a kilenc PIN
[8] ui_inventory ZÖLD (1) · [9] architecture_dependency ZÖLD (44)
[10] hardcoded_string_guard ZÖLD · [11] dio_factory_guard ZÖLD
[12] preferences_plugin_import_guard ZÖLD · [13] route_literal_guard ZÖLD
[14] architecture ZÖLD · [15] secrets ZÖLD · [16] l10n ZÖLD
MINDEN GATE ZÖLD
```

A **[7] 57/57** a §0.0/B/B8 szerződés gépi igazolása: a migráció additív maradt,
a pinnelt típusok (`Card`, `InsightCard` 4/5 darabszám, az osztálynevek, a
meglévő l10n feliratok) nem cserélődtek.

### 1.2 Scope-audit (ADR 0138)

```
$ python3 tools/scope-audit.py --repo … --brief docs/rounds/e13-r27-… --base 71b60bc5
Legacy scope audit OK (71b60bc55233..39c674b4991b, 32 changed path(s), 0 generated/ignored)
```

Az első futás egyetlen leletet adott (`.pipeline-prompt-e13-r27.md`) — az az **én
saját, nem commitolt orchestrátor-artefaktumom** volt a munkapéldány gyökerében,
nem a kör diffjében (`git ls-tree 39c674b4 | grep pipeline-prompt` → üres).
Kivéve, újramérve: tiszta.

### 1.3 Valódi-sértés próba A1-re — REPRODUKÁLVA

Nem fogadtam el a §10.3 bemondását, magam futtattam. `overview_view_model.dart:286`:

```diff
-      CapabilityStatus.unavailable => labels.unavailableValuePlaceholder(),
+      CapabilityStatus.unavailable => '${metric.value ?? 0}',
```

```
00:01 +4 -2: Some tests failed.
  threshold matrix (§6.1) … below threshold (unavailable): never "0" …
  the presentation formatter never collapses a missing value into a numeric zero
    Expected: not '0'   Actual: '0'
```

**Az A1 cella VALÓDI** — a tiltott implementációt két oldalról (widget + formázó)
fogja pirosra. Visszaállítva.

### 1.4 Biztonsági felület (a brief `risk = "high"`)

A `lib/` diff **nulla** hálózati, tárolási, engedély-, hitelesítés- vagy
titok-felületet érint (`Dio|http|Uri\.|SharedPreferences|SecureStorage|
permission|File\(|Directory\(|token|apiKey` → egyetlen találat sem, csak a
`public.dart` export-sorok és egy doc-comment szó). A kör tisztán prezentációs:
a megjelenített adat a már perzisztált `AnalysisDocument`-ből jön, új adatút
nem keletkezett. **Biztonsági lelet: nincs.**

### 1.5 CI (exact-SHA, `39c674b4`)

- Router CI [`33023242237`](https://github.com/wolfcasaba/strumsight/actions/runs/33023242237) — **success**
- Full Gate [`33023245336`](https://github.com/wolfcasaba/strumsight/actions/runs/33023245336) — a review írásakor fut

A CI-tervező (`tools/round-ci-plan.py`) `full-gate.yml`-t írt elő
(`apk_required: false`, tisztán Dart/dokumentum-diff) — ezt dispatcheltem.

---

## 2. Leletek

| # | Súly | Tárgy |
|---|---|---|
| **F1** | **MAJOR** | `SsEventList` fix 220 px magassága kevés soron ~172 px halott helyet hagy — a commitolt goldeneken LÁTHATÓ |
| F2 | MINOR | az A4 falszifikációs cella nem diszkriminál: a mohó változaton is zöld marad |
| F3 | MINOR | `_hotspotEventList` hotspotonként KÉTSZER számolja ugyanazt a címke-sztringet, minden buildben |
| F4 | NOTE | `SsScoreRing` `(ratio ?? 0)` tartaléka a `measured` ágban — ma elérhetetlen, de pont a tiltott minta |
| F5 | NOTE | a §10.5-ben jelentett pin-teszt flake (`analysis_export_screen_test.dart`) |

### F1 — MAJOR — `ss_event_list.dart:33-34,55-57`: fix magasság kevés soron

**Mit mértem.** `SsEventList` magassága `height = 220` **konstans**, a sorok
száma pedig nem befolyásolja. A golden-fixture EGY hotspotot publikál
(`e13_r27_screens_golden_test.dart:141-147`), tehát:

```
220 px doboz − 1 sor × 48 px itemExtent = 172 px halott hely
```

Ez a 915 px magas compact portrait keret **~19%-a**, és mindkét commitolt
idővonal-goldenen szabad szemmel látszik: a leírás és a „következő/előző
hotspot" gombok között egy nagy üres blokk tátong
(`test/ui/goldens/goldens/e13_r27_analysis_timeline_compact.png`,
`…_compact_scale2.png`). A `textScaler: 2.0` kereten ugyanez.

**Miért MAJOR.** A brief §7 kifejezetten ehhez a körhöz rendeli a vizuális
ítéletet: *„a záró vizuális regressziós kör csak azt tudja megmondani, hogy
valami MEGVÁLTOZOTT — azt, hogy a képernyő eleve csúnya-e, a saját körében
kell látni."* A tipikus felvételen néhány hotspot van, tehát ez a **gyakori
eset**, nem élhelyzet, és renderelési hibának néz ki, nem légies tervezésnek.
Az A9 cella ezt szerkezetileg nem foghatja meg (a golden rögzít, nem ítél) —
ezért kerül ide.

**Javasolt irány (NEM kész patch).** A doboz magasságát a tartalomhoz kösd
felső korláttal, pl. `min(height, rows.length * rowExtent)`. A virtualizáció
ettől **érintetlen**: a `ListView.builder` + `itemExtent` marad, csak a
`SizedBox` nem foglal többet, mint amennyi sor van. A `shrinkWrap: true`
továbbra is TILOS (a `ss_event_list.dart` doc-commentje helyesen indokolja,
miért) — a számított magasság nem az.

### F2 — MINOR — `timeline_virtualization_test.dart:130-176`: a cella nem diszkriminál

**Mit mértem (eldobható próba, lefuttatva, visszaállítva).** A
`SsEventList.build`-ban a `ListView.builder`-t a MOHÓ alakra cseréltem —
mind a 3000 sor-widget előre felépül:

```diff
-        child: ListView.builder(
-          key: scrollableKey, itemExtent: rowExtent, itemCount: rows.length,
-          itemBuilder: (context, index) { final row = rows[index]; return Semantics(
+        child: ListView(
+          key: scrollableKey,
+          children: <Widget>[ for (final row in rows) Semantics(
```

```
$ flutter test test/features/analyze/results/timeline_virtualization_test.dart
00:07 +5: All tests passed!
```

**A cella ZÖLD maradt a tiltott alakon.** Ok: a `find.byWidgetPredicate` az
ELEM-fán mér, a `ListView(children:)` pedig `SliverChildListDelegate`-tel
szintén csak a viewportban lévő gyerekeket *mountolja* — a különbség a
widget-objektumok mohó allokációja, amit ez az állítás nem lát. A brief §6.1
viszont kimondja: *„Az egész idővonal egyszerre renderelve → **A4**"*, a
§0.0/B/B7 pedig cellát kért, ami a tiltott implementáción PIROS ([L443](../LESSONS.md#l443)).

**Miért csak MINOR.** A cella a *használhatatlanná tévő* alakokat FOGJA:
`shrinkWrap: true` vagy `Column` esetén mind a 3000 sor mountolódik, a
`builtCount < 30` azonnal piros. A rés a mohó allokáció, aminek mért ára
mérsékelt (lásd F3). A mérce tehát gyengébb az előírtnál, de a
követelmény lényegét őrzi.

**Javasolt irány.** Egy cella, ami a delegátum-típusra zár —
`find.byWidgetPredicate((w) => w is ListView && w.childrenDelegate is SliverChildBuilderDelegate)` —
vagy egy sor-gyártó számláló, ami a KONSTRUÁLT (nem mountolt) sorokat számolja.

### F3 — MINOR — `analysis_timeline_screen.dart:185-196`: kétszeres címke-számítás

`_hotspotEventList` minden hotspotra KÉTSZER hívja a `_hotspotSemanticsLabel`-t
azonos argumentumokkal — egyszer `label:`-nek, egyszer `semanticLabel:`-nek —,
és ez a lista mohón épül fel a `sections` tömbbe, minden `build`-ben (tehát
minden pan/zoom `setState` után is).

Mért nagyságrend (reviewer-próba, 3000 soros lista teljes pumpálása a
teszt-hostban): mohó változat **580 ms**, a szállított builder-változat
**501 ms** — a különbség ~14%, mert a `ListView(children:)` is lustán mountol;
a kétszeres sztring-formázás viszont mindkettőben benne van.

**Javasolt irány.** Egy `final label = _hotspotSemanticsLabel(…)` hívás,
mindkét mezőnek átadva. Ha a két mezőnek tényleg különböznie kellene (a
`SsEventListRow` doc-commentje ezt engedi), akkor a `label` legyen a rövid
látható szöveg, a `semanticLabel` a bővebb — ma **azonosak**, tehát a
megkülönböztetés ma nem hordoz információt.

### F4 — NOTE — `ss_score_ring.dart:45`: `(ratio ?? 0)` a `measured` ágban

```dart
final fraction = state == SsScoreRingState.measured
    ? (ratio ?? 0).clamp(0.0, 1.0)
    : 0.0;
```

Az EGYETLEN mai hívó (`signal_quality_card.dart:73`) `card.overallRatio`-t ad
át, ami **nem nullable** `double` (`overview_view_model.dart:155`), tehát az ág
ma elérhetetlen — nem sértés. De az ADR 0286 §1 pont ezt a mintát tiltja, és a
komponens publikus, tehát egy jövőbeli hívó `measured` + `ratio: null`
kombinációval csendben 0-t festene. Egy
`assert(state != SsScoreRingState.measured || ratio != null)` ezt szerkezetileg
kizárja. **Nem blokkol.**

### F5 — NOTE — a §10.5-ben jelentett pin-flake

Az implementer becsületesen jelentette, hogy az `analysis_export_screen_test.dart`
„preview gate" cellája EGYSZER pirosra váltott a könyvtár együttes futtatásakor,
majd ismételten zöld lett. A fájl a **tilos zónában** van, a kör nem nyúlt hozzá
(a scope-audit igazolja). A saját mérésem (`[7] 57/57 ZÖLD`) és a Router CI is
zöld. **Ha a Full Gate emiatt pirosra vált, az meglévő kereszt-teszt
state-szivárgás, nem e kör defektje** — a merge-kapu viszont akkor sem lazul.

---

## 3. Acceptance criteria tételesen

| # | Verdikt | Bizonyíték, amit MAGAM láttam |
|---|---|---|
| A1 | ✅ | 1.3 próba: a `?? 0` KÉT cellát pirosra vált; visszaállítva 6/6 zöld |
| A2 | ✅ | `metric_missing_test.dart` „below threshold (notApplicable)" — külön állapot, `find.text('0'), findsNothing` |
| A3 | ✅ | ugyanott „A3 — confidence is visible for every card" + `findsAtLeastNWidgets(2)` a három szinten |
| A4 | ⚠️ **teljesül, de a mércéje gyenge (F2)** | az implementáció valóban `ListView.builder` + `itemExtent` (`ss_event_list.dart:57-60`), 3000 hotspoton < 30 épített sor; a cella viszont a mohó alakon is zöld |
| A5 | ✅ | `chart_semantics_test.dart` — MIND a 6 cella `pumpWidget`-el, valódi szöveget mér (korai/kései/egyenletes trend, HU fordítás, esemény-lista sor) |
| A6 | ✅ | `compare_compatibility_test.dart` a VALÓDI `CompatibilityEvaluator.compare`-t hívja, majd a verdiktet pumpálja a képernyőbe |
| A7 | ✅ | ugyanott: `find.text('Inconclusive')` + a pontos ok-mondat, ÉS `find.textContaining('40.00'), findsNothing` — az inkompatibilis értékek NEM jelennek meg |
| A8 | ✅ | `timeline_virtualization_test.dart` — pontos tartomány tap-ből, `start <= end` normalizálás hátrafelé húzásnál, és a gomb hiánya handler nélkül |
| A9 | ⚠️ **formálisan teljesül, tartalmilag F1** | 8 PNG commitolva, a golden-teszt VALÓDI kapu (nincs `skip`, `matchesGoldenFile` a 65. sorban); a felvétel viszont egy layout-defektet rögzít |

---

## 4. Architektúra és termékhatárok (AGENTS.md §5–§6)

- `design_system → feature` import: **nincs** — az `SsConfidenceLegend` saját
  `SsConfidenceLevel` enumot hoz, nem importálja a feature `ConfidenceBadgeLevel`-jét. ✅
- `test/core/architecture_dependency_test.dart` 44/44 zöld — a
  `foundations/**` közvetlen importja (az E13-R16/F8 hibaosztály) nem tért vissza. ✅
- `route_literal_guard` zöld — a kör route-literált nem vezetett be (§0.0/B/B3). ✅
- `ui_inventory` `hasLength(89)` **változatlan** — a kör nem hozott új
  `*_screen.dart`-ot, pontosan ahogy a §0.0/B/B4 előre mérte. ✅
- Az új DS-komponensek mind be vannak kötve productionbe (`SsScoreRing`,
  `SsTrendIndicator`, `SsConfidenceLegend`, `SsChartTextSummary`, `SsEventList`
  — mindegyikre van `lib/`-beli hívó). Nincs halott komponens. ✅
- Az ambiens `Theme.of(context)` olvasása a theme-extension helyett: a §10.1
  indoklása (a pinnelt tesztek csupasz `MaterialApp`-ot pumpálnak) **mért és
  helytálló** — a fordítottja a kilenc pint döntené be. ✅

## 5. Próbatesztek — mind eldobva

| Próba | Fájl | Sors |
|---|---|---|
| A1 `?? 0` injektálás | `overview_view_model.dart` | visszaállítva (`/tmp/ovm.bak`) |
| A4 mohó `ListView(children:)` | `ss_event_list.dart` | visszaállítva (`/tmp/sel.bak`) |
| 3000 soros pumpálás időzítés | `probe_timing_test.dart` | törölve |
| pan/görgetés keret-költség | `probe_frame_test.dart` + support | törölve |

`git status --short` a review-klónban a próbák után: **tiszta**.

## 6. A javító körnek átadott leletlista

1. **F1 (MAJOR, kötelező):** `SsEventList` magassága kövesse a tartalmat felső
   korláttal — a `ListView.builder` + `itemExtent` MARADJON, `shrinkWrap`
   továbbra is tilos. A golden-eket újra kell venni
   (`tools/golden-x86.sh record`), és a PNG-ket commitolni.
2. **F2 (MINOR):** az A4 cella zárjon a builder-delegátumra vagy a KONSTRUÁLT
   sorok számára, hogy a mohó alak pirosra váltson.
3. **F3 (MINOR):** egyetlen `_hotspotSemanticsLabel` hívás soronként.
4. **F4 (NOTE, opcionális):** `assert` az `SsScoreRing` `measured` ágára.

F5-höz nincs teendő (tilos zóna, nem a kör defektje).

---

## 7. Javító kör ellenőrzése — `fb0be5ba` (2026-08-26)

Friss klón (`/tmp/review-e13-r27b`), a gate ÚJRA magam futtatva:
**16/16 ZÖLD**, a kilenc pin `[7] 57/57` — a §0.0/B/B8 additív szerződés a
javítás után is áll. Scope-audit: `OK (71b60bc5..fb0be5ba, 33 changed path(s),
1 generated/ignored)` — az egy ignorált útvonal a saját review-jelentésem.
A `main` a dispatch óta nem mozdult (`37c8f1a9`).

| Lelet | Zárás | Ahogyan MAGAM igazoltam |
|---|---|---|
| **F1** MAJOR | ✅ | `ss_event_list.dart:59` — `final boundedHeight = math.min(height, rows.length * rowExtent)`. A `ListView.builder` és az `itemExtent` MEGMARADT, `shrinkWrap` nem került be. Az ÚJRAVETT goldenen (`e13_r27_analysis_timeline_compact.png`) a ~172 px halott blokk eltűnt: az esemény-sor közvetlenül a hotspot-navigációs gombokba folyik, és az idővonal-sáv kártyája is beleférve látszik. Mindkét keret (1.0 és 2.0 textScale) újravéve, commitolva. |
| **F2** MINOR | ✅ | ÚJ cella `timeline_virtualization_test.dart:169-186`: a delegátum-típusra zár. **Újra lefuttattam a próbámat** — ugyanaz a mohó `ListView(children: […])` csere, ami az 1. körben 5/5 zölden ment át, most PIROS: `Expected: <Instance of 'SliverChildBuilderDelegate'> / Actual: SliverChildListDelegate:<…(estimated child count: 3000)>`. A cella immár diszkriminál. Visszaállítva. |
| **F3** MINOR | ✅ | ÚJ `_hotspotEventListRow` segéd: `final label = _hotspotSemanticsLabel(…)` **egyszer**, `label`-nek és `semanticLabel`-nek is átadva. |
| **F4** NOTE | ✅ | `ss_score_ring.dart:42-45` — `assert(state != SsScoreRingState.measured \|\| ratio != null)`. |
| **F5** NOTE | — | nincs teendő; a `[7] 57/57` ebben a futásban is zöld volt. |

**A javító kör diffje** (`dbb140d5..fb0be5ba`): 7 fájl, +183/−23 — kizárólag a
négy lelet és a két újravett PNG, plusz a brief §10.7 dokumentációja.
Scope-tágítás nincs, a mérce sehol nem gyengült (F2 kifejezetten ERŐSÍTI).

**Merge-feltétel, ami még hátravan:** az exact-SHA CI zöldje a `fb0be5ba`-n
(Full Gate + Router CI). A review ettől függetlenül APPROVED.
