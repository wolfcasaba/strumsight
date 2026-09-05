# E14-R09 — Baseline dashboard és fail-closed release gate

- **Státusz:** READY (pre-flight elvégezve 2026-09-05, kód mérve: `main @ 20736577`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 9 —
  a „mérési és bizonyítási alap" blokk (R01–R09) ZÁRÓ köre
- **Kör-azonosító:** `E14-R09`
- **Branch:** `sonnet-impl/e14-r09-baseline-dashboard-and-release-gate`
- **Előfeltétel:** `E14-R08` merge-elve (a harness, amelynek a kimenetét a
  dashboard és a kapu olvassa).
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `0511` — **a Claude megírta a pre-flightban**
  (`docs/adr/0511-recognition-release-gate-and-single-source-report.md`);
  a `docs/adr/` a TILOS zónában van.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/domain/evaluation/recognition_release_gate.dart",
  "lib/features/live/data/evaluation/recognition_report_renderer.dart",
  "evaluation/recognition/recognition_release_gate.json",
  "tool/recognition_report.dart",
  "test/features/live/evaluation/recognition_release_gate_test.dart",
  "test/features/live/evaluation/recognition_report_renderer_test.dart",
  "docs/eval/recognition-dashboard.md",
  "docs/rounds/e14-r09-baseline-dashboard-and-release-gate.md",
]
gate_tests = [
  "test/features/live/evaluation/recognition_release_gate_test.dart",
  "test/features/live/evaluation/recognition_report_renderer_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Pre-flight revízió (2026-09-05, Claude/Opus 5)

A brief 2026-08-20-án készült; az alábbi állításait a pre-flight kimérte a
FÁN, és ahol a mérés mást mondott, ez a szakasz írja felül a brief eredeti
szövegét. A revízió a kör saját, még nem merge-elt artefaktumát érinti
(ADR 0087 §2), tehát az orchestrátor hatásköre.

**R1 — Az ADR-szám `0361` helyett `0511`.** `docs/adr/0361-*.md` nem létezik;
a foglaló (`tools/round-slots.py reserve-adr --round E14-R09`) a `0511`-et
adta. Ugyanaz a mintázat, mint az E14-R08-nál (előjegyzés `0360`, valóság
`0509`). A foglaló a mérvadó (ADR 0171 §1.0.1). **Az implementer az ADR-t nem
írja és nem módosítja** — készen áll a fán.

**R2 — A `technique` bontás KIKERÜL.** A `GroupKey` enum
(`lib/features/live/domain/evaluation/recognition_split.dart:18`) pontosan négy
értéket deklarál — `player, device, guitar, room` —, a `RecognitionCase`
(`…/recognition_metrics.dart:122`) pedig nem hordoz technika-mezőt.
`grep -rn "technique\|Technique" lib/features/live evaluation/recognition docs/eval`
→ **nulla találat**. A kulcs felvétele az E14-R08 lezárt köréhez tartozó két
fájl módosítását kívánná, amelyek a TILOS zónában vannak (H2/H3). **A kör négy
csoportkulcson bont**, és a `docs/eval/recognition-dashboard.md` kimondja, hogy
a technika-bontás egy későbbi kör dolga (ADR 0511 „Következmények").

**R3 — A csoport-bontást EZ a kör számolja, nem olvassa.** Az E14-R08
`RecognitionEvaluationReport`-ja (`recognition_metrics.dart:421-442`) három
mezőt hordoz: `manifestSchemaVersion`, `caseCount`, `overall` — **per-csoport
metrika nincs benne**. A brief §9 „itt csak olvasás és megjelenítés történik"
mondata ezért pontatlan volt. A helyes eljárás: a kör a `List<RecognitionCase>`
listát `GroupKey` szerint particionálja, és csoportonként meghívja a
**nyilvános** `computeRecognitionMetrics` függvényt
(`recognition_metrics.dart:449`). **Új metrika-számítást írni tilos** — a
particionálás + a meglévő függvény hívása a teljes megengedett művelet.

**R4 — Az `uncertainCorrect` nem mérhető; kimondott `null` lesz.** A
per-esemény helyesség-halmaz (`correctAccepted`,
`recognition_metrics.dart:680`) a `computeRecognitionMetrics` törzsében lokális,
a párosító (`_matchEvents:832`, `_maxBipartiteMatching:884`) privát. Az
absztinens detekciók helyessége tehát nem áll elő a nyilvános kimenetből, a
Kuhn-párosító lemásolása pedig két számítási forrást hozna ugyanarra a mérésre
(`docs/LESSONS.md` L269: mohó vs. maximális párosítás MÁS TP-számot ad). A
másik kettő viszont pontosan levezethető:

| Kategória | Képlet a nyilvános mezőkből |
|---|---|
| `confidentWrong` | `acceptedAccuracy.denominator − acceptedAccuracy.numerator` |
| `rejected` | `coverage.denominator − coverage.numerator` |
| `uncertainCorrect` | **`null` + `unavailableReason` szöveg** (ADR 0511 D4) |

A `null`-t `0`-ra cserélni hamis állítás és **tilos**.

**R5 — Az irányt (`>=` / `<=`) a REPORT adja, nem a küszöbfájl.** Minden
metrika a saját `RecognitionMetricDefinition.higherIsBetter` mezőjét viszi
magával (`recognition_metrics.dart:159-187`, ADR 0509 D3/D4). A küszöbfájl
CSAK határértéket ad; ha mégis irányt deklarálna, az típusos hiba (ADR 0511 D2).
Az irány-tudatos összevetés meglévő megvalósítása
(`tool/benchmarks/benchmark_record.dart`, ADR 0474) a `tool/` fában él, amit a
`lib/` nem importálhat — ezért írja a kör a sajátját, de az irányt akkor sem
deklarálja újra.

**R6 — Két Ch14 Alpha-sornak NINCS metrikája; kimondva kimaradnak.** Az
`acceptedAccuracy` (`recognition_metrics.dart:684-697`) az ÖSSZES elfogadott
detekción mér, **nem** irányra vagy akkordra szűkítve. Ezért a Ch14 §7.2
„accepted **direction** accuracy" és §7.4 „confirmed **chord** accepted
accuracy" sorai, valamint a „leggyengébb támogatott chord recall" nem
képezhetők le hűen. A küszöbfájl v1 **nem** helyettesíti őket hasonló nevű, más
jelentésű metrikával (ez lenne az L549 hibaosztálya); a
`docs/eval/recognition-dashboard.md` felsorolja őket mint még nem gépiesített
kaput. A 6. §-beli `0,90`-es cellahármas ezért **az `overall.acceptedAccuracy`
útvonalon**, a Ch14 §7.2 `0,90` határértékével mérendő, és a doksi kimondja,
hogy ez az esemény-fajta-agnosztikus változat.

**R7 — S12 (brief-lint) javítva:** a §7 gate-parancs mostantól szó szerint
tükrözi a `gate_tests` listát.

**R8 — Névütközés nincs:** `RecognitionReleaseGate`, `RecognitionGateThresholds`,
`RecognitionGateVerdict`, `RecognitionGateFinding`, `RecognitionReportRenderer`,
`RecognitionDashboardReport`, `RecognitionGroupBreakdown`,
`RecognitionEventCategories` — nulla találat a `lib/`, `tool/`, `test/` fában.
A `lib/features/live/public.dart` kézzel írott (a `public/` fragment-könyvtár
nem létezik), ezért új `domain/`/`data/` fájl **nem** teszi elavulttá — a
barrelt NE módosítsd (nincs is az engedélyezett listán).

### 0.0.1 Visszakeresett előzmény (ADR 0312)

- `lessons/L269` — mohó vs. maximális párosítás más TP-számot ad → a párosítót
  nem másoljuk (R4).
- `lessons/L549` — a metaadat MEGLÉTÉT mérni nem ugyanaz, mint a JELENTÉSÉT
  érvényesíteni: 33 zöld cella közül egy sem mérte, hogy a két összevetett szám
  összetartozik-e → a küszöb neve és a metrika jelentése nem csúszhat szét (R6),
  és az irány egyetlen forrásból jön (R5).
- `lessons/L526` — a Markdown-tábla „hiányzó cella" toleranciája a renderelővel
  ELLENTÉTES helyre szúr be → a MD-visszaolvasó teszt oszlop-fejlécre
  illesszen, ne pozícióra.
- `lessons/L613` — dátumozott jelentést nem őrizhet olyan cella, amely a számot
  az ÉLŐ fából méri újra → a küszöb-teszt a v1 értékeket **kipinneli** (ADR 0511 D9).
- `adr/0473` — fail-closed manifest, „ismeretlen ≠ zöld".
- `adr/0477` — örökölt küszöb + fail-closed hiány; a küszöb-logikát importálni
  kell, nem másolni (itt a `tool/` határ miatt nem importálható — R5).
- `adr/0509` — az olvasott metrika-készlet szerződése.

## 1. Cél

A release-döntés ne egyetlen százalékon múljon: ugyanabból a mérésből
készüljön JSON, Markdown és HTML report **per-player/-device/-guitar/-room**
bontással (technika: R2), külön mutatva a **confident wrong**, **uncertain
correct** és **rejected** eseményeket — és legyen mellette egy verziózott,
**fail-closed** kapu (`recognition_release_gate.json`), amely hiányzó metrikára
FAIL-t ad.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **E14-R01 release guard:** a szabály (`UNKNOWN > CONFIDENTLY WRONG`) és a
  baseline-számok (akkord 67,1%, onset F1 50 ms 67,4%, irány 80,7%) — a kapu
  ezekhez képest mér, és a guard-dokumentum a hivatkozás.
- **ADR 0053 / round-gate:** a repóban a kapu artefaktum, nem prompt-szöveg —
  ezért a release gate is futtatható fájl + teszt, nem doksi-mondat.
- A teljes, mért visszakeresés a §0.0.1-ben.

## 2. Jelenlegi állapot — mért tények (2026-09-05, `main @ 20736577`)

- `docs/eval/recognition-release-guard.md` — MEGVAN (E14-R01), de **nincs**
  géppel olvasható küszöbfájl mellette.
- `evaluation/recognition/` — `README.md`, `annotation_schema.json`,
  `baseline_manifest.json`, `baseline_manifest_schema.json`,
  `fixtures/annotation_pair.json`, `fixtures/ci_manifest.json`. Kapu-fájl
  **nincs**.
- `lib/features/live/domain/evaluation/` — `recognition_annotation.dart`,
  `recognition_metrics.dart`, `recognition_split.dart`.
  `lib/features/live/data/evaluation/` — `recognition_annotation_parser.dart`,
  `recognition_evaluation_runner.dart`. Dashboard/report renderer és kapu
  **nincs**.
- `tool/` — `recognition_annotate.dart`, `recognition_evaluate.dart` megvan;
  `recognition_report.dart` **nincs**.

## 3. Scope

**Benne:** kapu-modell + verziózott küszöbfájl, fail-closed kiértékelés,
JSON/Markdown/HTML renderer ugyanabból a köztes modellből, négy csoportkulcs
szerinti bontás, a három esemény-kategória külön megjelenítése, CLI, doksi.

**Nincs benne:** küszöb-hangolás modellre, modellcsere, `ml/**`, valós korpusz
a repóban, CI-workflow módosítás, UI a telefonon, **új metrika-számítás**, a
`GroupKey` bővítése, a `public.dart` barrel, új pubspec-függés.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/domain/evaluation/recognition_release_gate.dart` | kapu-modell + küszöb-parser + kiértékelés |
| `lib/features/live/data/evaluation/recognition_report_renderer.dart` | köztes modell + JSON/MD/HTML ugyanabból a forrásból |
| `evaluation/recognition/recognition_release_gate.json` | verziózott küszöbök (v1) |
| `tool/recognition_report.dart` | CLI: report + kapu |
| `test/features/live/evaluation/recognition_release_gate_test.dart` | fail-closed mátrix |
| `test/features/live/evaluation/recognition_report_renderer_test.dart` | három formátum, determinizmus |
| `docs/eval/recognition-dashboard.md` | olvasási útmutató |
| `docs/rounds/e14-r09-baseline-dashboard-and-release-gate.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten
`lib/features/live/domain/evaluation/recognition_metrics.dart`,
`…/recognition_split.dart`, `…/data/evaluation/recognition_evaluation_runner.dart`
(E14-R08 lezárt köre), `docs/eval/recognition-release-guard.md` (E14-R01
rekordja), `lib/features/live/public.dart`, `pubspec.yaml`, `ml/**`,
`lib/features/live/engine/**`, `assets/**`, `docs/adr/**`, `.github/workflows/**`,
`tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0511)

### 5.1 A kapu fail-closed

Hiányzó metrika = **FAIL**, nem „nincs adat, átengedjük". **NEM elfogadható**
gyengítés: `null` → `skip`, hiányzó kulcs → átengedés, vagy default-érték
behelyettesítése a hiányzó metrika helyére. A hiányzó metrika **neve**
megjelenik az indoklásban (ADR 0511 D1).

### 5.2 A küszöbfájl verziózott, és a report hivatkozza

A `recognition_release_gate.json` gyökerében `schemaVersion` és
`thresholdsVersion`; a report minden kapu-ítéletéhez leírja, MELYIK verzió
alapján döntött. Ismeretlen `schemaVersion` → **típusos hiba**, sosem default
(ADR 0511 D6).

### 5.3 Egy forrás, három formátum

A JSON, a Markdown és a HTML UGYANABBÓL a köztes `RecognitionDashboardReport`
modellből készül; a formázás (kerekítés is) EGY helyen, a köztes modellben
történik. Tilos külön-külön összeállítani vagy formátumonként újrakerekíteni
őket (ADR 0511 D5).

### 5.4 A három esemény-kategória külön látszik

`confidentWrong`, `uncertainCorrect`, `rejected` külön mező; egyik sem olvad be
az „accuracy" számba. A `rejected` **nem** hibás találat. Az `uncertainCorrect`
kimondottan `null` + `unavailableReason` (ADR 0511 D4, §0.0 R4).

### 5.5 Az irány a reportból jön

`higherIsBetter == true` → `value >= threshold`; `false` → `value <= threshold`.
A pontosan a küszöbön álló érték **PASS**. Epszilon-tűrés, kerekítés vagy
szöveggé alakítás utáni visszaolvasás az összevetésben tilos (ADR 0511 D2/D3).

### 5.6 A baseline felülírása emberi döntés

A kapu-fájl küszöbeinek lazítása a kód-oldalon nem lehetséges: a fájl a
`docs/eval/recognition-dashboard.md` szerint review-hoz kötött, és a teszt
**kipinneli** az aktuális Alpha-értékeket (ADR 0511 D9).

## 6. Acceptance criteria

1. Hiányzó metrika esetén a kapu ítélete **FAIL**, és a hiányzó metrika neve
   megjelenik az indoklásban. Ugyanígy FAIL, ha a metrika jelen van, de az
   értéke `null` (nulla nevező / nulla minta).
2. A küszöb-összehasonlítás mindhárom cellája mérve, a Ch14 §7.2 irány-küszöb
   (`0,90`) példáján az `overall.acceptedAccuracy` útvonalon: a küszöb **alatt**
   (`0.899`) → FAIL; **rajta** (pontosan `0.9`) → PASS, mert a határ az
   elfogadó oldalhoz tartozik; **fölött** (`0.901`) → PASS.
   Ellen-irányú metrikán is mérve (`higherIsBetter == false`,
   `falseVisibleEventsPerMinute`, Ch14 küszöb `2` / perc): `2.001` → FAIL,
   `2.0` → PASS, `1.999` → PASS.
3. A három formátum ugyanazokat a számokat tartalmazza: a teszt a Markdownból
   (oszlop-**fejléc** szerint, nem pozíció szerint — L526) és a HTML-ből
   visszaolvasott értékeket a JSON-hoz hasonlítja, legalább egy `overall` és
   egy csoport-metrikán.
4. A `confidentWrong` / `rejected` / `uncertainCorrect` mezők külön
   szerepelnek. Mérve: `confidentWrong ==
   acceptedAccuracy.denominator − acceptedAccuracy.numerator`,
   `rejected == coverage.denominator − coverage.numerator`, és egy olyan
   fixture-ön, ahol van absztinens detekció, a `rejected` értéke **nem**
   jelenik meg sem az `acceptedAccuracy` nevezőjében, sem a
   `falseVisibleEventsPerMinute.eventCount` értékében. Az `uncertainCorrect`
   `null`, és `unavailableReason` nem üres.
5. Kétszeri futtatás **bájtra azonos** JSON-t és Markdownt ad (a HTML-re
   ugyanígy). A kimenet nem tartalmaz időbélyeget, futásazonosítót vagy
   abszolút útvonalat.
6. A report minden kapu-ítéletnél megnevezi a `thresholdsVersion`-t —
   mindhárom formátumban.
7. Ismeretlen `schemaVersion` a kapu-fájlban **típusos hiba** (dedikált
   exception-típus), nem default-küszöbökre esés. Ugyanígy típusos hiba, ha egy
   küszöb-bejegyzés irányt (`>=`/`<=`/`higherIsBetter`) deklarál.
8. A csoport-bontás a négy `GroupKey` értékre készül, determinisztikus
   (csoportnév szerint rendezett) sorrendben; a `null` csoportkulcsú esetek
   nem tűnnek el némán (külön, megnevezett „ismeretlen" csoport vagy kimondott
   kizárás, számmal).
9. A szállított `evaluation/recognition/recognition_release_gate.json` a Ch14
   §7.2/§7.4 Alpha-értékeit hordozza, és a teszt ezeket **kipinneli** (a fájl
   beolvasott értékeit konstansokhoz hasonlítja, nem az élő fából méri újra).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Hiányzó metrika → `skip` | 1. pont FAIL-cellája |
| `null` értékű metrika → átengedés | 1. pont `null`-cellája |
| A küszöb-összehasonlítás szigorú (`>`) | 2. pont **rajta (0,9)** cellája |
| Az irány fixen `>=` (a `higherIsBetter` figyelmen kívül) | 2. pont ellen-irányú (`2.0` → PASS) cellája |
| A HTML külön számol kerekítést | 3. pont formátum-egyezés cellája |
| A MD-visszaolvasó pozícióra illeszt, és a tábla oszlopszáma nő | 3. pont fejléc-alapú cellája (L526) |
| A `rejected` beleszámít a hibás találatokba | 4. pont cellája |
| Az `uncertainCorrect` `0`-t ad `null` helyett | 4. pont `null`-cellája |
| A renderer időbélyeget ír a kimenetbe | 5. pont bájtra-azonos cellája |
| A csoportok halmaz-iterációs sorrendben jönnek | 5. pont bájtra-azonos + 8. pont rendezés-cellája |
| Ismeretlen séma-verzió → default küszöbök | 7. pont típusos-hiba cellája |
| A küszöbfájl v1 értéke elcsúszik a Ch14 Alphától | 9. pont kipinnelt cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation/recognition_release_gate_test.dart test/features/live/evaluation/recognition_report_renderer_test.dart
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a hiányzó-metrika ág ideiglenes `skip`-re állításával az
1. pont cellája **PIROS**, visszaállítva **ZÖLD**. Írd le a pontos parancsot és
a piros cella nevét.

## 8. Implementációs sorrend

1. Kapu-modell + küszöb-parser (típusos hibák) + `recognition_release_gate.json`
   v1 + fail-closed teszt.
2. Köztes `RecognitionDashboardReport` modell: csoport-particionálás
   (`GroupKey` × `computeRecognitionMetrics`) + a három esemény-kategória.
3. Renderer (JSON → MD → HTML) + determinizmus- és formátum-egyezés teszt.
4. `tool/recognition_report.dart` CLI + `docs/eval/recognition-dashboard.md`.

## 9. Kockázatok

- **A kapu túl korai szigora:** a küszöbök az Alpha-szintet rögzítik; a
  jelenlegi baseline (67,1% / 67,4% / 80,7%) alattuk van, tehát a kapu FAIL-t
  ad — ez a kapu HELYES viselkedése, nem hiba; a release-döntés emberi.
- **HTML-generálás mérete:** a renderer maradjon sablon-alapú, külső
  függőség nélkül (nincs új pubspec-függés — az a tilos zóna).
- **Átfedés az `E14-R08`-cal:** a metrika-KÉPLETEK ott vannak, és ez a kör nem
  ír újat; a csoport-particionálás viszont ITT történik (§0.0 R3), mert az R08
  reportja nem tartalmaz bontást.
- **Elcsúszó jelentés:** egy közeli, de más jelentésű metrika becsempészése egy
  Ch14 Alpha-sor neve alá (L549) — a §0.0 R6 kimondottan tiltja.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5), 2026-09-05.

### 10.1 Mit építettem

A nyolc engedélyezett fájl mindegyike elkészült:

- `lib/features/live/domain/evaluation/recognition_release_gate.dart` —
  `RecognitionReleaseGate` (küszöb-parser + `evaluate`), `RecognitionGateThresholds`/
  `RecognitionGateThresholdEntry`, `RecognitionGateVerdict`/`RecognitionGateFinding`,
  `RecognitionGateConfigException` (típusos hibák: `unknownSchemaVersion`,
  `directionDeclared`, `unknownMetricPath`, …), és a
  `recognitionMetricExtractors` regiszter — minden metrika-útvonalhoz egyetlen
  extraktor, amely a `value`-t ÉS a `higherIsBetter`-t is UGYANARRÓL a
  `RecognitionMetrics`-példányról olvassa (R5). A kapu csak `overall.*`
  útvonalakat fogad el (a `evaluate()` ellenőrzi az `overall.` prefixet, majd a
  regiszterben a metrika nevét).
- `evaluation/recognition/recognition_release_gate.json` — `schemaVersion: "1"`,
  `thresholdsVersion: "ch14-alpha-v1"`, 10 küszöb-bejegyzés (lásd 10.3).
- `lib/features/live/data/evaluation/recognition_report_renderer.dart` —
  `RecognitionDashboardReport.build(...)` particionálja a `cases`-t mind a
  négy `GroupKey` szerint (hiányzó kulcs → `"(unknown)"` csoport, sosem
  eldobva), csoportonként meghívja a nyilvános `computeRecognitionMetrics`-et,
  a metrikákat EGYSZER kerekíti (`toStringAsFixed(4)` → `double.parse`), és
  ugyanabból a modellből rendereli a JSON/MD/HTML-t (`RecognitionReportRenderer`).
  `RecognitionEventCategories.fromMetrics` számolja a `confidentWrong`/`rejected`-et
  a pontos D4-képlettel, `uncertainCorrect` mindig `null` + kimondott
  `uncertainCorrectUnavailableReason`.
- `tool/recognition_report.dart` — CLI: `--manifest`, `--thresholds`, `--format
  json|markdown|html`; kilépési kód `0` (kapu PASS) vagy `3` (kapu FAIL,
  fail-closed — sosem `0` bukott kapunál).
- `docs/eval/recognition-dashboard.md` — olvasási útmutató: csoport-bontás,
  három esemény-kategória, fail-closed szemantika, a kimaradó 4 Ch14
  Alpha-sor és indoklásuk, a küszöb-lazítás emberi-döntés szabálya.

### 10.2 Acceptance-cella → teszt megfeleltetés (§6, §6.1)

| # | Acceptance | Teszt |
|---|---|---|
| 1 | hiányzó/`null` metrika → FAIL, megnevezve | `recognition_release_gate_test.dart`: „fail-closed: missing/null metric” csoport (2 teszt) |
| 2 | határ az elfogadó oldalon, mindkét irány | „boundary belongs to the accepting side” csoport: `0.899/0.9/0.901` és `2.001/2.0/1.999` |
| 3 | 3 formátum ugyanaz a szám (fejléc-alapú MD/HTML olvasás) | `recognition_report_renderer_test.dart`: „single source, three formats” csoport (overall + csoport-metrika) |
| 4 | `confidentWrong`/`rejected`/`uncertainCorrect` külön, pontos képlet, `null` | „event categories” csoport (3 teszt) |
| 5 | bájtra azonos kétszeri futtatásra, nincs időbélyeg/útvonal | „determinism” csoport (2 teszt) |
| 6 | `thresholdsVersion` mindhárom formátumban | „every format names the gate thresholds version” |
| 7 | ismeretlen `schemaVersion` / irány-deklaráció → típusos hiba | „typed configuration errors” csoport (5 teszt) |
| 8 | 4 `GroupKey`, determinisztikus sorrend, „ismeretlen” csoport számmal | „determinism: groups are sorted…” + „unknown group naming” csoport (3 teszt) |
| 9 | a szállított JSON a Ch14 Alpha-értékeket hordozza, kipinnelve | „shipped v1 threshold file” csoport (2 teszt) |

### 10.3 A v1 küszöbfájl 10 bejegyzése és a 4 kimaradó Ch14 Alpha-sor

A `recognition_release_gate.json` a 14 Ch14 §7.2/§7.4 Alpha-sorból 10-et
képez le (lásd `docs/eval/recognition-dashboard.md` táblázatát a pontos
metrika-útvonalakkal). A **4 kimaradó sor** — mert egyiknek sincs hű
metrika-útvonala a nyilvános `RecognitionMetrics`-ben, és egyik sem
helyettesíthető egy hasonló nevű, de más jelentésű metrikával (L549, ADR
0511 D8): *leggyengébb támogatott chord recall*, *confirmed chord accepted
accuracy*, *chord transition p50*, *false confident chord hard-negative*.
Az *„accepted direction accuracy"* és a *„false visible arrow hard-negative"*
sorok az esemény-fajta-agnosztikus `overall.acceptedAccuracy.value` és
`overall.falseVisibleEventsPerMinute.value` útvonalakon vannak leképezve
(§0.0 R6), a dokumentumban és a küszöbfájl `label` mezőjében kimondva.

### 10.4 A gate tényleges kimenete

```
tools/round-gate.sh test/features/live/evaluation/recognition_release_gate_test.dart test/features/live/evaluation/recognition_report_renderer_test.dart
```

`format` → ZÖLD, `analyze` → ZÖLD (0 hiba), mindkét célzott teszt → ZÖLD (16,
majd 13 teszt), `architecture` → ZÖLD, `secrets` → ZÖLD, `l10n` → ZÖLD.
**MINDEN GATE ZÖLD.**

A CLI a szállított v1 küszöbfájllal és a `ci_manifest.json` fixture-rel
FAIL-t ad (`dart run tool/recognition_report.dart --format markdown`, exit
code `3`) — ez a kapu helyes viselkedése a jelenlegi (Alpha alatti) legacy
DSP-baseline-nal szemben, nem hiba (9. kockázat, ADR 0511 „Következmények”).

### 10.5 Falszifikációs bizonyíték (§7.1)

`lib/features/live/domain/evaluation/recognition_release_gate.dart`
`_evaluateEntry`-jében a hiányzó-metrika ágon a `passed: false`-t
ideiglenesen `passed: true`-ra állítottam (a „skip” egyenértékű
gyengítése), majd lefuttattam:

```
flutter test test/features/live/evaluation/recognition_release_gate_test.dart
```

**Eredmény: PIROS** — pontosan a 6.1-es mérce-mátrix „Hiányzó metrika →
`skip`” sorának megfelelő 1. acceptance-pont FAIL-cellája bukott, két teszt:
„fail-closed: missing/null metric a null-valued metric is FAIL and names the
metric” és „…skipping the missing-metric branch would turn this cell green”
(mindkettő `Expected: false / Actual: <true>` a `verdict.passed`/
`finding.passed` mezőn). A többi 13 teszt változatlanul ZÖLD maradt (a hiba
lokális volt a hiányzó-metrika ághoz).

Ezután a módosítást visszaállítottam (`passed: false`), és
`tools/round-gate.sh test/features/live/evaluation/recognition_release_gate_test.dart
test/features/live/evaluation/recognition_report_renderer_test.dart` teljes
kapuja **ZÖLD**-re futott (10.4). `git diff --stat` a visszaállítás után
üres volt — a fán nem maradt nyoma a kísérletnek.

### 10.6 Amit tudatosan NEM csináltam

A `GroupKey`-t nem bővítettem `technique`-kel (R2, tilos zóna). Nem
importáltam és nem használtam a `RecognitionSplitBuilder`/`LeakageDetector`-t
(train/eval fold-okhoz való, nem csoport-bontáshoz) — a
`recognition_report_renderer.dart` saját, egyszerű
`SplayTreeMap`-particionálást ír, amely a hiányzó kulcsot `"(unknown)"`-ra
képezi ahelyett, hogy (mint a `RecognitionSplitBuilder`) dobna. Nem
módosítottam a `pubspec.yaml`-t, a `public.dart` barrelt, sem az E14-R08
fájljait.

## 11. Review — a Claude tölti ki
