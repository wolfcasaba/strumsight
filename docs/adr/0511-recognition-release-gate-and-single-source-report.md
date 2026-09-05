# ADR 0511 — Fail-closed felismerési release-kapu: a küszöb a metrika saját irányával mér, és egy köztes modellből készül mindhárom formátum

- **Státusz:** Elfogadva
- **Kör:** `E14-R09` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 9)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0509](0509-grouped-recognition-evaluation-harness.md)
  (a metrika-készlet, amit ez a kör OLVAS — `higherIsBetter` a metrika
  definíciójában utazik, nulla nevezőnél `null`, sosem `0`),
  [ADR 0271](0271-recognition-recovery-program.md) (a recovery-program és a
  `UNKNOWN > CONFIDENTLY WRONG` szabály),
  [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
  (determinisztikus, bájtazonos mérési artefaktum),
  [ADR 0473](0473-release-fixture-corpus-manifest.md) (fail-closed manifest:
  „ismeretlen ≠ zöld"),
  [ADR 0477](0477-ai-release-evidence-aggregation-and-ga-scope-truth.md)
  (örökölt küszöb + fail-closed hiány; a küszöb-logikát ott IMPORTÁLNI kellett,
  nem másolni — lásd D2 alább)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 20736577`)

- **Az előre kiosztott `0361` szám elavult.** A `docs/adr/0361-*.md` nem
  létezik, és a foglaló (`tools/round-slots.py reserve-adr --round E14-R09`) a
  **`0511`** számot adta. Ugyanaz a mintázat, mint az E14-R08-nál (a brief
  `0360`-at foglalt, a valóságos szám `0509` lett): a 2026-08-20-i előre-írt
  briefek ADR-számai azóta tárgytalanok. A foglaló `O_CREAT|O_EXCL` markert ír,
  ezért ő a mérvadó; az `ls docs/adr | tail` alak sorszám-választásra tiltott
  (`tools/tests/test_adr_numbering.py`).

- **Az E14-R08 report NEM tartalmaz csoport-bontást.** A
  `RecognitionEvaluationReport` (`…/domain/evaluation/recognition_metrics.dart:421-442`)
  pontosan három mezőt hordoz: `manifestSchemaVersion`, `caseCount`, `overall`.
  Per-player/-device/-guitar/-room metrika a fában **nincs**. A csoportosítást
  tehát ez a kör végzi el: a `RecognitionCase` listát a `GroupKey` szerint
  particionálja, és csoportonként meghívja a **nyilvános**
  `computeRecognitionMetrics` függvényt (`recognition_metrics.dart:449`) — nem
  ír új metrika-számítást.

- **`technique` csoportkulcs a fában NINCS.** A `GroupKey` enum
  (`…/domain/evaluation/recognition_split.dart:18`) pontosan négy értéket
  deklarál: `player, device, guitar, room`, és a `RecognitionCase`
  (`recognition_metrics.dart:122-147`) sem hordoz technika-mezőt. `grep -rn
  "technique\|Technique" lib/features/live evaluation/recognition docs/eval` →
  **nulla találat**. A kulcs felvétele a `recognition_split.dart` és a
  `recognition_metrics.dart` módosítását kívánná, amelyek a kör TILOS zónájában
  vannak (E14-R08 lezárt köre, ADR 0087 §2 H2/H3).

- **A `confidentWrong` / `uncertainCorrect` / `rejected` számláló a fában
  nincs** (`grep -rn "confidentWrong\|uncertainCorrect\|rejected"
  lib/features/live/{domain,data}/evaluation` → nulla találat). Kettő közülük a
  meglévő, nyilvános metrika-mezőkből **pontosan** levezethető, a harmadik
  **nem** — lásd D4.

- **A per-esemény helyesség-halmaz PRIVÁT.** A `correctAccepted` halmaz a
  `computeRecognitionMetrics` törzsében, lokális változóként áll elő
  (`recognition_metrics.dart:680-686`), és a párosítót (`_matchEvents`,
  `_maxBipartiteMatching`, `recognition_metrics.dart:832`, `:884`) aláhúzás
  rejti. A kör tehát nem tud per-esemény helyességet kérdezni anélkül, hogy a
  Kuhn-párosítót lemásolná — az pedig két számítási forrást hozna létre
  ugyanarra a mérésre (a `docs/LESSONS.md` L269 mért hibaosztálya: mohó vs.
  maximális párosítás **más** TP-számot ad).

- **A `higherIsBetter` már a reportban utazik.** Minden metrika-típus a saját
  `RecognitionMetricDefinition`-jét viszi (`recognition_metrics.dart:159-187`),
  benne a `higherIsBetter` iránnyal (ADR 0509 D3/D4).

- **Az irány-tudatos küszöb-összevetés meglévő megvalósítása NEM importálható:**
  a `tool/benchmarks/benchmark_record.dart` (ADR 0474) a `tool/` fában él, a
  `lib/` pedig nem importálhat `tool/`-t. Ezért a kör saját összehasonlítót ír a
  `lib/`-ben — de a **irányt nem deklarálja újra**, hanem a reportból olvassa
  (D2).

- **A Chapter 14 Alpha-kapu értékei (SDD `14-…§7.2`, `§7.4`) mértek:** onset F1
  @50 ms `0,82`; end-to-end direction macro-F1 `0,80`; accepted direction
  accuracy `0,90`; coverage `0,70`; false visible arrow `<= 2 / perc`; verdict
  latency p50 `<= 180 ms`, p95 `<= 280 ms`; chord weighted accuracy `0,80`;
  chord macro-F1 `0,70`; N.C./unknown F1 `0,88`; leggyengébb támogatott chord
  recall `0,55`; confirmed chord accepted accuracy `0,88`; false confident chord
  `<= 2 / perc`.

- **A Ch14 nevesített Alpha-sorai közül kettőnek NINCS megfelelő metrikája az
  E14-R08 készletében:** a *„leggyengébb támogatott chord recall"* (a
  `RecognitionMacroF1` nem publikál per-osztály recallt a JSON-ban külön
  mezőként a `chordMacroF1`-en belüli osztály-bontáson kívül), és a *„confirmed
  chord accepted accuracy"* (az `acceptedAccuracy` **esemény-fajta-agnosztikus**:
  `recognition_metrics.dart:684-697` az ÖSSZES elfogadott detekción méri, nem
  chordra szűkítve). Ugyanez az agnosztikusság érinti az *„accepted **direction**
  accuracy"* sort is.

- **Névütközés nincs:** `RecognitionReleaseGate`, `RecognitionGateThresholds`,
  `RecognitionGateVerdict`, `RecognitionGateFinding`, `RecognitionReportRenderer`,
  `RecognitionDashboardReport`, `RecognitionGroupBreakdown`,
  `RecognitionEventCategories` — mind nulla találat a `lib/`, `tool/`, `test/`
  fában.

- **A `live` barrel kézzel írott** (`lib/features/live/public.dart`, 36 sor; a
  `lib/features/live/public/` fragment-könyvtár nem létezik), ezért új
  `domain/`/`data/` fájl nem teszi elavulttá — ugyanaz a mérés, ami az E14-R07/R08
  köröket is átvitte a barrel érintése nélkül.

## Döntés

### D1 — A kapu fail-closed: hiányzó metrika FAIL, és megnevezve

A kapu ítélete `FAIL`, ha a küszöbfájl olyan metrikát ír elő, amelyet a report
nem tartalmaz, vagy amelynek értéke `null` (nulla nevező, nulla minta). Az
indoklásban a **hiányzó metrika neve** szerepel. Tilos gyengítés: `null` →
`skip`, hiányzó kulcs → „nincs adat, átengedjük", és default-érték
behelyettesítése. Ez az ADR 0473 „ismeretlen ≠ zöld" mintájának felismerési
oldali alkalmazása.

### D2 — Az összehasonlítás iránya a REPORTBÓL jön, nem a küszöbfájlból

A küszöbfájl egy metrikához a **határértéket** adja meg, az irányt (`>=` vagy
`<=`) NEM: azt a kapu a report saját `definition.higherIsBetter` mezőjéből
olvassa. Indoklás: két, egymástól független irány-forrás előbb-utóbb
széttart, és az eredmény néma — a `docs/LESSONS.md` L549 pontosan ezt mérte
(33 zöld cella közül egy sem mérte a két összevetett mérés összetartozását).
Ha egy küszöbfájl-bejegyzés mégis irányt deklarálna, az **típusos hiba**, nem
felülírás.

### D3 — A határ az ELFOGADÓ oldalhoz tartozik

`higherIsBetter == true` esetén a feltétel `value >= threshold`;
`higherIsBetter == false` esetén `value <= threshold`. A pontosan a küszöbön
álló érték **PASS**. Az összevetés a `double` értékeken közvetlen
összehasonlítás — kerekítés, epszilon-tűrés vagy szöveggé alakítás után
visszaolvasás tilos (az kerekítési szinten átengedne egy küszöb alatti értéket).

### D4 — A három esemény-kategória közül kettő MÉRT, a harmadik kimondottan `null`

- `confidentWrong` = `acceptedAccuracy.denominator − acceptedAccuracy.numerator`
  — elfogadott (a felhasználónak megmutatott) detekciók, amelyek nem helyesek.
  Pontos, a nyilvános mezőkből; azonos az
  `falseVisibleEventsPerMinute.eventCount` értékkel.
- `rejected` = `coverage.denominator − coverage.numerator` — a motor által
  detektált, de nem felszínre hozott (absztinens) események. Pontos.
- `uncertainCorrect` = **`null`, kimondott indoklással**. Az absztinens
  detekciók közötti helyesség nem áll elő az E14-R08 nyilvános kimenetéből (a
  helyesség-halmaz privát, lásd a Kontextust), a párosító lemásolása pedig D5-öt
  sértené. A `null` mellé a modell egy `unavailableReason` szöveget visz, és a
  kapu erre a metrikára állított küszöböt D1 szerint **FAIL**-nek veszi.

Egyik kategória sem olvad be az accuracy-számba. Kimondottan: a `rejected`
**nem** hibás találat — sem az `acceptedAccuracy` nevezőjében, sem a
`falseVisibleEventsPerMinute` számlálójában nem szerepel (mérhető: a
`coverage` nevezője nagyobb az `acceptedAccuracy` nevezőjénél pontosan a
`rejected` értékével).

### D5 — Egy köztes modell, három formátum

A JSON, a Markdown és a HTML UGYANABBÓL a köztes
`RecognitionDashboardReport` modellből készül. A renderelők a modell már
kiszámolt, formázott értékeit írják ki — külön kerekítés, külön aggregálás vagy
külön küszöb-kiértékelés formátumonként tilos. A számok formázása EGY helyen, a
köztes modellben történik, ezért a három formátumból visszaolvasott érték
azonos.

### D6 — Verziózott küszöbfájl, és minden ítélet megnevezi a verziót

Az `evaluation/recognition/recognition_release_gate.json` gyökerében
`schemaVersion` és `thresholdsVersion` áll. Ismeretlen `schemaVersion` →
**típusos hiba** (a parser dobja), sosem default-küszöbökre esés. Minden
kapu-ítélet (a JSON-ban, a Markdownban és a HTML-ben egyaránt) leírja, melyik
`thresholdsVersion` alapján döntött.

### D7 — Determinizmus: nincs időbélyeg a kimenetben

A renderelt JSON és Markdown kétszeri futtatásra **bájtra azonos**. A kimenet
nem tartalmaz időbélyeget, futásazonosítót, abszolút útvonalat vagy
halmaz-iterációs sorrendet: a csoportok és a metrikák determinisztikus (nevük
szerint rendezett) sorrendben jelennek meg. Ez az ADR 0354 bájtazonos
artefaktum-szabályának folytatása.

### D8 — A küszöbfájl a Ch14 Alpha-sorait rögzíti, a le nem fedett sorokat KIMONDVA hagyja ki

A szállított `recognition_release_gate.json` **v1** azokat a Ch14 Alpha-sorokat
tartalmazza, amelyeknek van megfelelő metrika-útvonala a reportban. A metrika
nélküli Alpha-sorokat (leggyengébb támogatott chord recall; a chordra, illetve
irányra szűkített accepted accuracy) a fájl **nem** helyettesíti egy hasonló
nevű, de más jelentésű metrikával — a `docs/eval/recognition-dashboard.md`
felsorolja őket mint még nem gépiesített kaput. Egy közeli metrika
becsempészése a rossz név alá pontosan az L549 hibaosztálya lenne.

### D9 — A küszöbök lazítása emberi döntés

A kapu-küszöbök kódból nem lazíthatók: a `recognition_release_gate.json` a
`docs/eval/recognition-dashboard.md` szerint review-hoz kötött artefaktum, és a
kör tesztje **kipinneli** a v1 Alpha-értékeket. A küszöb csökkentése tehát csak
a teszt egyidejű, látható átírásával lehetséges — a `docs/LESSONS.md` L613
mintája szerint a kipinnelt szám a mérce, nem az élő fából újramért érték.

## Következmények

- A felismerési release-döntés innentől egy futtatható artefaktumon áll, nem egy
  doksi-mondaton (ADR 0053 mintája: a mérce artefaktum, nem prompt-szöveg).
- A kapu a jelenlegi baseline-nel (akkord 67,1%, onset F1 67,4%, irány 80,7% —
  `docs/eval/recognition-release-guard.md`) szemben **FAIL**-t ad. Ez a kapu
  HELYES viselkedése, nem hiba: az Alpha-szintet rögzíti, és a release-döntés
  emberi (E14-R01 aktivációs szerződés).
- A `technique` bontás a Chapter 14 §7.1 korpusz-kívánalma marad; gépi
  megvalósítása egy későbbi kör dolga, amely a `GroupKey`-t bővíti. Ez a kör
  négy kulcson bont.
- Az `uncertainCorrect` gépi mérése akkor válik lehetségessé, ha egy későbbi kör
  az E14-R08 harness-t per-esemény helyesség kiadására bővíti. Addig a `null` +
  indoklás az igaz állítás, a `0` hamis lenne.
