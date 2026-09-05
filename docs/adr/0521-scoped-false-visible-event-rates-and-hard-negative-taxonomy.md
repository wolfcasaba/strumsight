# ADR 0521 — A szűkített hamis-esemény ráta a MERGE-ELT harness partíciója, és a hard-negative taxonómia gépi listája

- **Státusz:** Elfogadva
- **Kör:** `E14-R15` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 15)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [ADR 0509](0509-grouped-recognition-evaluation-and-leakage-protection.md)
  (a report-fa, a `correctAccepted` halmaz és az `accepted` szűrés — ez a kör
  ERRE épül),
  [ADR 0511](0511-recognition-release-gate-and-single-source-report.md)
  (D2: az irány MINDIG a metrika saját `definition.higherIsBetter`-éből; D7: a
  három renderelés EGY köztes modellből; D8: a „deliberately absent" lista és
  az `L549` helyettesítési tilalom; D9: a küszöbfájl reviewed artefaktum),
  [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (nyers audio nem kerül a repóba — a manifest hivatkozik, nem tartalmaz),
  [L549](../LESSONS.md#l549), [L630](../LESSONS.md#l630)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ b17e08ef`)

Az előre megírt brief (2026-08-20, `main @ 6371aa3`) alapja elmozdult; a
`brief-lint` **S15** foka emiatt jelzett, és a kör az EREDETI alakjában
dispatch előtt **H3**-mal megállt. A revíziót az ADR 0112 önjavító köre
végezte el (merge-elve: `b17e08ef`), a mai pre-flight pedig újramérte és
kiegészítette. A négy döntő tény:

### 1. Az eseményfajta-agnosztikus hamis-esemény ráta MÁR MERGE-ELVE VAN

`falseVisibleEventsPerMinute`
(`lib/features/live/domain/evaluation/recognition_metrics.dart:727-746`) az
E14-R08 óta él:

```dart
final falsePositiveAcceptedCount =
    acceptedDetections.length - correctAcceptedCount;
final durationMinutes = totalDurationMs / 60000;
```

Egy ÚJ, különálló fájlban élő, saját nevezővel és saját elfogadás-fogalommal
dolgozó „hamis-esemény metrika" tehát **második, divergens definíció** volna
ugyanarra a fogalomra — pontosan az `L549` hibaosztály, amit az ADR 0511 D8
szövege kifejezetten megnevez („none of them is replaced by a similarly named
but differently scoped metric").

### 2. A partíció MÉRHETŐEN zárt — nincs szükség új adatra

A számláló forrása két, már merge-elt halmaz
(`recognition_metrics.dart:676-689`): a `correctAccepted` az onset-,
strum- és akkord-párosításokból épül, az `acceptedDetections` pedig az
`allDetected.where((d) => d.accepted)` lista, fajta szerinti szűrés nélkül.
Mivel a `RecognitionEventKind` (`:24`) zárt hármas (`onset`, `strum`,
`chord`), az `accepted && !correctAccepted` halmaz fajta szerinti bontása
**pontosan** partícionálja az agnosztikus darabszámot. Az eseményfajta már ott
van a `RecognitionDetectedEvent.kind`-ben: a szűkítés nem új mérés, hanem a
meglévő számláló felbontása.

### 3. A metrika akkor létezik, ha NEVEZHETŐ

A `recognitionMetricExtractors`
(`recognition_release_gate.dart:60-108`) az EGYETLEN hely, ahonnan egy metrika
neve és iránya származhat, és a renderer ebből a kulcshalmazból generálja
mindhárom formátumot — generikusan, kulcslista nélkül
(`lib/features/live/data/evaluation/recognition_report_renderer.dart:59-73`,
`_summarize`). Ezért a renderer FORRÁSÁT ez a kör nem módosítja; az új
extractor-bejegyzés önmagában megjeleníti a metrikát a JSON/Markdown/HTML
renderelésben.

### 4. A küszöbfájl reviewed artefaktum, az átkötés külön döntés

`evaluation/recognition/recognition_release_gate.json:35-39` a Ch14 §7.2
„false visible arrow hard-negative" sorát MA az agnosztikus rátán kapuzza
(2,0/perc, `event-kind-agnostic` címkével), és a
`recognition_release_gate_test.dart:251-266` a TELJES bejegyzés-listát
pinneli. Az átkötés a szűkített rátára ADR 0511 D9 szerint ADR-döntés, nem
mellékhatás → **külön kör**.

## Döntés

**D1. A szűkített ráta a merge-elt metrika PARTÍCIÓJA, nem második
definíciója.** A `RecognitionMetrics` két új mezőt kap —
`falseVisibleDirectionEventsPerMinute` és `falseVisibleChordEventsPerMinute` —,
mindkettő `RecognitionRateMetric`, mindkettő ugyanabban a
`computeRecognitionMetrics` menetben, ugyanabból a `correctAccepted`
halmazból és ugyanazzal a `durationMinutes` nevezővel készül, mint az
agnosztikus `falseVisibleEventsPerMinute`. Külön fájlban élő második
metrika-definíció (`false_visible_event_metric.dart` vagy bármely más név)
**tilos**.

**D2. A számláló a MEGMUTATOTT eseményt számolja.** A predikátum
`d.accepted && d.kind == <fajta> && !correctAccepted.contains(d)`. Az
abstained (`accepted == false`) detektálás SOHA nem hamis pozitív — ez a
merge-elt ADR 0509 szerződés, amit ez a kör nem definiál újra. A modell nyers
kimenetének számolása tilos.

**D3. Percre normalizált, `null` az üres nevezőn.** Az érték
`eventCount / durationMinutes`, ahol `durationMinutes = totalDurationMs /
60000`. `durationMinutes == 0` esetén az érték `null` (a merge-elt viselkedés),
nem `0` — az „elhanyagolható rátának látszó nulla" pontosan az a hazugság,
amit az agnosztikus metrika már egyszer kizárt.

**D4. A partíció zárt, és ezt gépi cella bizonyítja.** Mivel az `onset`,
`strum`, `chord` a `RecognitionEventKind` teljes partíciója,

```
direction.eventCount + chord.eventCount + <onset-fajta hamis darabszám>
    == falseVisibleEventsPerMinute.eventCount
```

Ebből két KÖTELEZŐ cella: (a) `onset`-fajta hamis látható esemény NÉLKÜLI
fixture-ön a két szűkített darabszám összege **pontosan** az agnosztikus
`eventCount`; (b) `onset`-fajta hamis látható eseményt IS tartalmazó
fixture-ön az összeg **szigorúan kisebb**, és
`falseVisibleDirectionEventsPerMinute.value != falseVisibleEventsPerMinute.value`.
A (b) cella az anti-`L549` bizonyíték: enélkül egy egyszerű átcímkézés is
zölden átmenne.

**D5. Extractor nélkül nincs metrika.** Mindkét ráta bekerül a
`recognitionMetricExtractors`-ba
(`falseVisibleDirectionEventsPerMinute.value`,
`falseVisibleChordEventsPerMinute.value`), az irányt kizárólag a metrika SAJÁT
`definition.higherIsBetter`-éből olvasva (ADR 0511 D2 — külön karbantartott
irány-konstans tilos).

**D6. A szállított küszöbfájl VÁLTOZATLAN.** A
`recognition_release_gate.json` bejegyzés-listáját pinnelő cella
MÓDOSÍTÁS NÉLKÜL zöld marad. A Ch14 §7.2 sor a kör után is az agnosztikus
rátán áll; az átkötés külön kör külön ADR-rel (ADR 0511 D9).

**D7. A hard-negative taxonómia gépi lista + típusos validátor.** A
`evaluation/recognition/negative_taxonomy.json` legalább **10** kategóriát
sorol fel; a `negative_taxonomy.dart` típusos modellt és validátort ad.
Ismeretlen kategória a kör SAJÁT `Exception`-alosztályát dobja (`kind` mezővel),
NEM `other`-be sorolást és NEM bare `ArgumentError`/`StateError`-t — az
„ismeretlen → gyűjtőkategória" némán rontja el a későbbi kategória-bontást.

**D8. Nyers audio nem kerül a repóba (ADR 0249 megerősítése).** A fixture
szintetikus vagy annotáció-only; a tényleges 60 perc negatív anyag külső,
kézi munkafolyam, amit a `docs/eval/recognition-hard-negatives.md` ír le és a
manifest tart nyilván.

**D9. A dashboard „deliberately absent" listájából PONTOSAN KETTŐ zárul.** A
`docs/eval/recognition-dashboard.md` D8-szakasza a kör után a
„false visible arrow hard-negative" és a „false confident chord
hard-negative" sorokat gépiesítettként vezeti fel; a szakasz saját
darabszám-szava a maradékkal EGYÜTT írandó át. A maradó sorok:
**accepted direction accuracy**, **weakest supported chord recall**,
**confirmed chord accepted accuracy**, **chord transition p50** — ezek
accuracy/recall/latency-szűkítések, amiket EZ a kör nem ad meg.

## Következmények

- Az E14-R10 abstention-köre IRÁNY-szinten bizonyíthatóvá válik: van olyan
  ráta, amely csak a hamis NYILAKAT számolja.
- A kategória manifest-hordozása és a metrika kategória-bontása **nem** ebben a
  körben történik: ahhoz a `RecognitionCase` és a
  `baseline_manifest_schema.json` bővülne, ami ADR 0354 szerint reviewed
  evidencia-artefaktum → külön kör, saját ADR-rel.
- A `sourceId` group-key / klip-leakage gépiesítése szintén külön kör: a
  `GroupKey` (`recognition_split.dart:18`) bővítése kimerítő `switch`-eket, a
  manifest-sémát és a renderer csoport-celláit is mozgatja.

## Mérce

A kör `gate_tests` négyese: `negative_taxonomy_test.dart` (D7 — 9/10/11
kategóriás hármas a küszöb köré, típusos hiba ismeretlen kategóriára),
`recognition_metrics_test.dart` (D1–D4 — 3 hamis irány-esemény / 120 s →
1,5/perc; abstained esemény kizárása → 1,0/perc; zárt partíció; anti-alias),
`recognition_release_gate_test.dart` (D5–D6 — extractor-kulcsok +
a küszöbfájl-pin MÓDOSÍTÁS NÉLKÜL zöld),
`recognition_report_renderer_test.dart` (D5 — a két új sor mindhárom
renderelésben, azonos értékkel).

A falszifikáció dokumentált: az `accepted` szűrés kikapcsolásával a
`1,0/perc` cella PIROS, a `kind` szűrés „minden fajtá"-ra rontásával az
anti-alias cella PIROS.
