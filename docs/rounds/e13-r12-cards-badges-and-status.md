# E13-R12 — Kártyák, badge-ek, insight és status komponensek

- **Státusz:** READY (pre-flight MÉRVE 2026-08-24, `main @ 69679bb5`; a
  PREPARED szöveg 2026-08-15-i, `main @ 93a6c19a` — a §0.0 hét eltérést javít)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 12
- **Kör-azonosító:** `E13-R12`
- **Branch:** `sonnet-impl/e13-r12-cards-badges-and-status`
- **Előfeltétel:** `E13-R11` merge-elve (action/input készlet) — ✅ `d55d1656`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0278`](../adr/0278-ai-provenance-is-visible.md)
  — **MÁR MERGE-ELVE** (`a4fdfec2`), tehát ez a kör ADR-t **NEM ír**, és a
  `docs/adr/` a TILOS zónában marad. Lásd §0.0/D1.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd fel, milyen TÉNYLEGES
> AI-mód és sync-állapot típusok léteznek ma (a coach/analysis rétegben), mert
> a §5.1 provenance-badge ezekre képez. Eltérésnél §0.0 revízió.
> **ELVÉGEZVE — §0.0/D4: ilyen típus MA NEM LÉTEZIK**, a badge saját
> prezentációs enumot definiál.

> 📌 **Az implementer ELŐSZÖR a §0.0-t olvassa el**, és azt a §5-tel azonos
> kötelező erejűnek tekinti. Hét mért eltérés: **D1–D7**.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/components/cards/ss_metric_card.dart",
  "lib/core/design_system/components/cards/ss_insight_card.dart",
  "lib/core/design_system/components/cards/ss_coach_action_card.dart",
  "lib/core/design_system/components/cards/ss_content_card.dart",
  "lib/core/design_system/components/ai/ss_model_status_card.dart",
  "lib/core/design_system/components/ai/ss_provenance_badge.dart",
  "lib/core/design_system/components/feedback/ss_status_badge.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/features/design_system_en.arb",
  "lib/l10n/features/design_system_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/cards/ss_cards_test.dart",
  "test/core/design_system/cards/ss_badges_test.dart",
  "docs/rounds/e13-r12-cards-badges-and-status.md",
]
gate_tests = [
  "test/core/design_system/cards/ss_cards_test.dart",
  "test/core/design_system/cards/ss_badges_test.dart",
  "test/core/design_system/component_catalog_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör egyetlen `high_risk_path_fragment`
útvonalat sem érint (nincs `auth`/`crypto`/`upload`/… a listán) — a besorolás
**tartalmi**: az ADR 0278 §1 szerint a provenance-badge **adatvédelmi tényt**
közöl (elhagyta-e az adat a készüléket), és egy elrejtett vagy téves
`local`/`cloud` jelölés a felhasználót a saját adatai útjáról téveszti meg.
A `risk = "high"` ezért marad, és a review-ba a `security-reviewer` subagent
kötelezően bevonandó (adatvédelmi láthatóság, nem hálózati felület).

## 0.0 Pre-flight revízió — MÉRVE 2026-08-24, `main @ 69679bb5`

A brief PREPARED szövege 2026-08-15-i. A kód azóta elmozdult; az alábbi hét
pont **kötelező**, és a §3–§8 megfelelő sorait felülírja.

### D1 — Az ADR 0278 MÁR MERGE-ELVE; ez a kör ADR-t NEM ír

```
$ git log --oneline -1 -- docs/adr/0278-ai-provenance-is-visible.md
a4fdfec2 docs(ch13): E13-R07..R13 briefek + ADR 0275-0279
$ git cat-file -e origin/main:docs/adr/0278-ai-provenance-is-visible.md && echo PRESENT
PRESENT
```

A fejléc „a Claude írja meg a kör indításakor" mondata ezért tárgytalan: egy
merge-elt ADR átírása **H1** (ADR 0087 §2). Ugyanaz a minta, mint
`E13-R08`/`R09`/`R10`/`R11` — a Ch13 ADR-jei előre merge-elve érkeztek. A
foglalótól kapott `0419` szám **felhasználatlan** marad. A `docs/adr/**` végig
TILOS zóna.

### D2 — Az ARB-aggregátum GENERÁLT; a kézzel írt forrás a fragmentum (ADR 0307 §4)

A PREPARED lista KIZÁRÓLAG a `lib/l10n/app_{en,hu}.arb`-t engedte, ami
2026-08-20 óta **generált uniós aggregátum**
(`tool/gen_l10n_segments.dart`, ADR 0307 §4). Aggregátumba írt kulcsra a
`--check` PIROS, a `--write` pedig eldobja őket — ez a hibaosztály **ötször**
mérve ([L365](../LESSONS.md), [L369](../LESSONS.md), [L396](../LESSONS.md),
[L454](../LESSONS.md), E13-R11/D2).

Ez **nem lista-tágítás, hanem forrás-átirányítás**: a kézzel szerkesztendő
fájl a fragmentum, a már engedélyezett aggregátum pedig annak **generált
kimenete**, amit a fán követünk. Mindkettő a listán van (E13-R10/R11 mintája).

- **Kézzel:** `lib/l10n/features/design_system_{en,hu}.arb` (LÉTEZIK, ma 23
  kulcs, `ds…` prefix).
- **Generálva, a gate ELŐTT kötelezően:**
  `dart run tool/gen_l10n_segments.dart --write`, majd a módosult
  `lib/l10n/app_{en,hu}.arb` **is** commitolandó.
- A kulcsprefix maradjon `ds…` (a meglévő 23 kulcs konvenciója).

### D3 — A `component_catalog_test.dart` EXACT-COUNT csapdája, és ez nem szerkeszthető fájl

A `test/core/design_system/component_catalog_test.dart` (NINCS az
`allowed_paths`-on, tehát **fagyott őr**) három darabszám-állítást tesz az
EGÉSZ fára:

```dart
expect(find.byType(SsCard), findsOneWidget);
expect(find.descendant(of: find.byType(SsCard), matching: find.byType(Material)), findsOneWidget);
expect(find.byType(DecoratedBox), findsOneWidget);
```

Mért következmények (`ss_surface.dart`, `ss_card.dart`, `ss_skeleton.dart`):

| Tény | Kötelező következmény |
|---|---|
| `SsSurface` `Material`-t rendel ki, **nem** `DecoratedBox`-ot | az új kártyák **`SsSurface`-re** épülnek, ahogy a meglévő `SsHeroCard` — **nem** `SsCard`-ra |
| a katalógusban ma PONTOSAN 1 `SsCard` van | a katalógus-mátrix **nem adhat hozzá újabb `SsCard`-ot** |
| a fában ma PONTOSAN 1 `DecoratedBox` van (a `Scaffold` háttere) | az új komponensek **nem használnak `DecoratedBox`-ot**, és a katalógusba **skeleton-demó nem kerül** (`SsSkeleton` `DecoratedBox`-ot rendel ki — az E13-R10 pontosan ezen mért) |

Ezért a fájl **negyedik gate-útvonalként** (§7) felvéve — enélkül a katalógus
törése csak a CI teljes suite-jában bukna ki, a kör saját kapuja után.

### D4 — A provenance-badge-nek NINCS mire képeznie: ilyen típus ma nem létezik

A fejléc ⚠ pre-flightja ezt kérte. Mérés:

```
$ grep -rn "enum .*\(AiMode\|AiProvider\|ModelSource\|InferenceLocation\|ModelLocation\)" lib/ --include=*.dart
(nincs találat)
```

Ami LÉTEZIK (mind `lib/core/design_system/foundations/ss_colors.dart`, ami
**NINCS** az `allowed_paths`-on → csak OLVASHATÓ):

- `enum SsStatusMarkerKind { confidence, offline, localAi, cloudAi }` +
  `SsStatusMarkers.forKind(...)` ikonokkal (`help_outline`, `cloud_off_outlined`,
  `memory_outlined`, `cloud_outlined`) — `ss_colors.dart:6-26`;
- szín-tokenek az `SsColorScheme`-en: `confidenceHigh/Medium/Low`, `offline`,
  `localAi`, `cloudAi`, **`syncPending`** — `ss_colors.dart:107-113`.

Az `ai_tutor` „provenance" enumjai **tartalom**-eredetről szólnak, nem
modell-helyről (`DebriefFactProvenance { measuredFact, computedTrend }`,
`StudentProfileFieldProvenance`, `PracticePlanSource`, `TutorActionSource`),
a `TutorToolPermission { readLocal, computeLocal }` pedig eszköz-jogosultság.

**Kötelező következmény:** a badge-ek SAJÁT, prezentációs enumot definiálnak a
saját fájljukban (ADR 0278 §5 — a komponens prezentációs réteg), és a
szín/ikon értéket a MEGLÉVŐ tokenekből olvassák. **Új színtokent felvenni
tilos** (`ss_colors.dart` a tilos zónában, ADR 0273 egy-token-forrás). A
`syncPending`-hez nincs `SsStatusMarkerKind` — annak ikonját a badge-fájl
adja meg, de a SZÍNT a `syncPending` tokenből veszi.

### D5 — A metrika-tipográfia MÁR token; a `SsMetricCard` olvassa, nem definiálja

```
$ grep -n "metricLarge\|tabularFigures\|montserratFamily" lib/core/design_system/foundations/ss_typography.dart
16:    required this.metricLarge,      76:      metricLarge = const TextStyle(
81:        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
99:  static const montserratFamily = 'Montserrat';
```

A §8/2. pont „Montserrat, tabular figures" előírását tehát a
`Theme.of(context).extension<SsTypography>()!.metric{Large,Medium,Small}`
OLVASÁSA teljesíti. `fontFamily`/`FontFeature` **hardkódolása tilos**
(ADR 0273). A `SsTypography.metricLabel(value, unit)` a nem-törő szóközös
érték+egység összefűzés kész helye.

### D6 — Az A7 gépi őre néven nevezve

`tool/check_architecture.dart:332-334`, `ArchitectureRule.coreMustNotImportFeatures`:
`lib/core/**` → `lib/features/**` import = violation. A `tools/round-gate.sh`
`architecture` lépése futtatja. Az A7-hez tehát **nem kell új teszt**, de a
komponensek `lib/features/**`-ból SEMMIT nem importálhatnak (a katalógus
`lib/core/foundation/app_failure.dart`-ja core, az rendben van).

### D7 — A katalógus dev-only és ANGOL (E13-R10/R11 D7 folytatása)

A katalógus-showcase-ek `lookupAppLocalizations(const Locale('en'))`-t
hívnak, mert nincs `Localizations` ősük; a katalógus fejlesztői felület,
nincs saját lokalizált terméktartalma. Az ÚJ komponensek felhasználónak szóló
stringjei viszont **mind** ARB-n mennek át (A8) — a katalógus csak fixture-
szöveget ad át nekik paraméterként.

### Visszakeresett előzmény (ADR 0312 / brief-lint S8)

| Forrás | Mit mond ennek a körnek |
|---|---|
| [`adr/0278`](../adr/0278-ai-provenance-is-visible.md) | a kör öt kötött döntése — **merge-elve**, §5 ezt tükrözi (D1) |
| [`adr/0277`](../adr/0277-failure-presentation-model.md) §6 | a skeleton kimarad a semantics fából — az A5 gyökere |
| [`adr/0273`](../adr/0273-design-system-token-source-of-truth.md) | egy token-forrás: az új komponens OLVAS, nem másol (D4, D5) |
| [`adr/0307`](../adr/0307-pipeline-throughput-program-v2.md) §4 (E99-R17 lever) | az ARB-aggregátum generált, a forrás a fragmentum (D2) |
| [`L460`](../LESSONS.md) | egy „jelenlét-alapú" őr VAK lehet: a `find.text()` a láthatatlan maradékot is megtalálja → az A1/A2 cellák **tulajdonság-szinten** mérjenek, ne puszta jelenléttel |
| [`L457`](../LESSONS.md) | a zöld cella a prezentációs MODELLT mérheti, miközben a user a WIDGET-et látja → az A3/A4 a **kirendelt** `InkWell`/`onTap`-et mérje, ne egy predikátumot |
| [`L403`](../LESSONS.md) | a valódi-sértés próba widget-TÍPUS szinten átengedhet tartalmi sértést → a próbák a §6.1 mátrix szerinti KONKRÉT sértést állítsák elő |

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Újrahasznosítható információs komponensek a hubokhoz, eredményekhez, az AI-,
sync- és confidence-felületekhez (SDD Ch13 Kör 12).

## 2. Jelenlegi állapot — mért tények

- Az R03 kimondta: az állapot **nem csak színnel** jelölt, és az alacsony
  confidence nem `danger`.
- Az R05 adja a felület-hierarchiát, az R07 az ikonokat, az R10 a skeletont.
- Az R10 skeleton-szabálya érvényes itt is: a skeleton geometriát tart, és nem
  olvasható tartalomként.

## 3. Scope

**Benne van:** `SsMetricCard`, `SsInsightCard`, `SsCoachActionCard`,
`SsModelStatusCard` és általános tartalmi kártya · offline, sync pending,
local AI, cloud AI, on-device, adatvédelmi láthatóság és confidence badge-ek
**ikon + szöveg** formában · kártya-akció hierarchia és beágyazott érintési cél
szabályai · compact és expanded sűrűség · a kártyákhoz illő skeletonok ·
Component Catalog állapot-mátrix.

**NINCS benne (tilos):** `lib/features/**` átállítása · AI-hívás vagy
üzleti logika a komponensben · a confidence **küszöbeinek** meghatározása
(az a felismerési rétegé) · `lib/core/theme/**` · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `cards/ss_metric_card.dart` | **ÚJ** — mérőszám (Montserrat, tabular) |
| `cards/ss_insight_card.dart` | **ÚJ** |
| `cards/ss_coach_action_card.dart` | **ÚJ** |
| `cards/ss_content_card.dart` | **ÚJ** — általános |
| `ai/ss_model_status_card.dart` | **ÚJ** — modell-állapot |
| `ai/ss_provenance_badge.dart` | **ÚJ** — helyi / felhő / on-device |
| `feedback/ss_status_badge.dart` | **ÚJ** — offline, sync, confidence |
| `documentation/component_catalog_screen.dart` | állapot-mátrix — **a §0.0/D3 három megkötésével** |
| `public.dart` | az export bővítése |
| `lib/l10n/features/design_system_{en,hu}.arb` | **a kézzel írt ARB-forrás** (§0.0/D2) |
| `lib/l10n/app_{en,hu}.arb` | a `--write` GENERÁLT kimenete, commitolandó (§0.0/D2) |
| `test/…/cards/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r12-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0278 — MÁR MERGE-ELVE, §0.0/D1)

### 5.1 Az AI-eredet LÁTHATÓ, és nem csak szín

Minden AI-eredetű tartalom megmutatja, **helyi vagy felhő** modell adta-e. Ez
adatvédelmi kérdés: a felhasználónak joga tudni, elhagyta-e adat a készüléket.

**NEM elfogadható gyengítés:** a provenance elrejtése egy részletnézetbe „hogy
tisztább legyen a kártya". A felhő-hívás ténye nem részletkérdés.

### 5.2 A badge jelentése NEM csak szín

Ikon vagy szöveg mindig kíséri (az R03 §5.3 folytatása). Színvakság mellett is
egyértelmű.

### 5.3 A kártya EGÉSZE csak akkor kattintható, ha EGY fő akciója van

Több akció esetén a kártya-háttér nem nyel el koppintást — különben a
felhasználó nem tudja, mi fog történni.

**NEM elfogadható gyengítés:** a kártya `InkWell`-be csomagolása több gomb
mellett. A beágyazott érintési célok kiszámíthatatlanná válnak.

### 5.4 A skeleton geometriát TART és nem olvasható tartalomként

Az R10 szabálya itt is él — a kártya betöltés közben nem ugrik.

### 5.5 A komponens NEM hív AI-t és nem tartalmaz üzleti logikát

Prezentációs réteg: minden adat kívülről jön.

### 5.6 A hosszú magyar cím nem csordul túl

Az R04 fixture-szabálya szerint, compact és expanded sűrűségben is.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az AI-eredet (helyi/felhő) minden AI-tartalomnál látható | `ss_badges_test.dart` |
| A2 | Egy badge jelentése sem csak színnel jelölt | ugyanott |
| A3 | A kártya háttere csak egyetlen fő akciónál kattintható | `ss_cards_test.dart` |
| A4 | Beágyazott akció koppintása NEM váltja ki a kártya-akciót | ugyanott |
| A5 | A skeleton tartja a geometriát, és nincs a semanticsben | ugyanott |
| A6 | Hosszú magyar cím compact és expanded sűrűségben sem csordul túl | `ss_cards_test.dart` |
| A7 | A komponensek nem importálnak feature-logikát | architektúra-guard |
| A8 | Minden új szöveg ARB-n át megy (en + hu) | `grep` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Az őr FAJTÁJA |
|---|---|---|
| A provenance csak a részletnézetben (a kártya alapállapotában nincs kirendelve) | **A1** | widget-cella: a kártyát AI-tartalommal kirendelve a provenance-badge a fában van |
| A confidence csak színes pötty (nincs ikon és nincs szöveg) | **A2** | tulajdonság-cella (lásd lent) |
| A kártya `InkWell`-ben, két gombbal | **A3** | widget-cella: `InkWell.onTap` a kirendelt fában |
| A beágyazott gomb koppintása felbuborékol | **A4** | interakciós cella: `tap` a gombon → a kártya-callback **nem** hívódik |
| A skeleton más magasságú, mint a kész kártya | **A5** | geometria-cella: `tester.getSize(...)` egyezés |
| Csak angol fixture | **A6** | fixture-cella: hosszú magyar cím compact ÉS expanded sűrűségben |
| Egy komponens `lib/features/**`-ból importál | **A7** | `tool/check_architecture.dart` (`coreMustNotImportFeatures`, §0.0/D6) |
| Egy user-nek szóló string a Dart forrásban, nem ARB-ban | **A8** | `grep` a diffben + `check_l10n_parity` |

**Az őrök MÉRJÉK A KIRENDELT WIDGETET, ne egy predikátumot, és a badge-nél
TULAJDONSÁG-SZINTEN** (mért gyökérokok: [`L457`](../LESSONS.md) — egy zöld
cella a prezentációs modellt mérte, miközben a user egy halott gombot látott;
[`L460`](../LESSONS.md) — a `find.text()` a láthatatlan maradékot is
megtalálja, ezért a puszta jelenlét-keresés VAK). Konkrétan:

- **A2** ne érje be azzal, hogy „van valamilyen `Text` vagy `Icon` a badge-ben".
  A cella állítsa, hogy a badge **ikon-adata és szöveg-tartalma** a státuszhoz
  kötött, és **két különböző státusz két különböző ikont/szöveget** ad — így egy
  „minden státuszhoz ugyanaz az ikon, csak a szín más" implementáció PIROS.
- **A3/A4** a `find.byType(InkWell)`/`GestureDetector` **kirendelt** példányát
  és a tényleges `tester.tap(...)` hatását mérje, ne egy `bool isTappable`
  mezőt.

**A kártya-kattinthatóság három kötelező cellája** (a küszöb: a fő akciók száma):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 0 akció (tisztán információs) | a kártya **nem** kattintható |
| rajta (a küszöbön) | **1** fő akció | a teljes kártya kattintható |
| a küszöb fölött | 2+ akció | a kártya **nem** kattintható, csak a gombok |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd kattinthatóvá a
kártya hátterét két akció mellett → az **A3** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
dart run tool/gen_l10n_segments.dart --write
tools/round-gate.sh test/core/design_system/cards/ss_cards_test.dart test/core/design_system/cards/ss_badges_test.dart test/core/design_system/component_catalog_test.dart
```

A `--write` a §0.0/D2 miatt KÖTELEZŐ és a gate ELŐTT fut; a katalógus-teszt a
§0.0/D3 miatt harmadik gate-útvonal (fagyott őr, nem szerkesztheted).

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_status_badge.dart` + `ss_provenance_badge.dart` — ikon + szöveg, SAJÁT
   prezentációs enummal, a meglévő `SsColorScheme` tokenekből olvasva (§0.0/D4).
2. `ss_metric_card.dart` — a `SsTypography.metric*` tokenek OLVASÁSÁVAL
   (Montserrat + tabular figures már bennük van, §0.0/D5); a bázis `SsSurface`,
   **nem** `SsCard` (§0.0/D3).
3. `ss_insight_card.dart`, `ss_coach_action_card.dart`, `ss_content_card.dart`.
4. `ss_model_status_card.dart`.
5. A kattinthatóság három cellája + a beágyazott hit-test (§6.1, a kirendelt
   widgetet mérve).
6. Skeletonok (a kártyafájlokban, `SsSkeleton`-ből) + ARB-**fragmentum** (en +
   hu) + `dart run tool/gen_l10n_segments.dart --write` + Component Catalog
   mátrix a §0.0/D3 három megkötésével (**nincs új `SsCard`, nincs
   `DecoratedBox`, nincs skeleton-demó a katalógusban**).
7. A valódi-sértés próba, §10-be dokumentálva.
8. `dart run tool/gen_l10n_segments.dart --write`, majd `tools/round-gate.sh`
   a §7 szerint (három teszt-útvonal).

## 9. Kockázatok

- **A provenance elrejtése.** A tisztább kártya kedvéért eltűnik egy
  adatvédelmi tény (A1).
- **A mindenhol kattintható kártya.** Egységesnek tűnik, és két akció mellett
  kiszámíthatatlan (A3/A4).
- **A csak színes confidence.** A leggyorsabb megoldás, és pont a termék
  bizonytalanság-kommunikációját teszi hozzáférhetetlenné (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
