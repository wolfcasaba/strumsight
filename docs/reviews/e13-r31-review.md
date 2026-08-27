# E13-R31 review — Progress Dashboard és Skill Detail UI

- **Kör:** `E13-R31` (Chapter 13, Kör 31 — UI-49/UI-50)
- **Brief:** [`docs/rounds/e13-r31-progress-and-skills.md`](../rounds/e13-r31-progress-and-skills.md)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor-ülés) — **read-only**, production kódot
  nem írtam
- **Review-alap:** `fbeddd13` (pre-flight) … `2903f248` (implementation handoff)
- **Izolált klón:** `/tmp/review-e13-r31` (a közös munkafában semmit nem futtattam)

## 1. Verdikt — **APPROVED** (a javító kör után; első forduló: CHANGES REQUESTED)

| Osztály | Db (1. forduló) | Állapot a javító kör után (`60acf24e`) |
|---|---|---|
| BLOCKER | 0 | — |
| **MAJOR** | **1** | **LEZÁRVA**, őrtesztet is kapott (§9) |
| MINOR | 3 | mind a 3 LEZÁRVA |
| NOTE | 2 | mind a 2 LEZÁRVA |

**A §9 szakasz tartalmazza a javító kör független újra-ellenőrzését** — az
alábbi §2–§6 az ELSŐ forduló (`2903f248`) jegyzőkönyve, változatlanul hagyva.

A kör tartalmilag erős: minden acceptance-cellának van gépi mércéje, a
valódi-sértés próba az L403 lecke szerint TARTALMI (feliratot mérő), és a
§0.0.B pre-flight kötései (B3 saját trend-küszöb, B4 route-mentesség, B5
DS-helyettesítők, B7 caller-fed) maradéktalanul teljesülnek. Egy MAJOR
viszont nyitva van: a felület **összeomlik** egy olyan bemeneten, amit a kör
SAJÁT domain-függvénye dokumentáltan és teszttel bizonyítottan előállít.

## 2. Gate — magam futtattam, izolált klónban

`tools/round-gate.sh` a brief §7 szerinti 10 célteszttel,
`/tmp/review-e13-r31`-ben, külön processzekkel:

```
[1] format ZÖLD · [2] analyze ZÖLD
[3] dashboard_states_test.dart        +8  ZÖLD
[4] mastery_evidence_test.dart        +9  ZÖLD
[5] metric_migration_test.dart        +5  ZÖLD
[6] chart_semantics_test.dart         +3  ZÖLD
[7] e13_r31_screens_golden_test.dart  +4  ZÖLD
[8] ui_inventory_test.dart            +1  ZÖLD
[9] architecture_dependency_test.dart +44 ZÖLD
[10] dio_factory_guard_test.dart      +1  ZÖLD
[11] preferences_plugin_import_guard  +2  ZÖLD
[12] route_literal_guard_test.dart    +1  ZÖLD
[13] architecture ZÖLD · [14] secrets ZÖLD · [15] l10n ZÖLD
═══ MINDEN GATE ZÖLD
```

**A zöld gate itt sem bizonyíték** — a lenti MAJOR-t egy eldobható
próbateszt mérte ki, nem a suite.

## 3. Scope-audit

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r31 \
    --brief docs/rounds/e13-r31-progress-and-skills.md --base fbeddd13b695…
Legacy scope audit OK (fbeddd13b695..2903f248f5fd, 23 changed path(s), 0 generated/ignored)
```

**`ok`** — mind a 23 commitolt útvonal a brief `allowed_paths` listáján van.

> **A wrapper `scope_audit=VIOLATION`-ja hamis pozitív volt, és ORCHESTRÁTOR-HIBA.**
> A jelzett egyetlen sértés (`.pipeline-prompt-e13-r31.md`) az **általam** a
> munkapéldány gyökerébe írt implementer-prompt volt — nem az implementer
> munkája, és soha nem is volt commitolva (`?? ` untracked). Az implementer
> saját jelzése `implementer_status=done` volt. A fájlt a repóból kivettem
> (`.pipeline/impl-prompt-E13-R31.md` a fő fában), és az auditot kézzel
> újrafuttattam — a fenti `ok` az eredmény. **Nem H3.** Lecke:
> az orchestrátor-prompt SOHA ne a munkapéldány fáján belülre kerüljön.

## 4. Biztonsági / adatvédelmi ellenőrzés (`risk = "high"`)

A kör diffje `lib/features/progress_v2/**` + l10n + tesztek. Mérve:

```
$ grep -rn "Dio|http|SharedPreferences|DateTime.now()|Random|FlutterSecureStorage|File(|Platform\." lib/features/progress_v2/
→ egyetlen találat, és az egy DOC-COMMENT (progress_overview_projection.dart:32),
  ami épp azt mondja ki, hogy ilyen olvasás NINCS
```

Cross-feature import kizárólag barrelen át (`gamification/public.dart`,
`core/design_system/public.dart`); az `app/routing/app_route.dart` csak
KONSTANST ad (a `route_literal_guard_test` zöld, `.go(`/`.push(` hívás nincs a
fán). **Új adat-út, hálózati hívás, tartós tárolás vagy engedélykérés nem
keletkezett** — a `risk=high` besorolás a megjelenített adat érzékenységéből
jött, és a caller-fed szerződés (B7) a legszűkebb lehetséges felületet adja.
**Biztonsági lelet: 0.**

## 5. Acceptance criteria — tételesen

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | Az elsajátítottság nem XP-ből származik | ✅ | `mastery_evidence_test.dart` 2 cella a RENDERELT százalékra; a `ratio` forrása `MasteryProgress.progressValue` (evidence-session arány). Valódi-sértés próba az implementer §10-jében: fix XP-arány → PONTOSAN az A1 két cellája pirosodott ki |
| A2 | Minden állítás mögött megnyitható bizonyíték | ✅ | `mastery_evidence_test.dart:138` — VALÓDI `tester.tap` az evidence soron, és a callback `AppRoutes.profileLibrarySession` + `sessionId` értékét méri. Nem dísz-hivatkozás |
| A3 | A hiányzó adat NEM nullaként jelenik meg | ✅ | `hasEvidence` kapu: `SsScoreRingState.unavailable` + látható „Not measured yet" felirat (nem csak `semanticLabel` — L403) |
| A4 | Elégtelen adatnál nincs trend, és ezt kimondja | ✅ | 3 cella (3 / 5 / 30 pont); a `progress-trend-insufficient` kulcs a kimondott szöveg |
| A5 | A mérőszám-verzió váltása látható | ⚠ **MAJOR** | a 2-szegmenses eset zöld, de a **visszatérő verzió** (v1→v2→v1) rendereléskor DOBÁL — lásd F1 |
| A6 | Az offline fejlődés látható | ✅ | `dashboard_states_test.dart:227,259` — `SsStatusBadgeKind.offline` jelenlét/hiány párban |
| A7 | Az ajánlás nem sérti az előfeltételeket | ✅ | `isRecommendationEligible` tiszta függvény + 2 widget-cella (locked szöveg vs. `SsCoachActionCard` akció) |
| A8 | Diagram-összegzés + lineáris alternatíva | ⚠ részben | a TREND-re teljes (`SsChartTextSummary` + `SsEventList`, 3 cella); a **képesség-gráf** lineáris alternatívája hiányos — lásd F4 |
| A9 | Golden: 412×915 + `textScaleFactor: 2.0`, commitolva | ✅ | 4 PNG a `test/ui/goldens/goldens/` alatt, `tools/golden-x86.sh record`+`check` zöld (ADR 0426 szerint x86-on, NEM `--update-goldens`). A felvétel egy VALÓDI hibát mért ki (137 px `RenderFlex` túlcsordulás scale2 mellett) — javítva (`1bad5c71`) |

## 6. Leletek

### F1 — **MAJOR** — a mérce-verzió előzmény ÖSSZEOMLIK, ha egy verziószám visszatér

**Hol:** `lib/features/progress_v2/screens/progress_dashboard_screen.dart:264`
(`_MetricHistorySection`, `key: ValueKey('progress-metric-segment-${segment.catalogVersion}')`)

**Mit mértem.** A kör saját domain-függvénye kimondottan támogatja és
teszttel bizonyítja a visszatérő verziót:

> `metric_migration_test.dart:66` — *„a version reappearing later starts a NEW
> segment, never re-merges"* → `[1, 2, 1]`, 3 szegmens

A képernyő viszont a szegmenseket a **`catalogVersion` értékével kulcsolja**
egy `Column` gyerekeiként. Két azonos verziójú szegmens tehát két azonos
kulcsú testvér — amit a Flutter hibának tekint. Eldobható próbateszt
(`test/features/progress_v2/zz_reviewer_probe_test.dart`, review után törölve)
PONTOSAN a domain-teszt bemenetével:

```
$ flutter test test/features/progress_v2/zz_reviewer_probe_test.dart
FlutterError: Duplicate keys found.
  If multiple keyed widgets exist as children of another widget, they must have unique keys.
  Column(direction: vertical, …, crossAxisAlignment: stretch) has multiple
  children with key [<'progress-metric-segment-1'>].
00:01 +0 -1: Some tests failed.
```

**Miért MAJOR és nem NOTE.** Ez nem elméleti él: a domain a nem-összeolvadást
SZÁNDÉKOSAN, az A5 indoklásával valósítja meg („a verzióváltás sosem olvad
vissza egy korábbi szakaszba"), tehát a `[1,2,1]` a szerződés szerinti,
elvárt bemenet — a felület mégis kivétellel dől el rajta. A kör legfontosabb
mérőszám-migrációs cellája (A5) így pont a nem-triviális esetben nem
teljesül. A meglévő widget-cella azért zöld, mert kizárólag `[1,2]`-t pumpál.

**Javasolt irány (nem kész patch):** a szegmens-kulcs legyen a
**pozícióval** egyedi (a listaindex, vagy index+verzió pár), és kerüljön egy
új cella a `metric_migration_test.dart`-ba, ami a `[1,2,1]` sorozatot
RENDERELI és mindhárom szegmenst megtalálja — ugyanaz a bemenet, ami ma a
pure-függvény cellájában már ott van.

### F2 — MINOR — a trend-pontok `semanticLabel`-je rossz mondatba tesz egy dátumot

**Hol:** `progress_dashboard_screen.dart:236-239`

A per-pont `semanticLabel` a `progressV2TrendExtremes` kulcsot használja
újra, aminek a szerződése (`lib/l10n/base/app_en.arb:407`):

```
"progressV2TrendExtremes": "First {first}, latest {last}"
```

A hívás viszont `('62%', '2026-08-01T00:00:00.000Z')` — a képernyőolvasó így
azt mondja: *„First 62%, latest 2026-08-01T00:00:00.000Z"*, ami egyetlen
mérési pontról értelmetlen, és nyers gépi időbélyeget olvas fel. Saját kulcs
kell (pl. „{value} on {date}").

### F3 — MINOR — nyers ISO-8601 időbélyeg a LÁTHATÓ felületen

**Hol:** `progress_dashboard_screen.dart:233` (trend-sor `label`),
`skill_detail_screen.dart:95,100` (evidence-sor `label`/`semanticLabel`)

Mindkettő `observedAt.toIso8601String()`-et jelenít meg a felhasználónak
(`2026-08-01T00:00:00.000Z`). Ez lokalizálatlan, gépi formátum; az SDD UI-50
„Evidence **date** és source felolvasott" előírását formailag teljesíti, de
olvashatatlanul. A projekt `intl`-lel dolgozik (`DateFormat`), a többi
felület lokalizált dátumot mutat.

### F4 — MINOR — az A8 „gráf → lineáris alternatíva" fele csak részben van meg

A brief §3 és az A8 a **képesség-gráf** lineáris, hozzáférhető alternatíváját
is kéri (SDD UI-50: „Skill graph lineáris prerequisite listként"). A
megvalósításban gráf nem készült — ez önmagában rendben van (nincs mit
linearizálni) —, de az előfeltétel-viszony a felületen **kizárólag a zárolt
ágon** látszik (`skill-detail-recommendation-locked` szöveg). Ha az ajánlás
jogosult, a felhasználó semmilyen előfeltétel-kontextust nem lát, holott a
modell (`SkillRecommendation.prerequisiteMilestoneId/Title`) hordozza.

Az implementer ezt maga is nyitott kérdésként jelezte a §10-ben — a review
megerősíti: nem hiba, de az A8 második fele alul van szállítva. Egy rövid,
mindig látható előfeltétel-sor (teljesítve/hiányzik jelöléssel) lezárná.

### F5 — NOTE — a `ProgressTrend` lokális változója `sorted`, de semmi nem rendez

`domain/progress_trend.dart:36` — `final sorted = List.unmodifiable(points);`.
A név rendezést sugall; a `_TrendSection` irány-számítása
(`points.first` vs `points.last`) ténylegesen **feltételezi** az idősorrendet,
de sem a konstruktor nem rendez, sem a doc-comment nem mondja ki előfeltételként
(a `segmentByCatalogVersion` ezzel szemben kimondja: „assumed already ordered").
Vagy a név javítandó + előfeltétel dokumentálandó, vagy rendezni kell.

### F6 — NOTE — a `const` osztályok belső listái módosíthatók

`MetricVersionSegment.points`, `SkillDetailProjection.evidence`,
`ProgressOverviewProjection.milestones/metricSegments` mind sima `List`.
A `segmentByCatalogVersion` a KÜLSŐ listát `List.unmodifiable`-lé teszi, a
belsőket nem. Immutable-nek szánt, caller-fed projekcióknál a
`List.unmodifiable` konzisztens alkalmazása lenne a minta (és a doc-comment
„Immutable, caller-fed projection" állítását is bizonyíthatóvá tenné).

## 7. Merge-döntés

**MERGE TILOS**, amíg az **F1 (MAJOR)** nyitva van. A javító kör a lánc normál
útja: ugyanaz a motor (`sonnet-impl`), ugyanezen az ágon, a fenti leletlistával.

A javító körben KÖTELEZŐ:

1. **F1** — a szegmens-kulcs egyedivé tétele + a `[1,2,1]` sorozatot
   RENDERELŐ új cella a `metric_migration_test.dart`-ban (a hibát pirosra
   fogó cella nélkül a javítás nincs lezárva).
2. **F2, F3, F4** — MINOR-ok; a diffet nem hizlalják érdemben, javítsd őket a
   javító körben.
3. **F5, F6** — NOTE, opcionális.

A javítás után a teljes gate ÚJRA fut, a CI-t a friss HEAD-re ÚJRA
dispatch-elem, és a review-t leletenként lezárom.

## 8. Ami kifejezetten JÓL sikerült (a jegyzőkönyv kedvéért)

- **A B3 kötés maradéktalan.** A `ProgressTrendThresholds.minimumDataPointsForTrend = 5`
  saját konstans, és a doc-comment KIMONDJA, miért nem a `TrendBuilder`
  `minimumSessionsForTrend = 3`-a. A falszifikációs „3 pont" cella él.
- **A valódi-sértés próba TARTALMI volt** (L403): fix XP-arány → a renderelt
  „60%"/„100%" felirat tűnt el, nem widget-típus változott.
- **A golden-felvétel valódi hibát fogott** (137 px túlcsordulás `textScaler`
  2.0 mellett) — pontosan azért van a mérce, hogy a képernyő ne csak
  „megváltozzon", hanem jó is legyen.

---

## 9. Javító kör (1.) — független újra-ellenőrzés

- **Javító commit:** `60acf24e` — „[E13-R31] javító kör: F1 MAJOR (mérce-verzió
  duplicate keys) + F2-F6 (a review leleteire)"
- **Motor:** ugyanaz (`sonnet-impl`), ugyanaz az ág. **Ez a kör ELSŐ javító
  köre** — az eszkalációs küszöb nincs kimerítve.
- **Friss izolált klón:** `/tmp/review-e13-r31b` (a javított HEAD-ről)
- **Implementer-jelzés:** `status=done`, `head=60acf24e`, `dirty_files=1` —
  **kivizsgálva:** a `git status --short` a commit után ÜRES; a számláló a
  jelzésfájl saját, commit utáni írását tükrözte, nem elveszett munkát.

### 9.1 Scope-audit (újra)

```
Legacy scope audit OK (fbeddd13b695..60acf24ef1de, 24 changed path(s), 1 generated/ignored)
```

Az `1 generated/ignored` a saját review-jelentésem (`docs/reviews/e13-r31-review.md`),
ami kód szintű, állandó mentesség — nem sértés.

### 9.2 Gate (újra, magam futtattam)

`tools/round-gate.sh` a 10 célteszttel, `/tmp/review-e13-r31b`-ben:
**15/15 ZÖLD.** A `metric_migration_test.dart` `+5` → **`+6`** — pontosan az
F1-hez kért új cellával.

### 9.3 F1 — a javítás VALÓDI-SÉRTÉS PRÓBÁVAL igazolva

Nem elég, hogy a cella zöld: azt mértem, hogy a RÉGI hibát tényleg pirosra
fogja. Az izolált klónban visszaállítottam a javítás előtti kulcsot
(`ValueKey('progress-metric-segment-${segment.catalogVersion}')`), majd:

```
$ flutter test test/features/progress_v2/metric_migration_test.dart
00:01 +3 -2: A5 … "a version reappearing later (v1, v2, v1) renders as THREE
             distinct segments, not a Duplicate keys crash" [E]
  Actual: FlutterError:<Duplicate keys found.
Some tests failed.
```

**Az új cella PIROSRA vált a régi kódon**, a pontos eredeti hibaüzenettel — a
lelet tehát nem „elfedve", hanem őrrel lezárva. A próbát visszaállítottam
(a klón tiszta).

A javítás maga: `progress_dashboard_screen.dart:282` — a kulcs
`'progress-metric-segment-$index-v${segment.catalogVersion}'`, azaz
**pozícióval egyedi**, a megjelenített szöveg és a szekció-logika változatlan.

### 9.4 A MINOR/NOTE leletek lezárása — tételesen

| Lelet | Állapot | Mért bizonyíték |
|---|---|---|
| **F2** — rossz mondat a trend-pont `semanticLabel`-jén | ✅ | saját l10n kulcs mindkét ARB forrásban, az aggregátum regenerálva; a `progressV2TrendExtremes` már csak a valódi szélsőértékekre megy |
| **F3** — nyers ISO-8601 dátum a látható feliraton | ✅ | `import 'package:intl/intl.dart' show DateFormat;` + `DateFormat.yMMMd(...)` MINDKÉT képernyőn. A megmaradt `toIso8601String()` (`progress_dashboard_screen.dart:243`) az `SsEventListRow.id` — **belső azonosító, nem látható felirat**, ott helyes |
| **F4** — az előfeltétel csak a zárolt ágon látszott | ✅ | `skill_detail_screen.dart:127` — `if (recommendation.prerequisiteMilestoneId != null)` ág a JOGOSULT esetben is renderel előfeltétel-sort (`skill-detail-recommendation-prerequisite` kulcs); a `mastery_evidence_test.dart` cellái ezt fedik |
| **F5** — a nem rendező `sorted` változó | ✅ | rendezve/dokumentálva a javító commitban |
| **F6** — módosítható belső listák | ✅ | a `const` projekciók listái konzisztensen `List.unmodifiable` |

### 9.5 A9 — golden újrafelvétel

Az F3/F4 megváltoztatta a renderelt szöveget, ezért a goldeneket újra fel
kellett venni. `tools/golden-x86.sh record` + `check` (ADR 0426, x86-on) —
a `[7] e13_r31_screens_golden_test.dart` cella a saját gate-futásomban
**zöld, nulla eltérés**.

### 9.6 Verdikt

**Minden lelet lezárva, 0 nyitott BLOCKER/MAJOR/MINOR.**

**VÉGSŐ DÖNTÉS: APPROVED.** A merge a zöld kapu (exact-SHA Full Gate +
Router CI a merge SHA-n) teljesülése után mehet.
