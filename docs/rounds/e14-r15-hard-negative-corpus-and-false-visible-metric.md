# E14-R15 — Hard-negative taxonómia és SZŰKÍTETT false-visible-event metrika

- **Státusz:** REVISED (ADR 0112 önjavító kör, 2026-09-05 — mért alap: `main @ 8180c9dc`;
  az eredeti előre-írás 2026-08-20, `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 15 — a „strum onset + direction recovery" blokk (SDD §8: R15–R24) nyitó köre
- **Kör-azonosító:** `E14-R15`
- **Branch:** `<motor>/e14-r15-hard-negative-corpus-and-false-visible-metric`
- **Előfeltétel:** `E14-R08` (ADR 0509 — a harness, amit a metrika KITERJESZT),
  `E14-R09` (ADR 0511 — a dashboard és a release-kapu szerződése) és
  `E14-R07` (annotációs szerződés, amivel a negatív anyag címkézhető) — mind merge-elve.
- **Brief szerzője:** Claude (Opus 5) · **revízió:** ADR 0112 önjavító kör
- **Előre kiosztott ADR:** `0521` (foglaló: `tools/round-slots.py reserve-adr --round E14-R15`,
  marker `.pipeline/inflight/adr/0521`) — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**
  A 2026-08-20-i előre-írás `0367`-et mondott; az a szám elavult (lásd §0.0).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a §0.0 revíziót, majd
> a `lib/features/live/domain/evaluation/recognition_metrics.dart`
> `computeRecognitionMetrics` végét (`falseVisibleEventsPerMinute`, ~731–746) és
> a `docs/eval/recognition-dashboard.md` „Four Ch14 Alpha lines" szakaszát
> (ADR 0511 D8). Ez a kör azt a szakaszt zárja le — nem ír mellé második
> metrikát. Eltérésnél `stopped` jelzés, nem improvizáció.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "evaluation/recognition/negative_taxonomy.json",
  "evaluation/recognition/fixtures/negative_taxonomy_sample.json",
  "lib/features/live/domain/evaluation/negative_taxonomy.dart",
  "lib/features/live/domain/evaluation/recognition_metrics.dart",
  "lib/features/live/domain/evaluation/recognition_release_gate.dart",
  "lib/features/live/public.dart",
  "test/features/live/evaluation/negative_taxonomy_test.dart",
  "test/features/live/evaluation/recognition_metrics_test.dart",
  "test/features/live/evaluation/recognition_release_gate_test.dart",
  "test/features/live/evaluation/recognition_report_renderer_test.dart",
  "docs/eval/recognition-hard-negatives.md",
  "docs/eval/recognition-dashboard.md",
  "docs/rounds/e14-r15-hard-negative-corpus-and-false-visible-metric.md",
]
gate_tests = [
  "test/features/live/evaluation/negative_taxonomy_test.dart",
  "test/features/live/evaluation/recognition_metrics_test.dart",
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

## 0.0 Revízió — MÉRT tények (ADR 0112 önjavító kör, 2026-09-05, `main @ 8180c9dc`)

A brief 2026-08-20-án készült; azóta a mért alapja elmozdult (`brief-lint` **S15**),
és a kör az eredeti alakjában **H3**-mal megállt még dispatch ELŐTT. A mérés
(reprodukálható parancsokkal, `.pipeline/halt-detail-E14-R15.md`):

| Amit a régi brief állított | MA mért igazság |
|---|---|
| „A termék oldalán nincs a MEGMUTATOTT hamis eseményeket számoló metrika" | **HAMIS.** `recognition_metrics.dart:731–746` — `falseVisibleEventsPerMinute` merge-elve (E14-R08 / ADR 0509) |
| a metrika ÚJ, különálló fájlba kerül (`false_visible_event_metric.dart`) | **TILOS.** ADR 0511 D8 (`docs/eval/recognition-dashboard.md`) kimondja: a szűkített változatot a **`recognition_metrics.dart` kiterjesztésével** kell megépíteni; a mellé írt második definíció pontosan az `L549` hibaosztály |
| a Ch14 §7.2 „false visible arrow" sor még nincs kapuzva | **HAMIS.** `evaluation/recognition/recognition_release_gate.json:36–39` — 2,0/perc küszöb, `event-kind-agnostic` címkével (E14-R09 / ADR 0511) |
| a 6. acceptance-pont `sourceId`-leakage-et kér | **TELJESÍTHETETLEN ITT.** `GroupKey` = `{player, device, guitar, room}` (`recognition_split.dart:18`), a `RecognitionCase`-ben nincs `sourceId`, és a `GroupKey` bővítése kimerítő `switch`-eket, a manifest-sémát és a renderer csoport-celláit is mozgatja → **külön kör, saját ADR-rel** |
| előre kiosztott ADR `0367` | **ELAVULT.** a foglaló `0521`-et ad; az E14 sáv valós ADR-jei `0505`/`0509`/`0511`/`0518` körül járnak (ugyanez mérve az E14-R12-nél: sor `0364`, valós `0518`) |

**A kör EGYETLEN döntési helye ezért:** a merge-elt
`recognition_metrics.dart` report-fája. A kör **kiterjeszti** azt két, valóban
szűkített rátával, és ezzel az ADR 0511 D8 „deliberately absent" listájából
kettőt lezár. Nem épít párhuzamos metrika-fát, nem köti át a release-kaput.

**A revízió által a körből KIVETT munka (külön körbe tartozik, saját ADR-rel):**

1. **`sourceId` group-key + klip-leakage gépiesítése** — a merge-elt
   `GroupKey`/`SplitStrategy`/manifest-séma bővítése (a régi 6. acceptance-pont).
2. **A taxonómia-kategória manifest-hordozása** és a metrika kategória-bontása —
   ehhez a `RecognitionCase` és a `baseline_manifest_schema.json` bővülne, ami
   ADR 0354 szerint reviewed evidencia-artefaktum.
3. **A Ch14 §7.2 sor átkötése** az agnosztikus rátáról a szűkítettre a
   `recognition_release_gate.json`-ban — ADR 0511 D9 szerint az a fájl reviewed
   artefaktum, az átkötés ADR-döntés, nem mellékhatás.

## 0.0.1 Kiegészítő pre-flight mérés (2026-09-05, `main @ b17e08ef`, orchestrátor)

A dispatch előtti újramérés három ponton pontosítja a fentieket. Mindhárom a
kör SAJÁT, még nem merge-elt artefaktumát érinti (ADR 0087 §2), tehát
brief-revízió, nem H3.

1. **A renderer forrása NEM a `domain/` alatt van, és nem is kell módosítani.**
   A §2 „`recognition_report_renderer.dart:62`" hivatkozás tényleges útvonala
   `lib/features/live/data/evaluation/recognition_report_renderer.dart`. A
   `_summarize` (`:59–73`) **generikusan** a `recognitionMetricExtractors`
   rendezett kulcslistáján megy végig — nincs benne kipinnelt metrika-névsor.
   Ezért a renderer FORRÁSA szándékosan nincs az `allowed_paths`-on: az
   extractor-bejegyzés önmagában megjeleníti a metrikát mindhárom
   renderelésben. Csak a renderer TESZTJE van a listán (a 7. acceptance-pont
   új sorai miatt).

2. **A `recognition-dashboard.md` „deliberately absent" szakasza a fejlécében
   „Four"-t mond, de HAT nevesített Ch14 Alpha sort sorol fel** (a 106–144.
   sorok: accepted direction accuracy, false visible arrow hard-negative,
   weakest supported chord recall, confirmed chord accepted accuracy, chord
   transition p50, false confident chord hard-negative). A §8/4. lépés
   szövegének „a maradék kettő" állítása ezért **pontatlan**: ez a kör
   PONTOSAN KETTŐT zár le (a két hard-negative sort), és utána **négy** marad
   — accepted direction accuracy, weakest supported chord recall, confirmed
   chord accepted accuracy, chord transition p50 —, mert azok accuracy-,
   recall- és latency-szűkítések, amiket ez a kör nem ad meg. A szakasz saját
   darabszám-szavát a maradék listával EGYÜTT kell átírni (ADR 0521 D9). A két
   hard-negative sor lezárása a lista tartalmi állítását is helyesbíti: a
   „substitution is exactly the L549 failure class" mondat érvényben marad, de
   e két sorra már nem helyettesítés, hanem valódi, szűkített metrika felel.

3. **Az ADR-szám `0521`, és a foglaló NEM idempotens.** A
   `.pipeline/inflight/adr/0521` marker tartalma `round=E14-R15` (a revíziós
   önjavító kör foglalta le), a queue-sor is `0521`. A pre-flightban futtatott
   `tools/round-slots.py reserve-adr --round E14-R15` ettől függetlenül ÚJ
   számot (`0523`) adott — a foglaló a körazonosítót csak beleírja a markerbe,
   nem keresi vissza. A fölösleges `0523` marker azonnal fel lett szabadítva; a
   kör ADR-je a `docs/adr/0521-scoped-false-visible-event-rates-and-hard-negative-taxonomy.md`.

**Amit a mérés MEGERŐSÍTETT (nem változott):** a `RecognitionMetrics` két
konstrukciós helye (`recognition_metrics.dart:797` és
`recognition_release_gate_test.dart:413`) MINDKETTŐ az `allowed_paths`-on van,
tehát a két új kötelező mező felvétele nem lép ki a listából; a
`recognitionMetricExtractors` kulcshalmazát a körön KÍVÜL egyetlen teszt sem
pinneli; a partíció zártsága a merge-elt `correctAccepted` / `acceptedDetections`
párból következik (`:676–689`), új adat nélkül.

## 0.1 Kötött scope-szűkítés a SDD-hez képest (drift, KÖTELEZŐ így)

A SDD Kör 15 „legalább 60 perc negatív anyagot" is kér. **Hangfelvétel nem
kerül a repóba** (ADR 0249 óta álló határ), és a felvételt a `E14-R06`
consent-kapuja végzi — ezért ez a kör a **taxonómiát, a capture-listát, a
manifest-szerződést és a termék-oldali metrikát** adja; a tényleges 60 perc
külső, kézi munkafolyam, amit a `docs/eval/recognition-hard-negatives.md`
ír le és a manifest tart nyilván. A kör acceptance-e a repóban ellenőrizhető
részre vonatkozik.

## 1. Cél

1. Legyen a terméknek **valóban szűkített** gépi fogalma arról, mennyi hamis
   eseményt mutat a felhasználónak **eseményfajtánként**:
   `false visible **direction** event / min` és
   `false visible **chord** event / min` — a merge-elt, eseményfajta-agnosztikus
   `falseVisibleEventsPerMinute` UGYANAZON report-fájában, annak partícionálásaként.
   Ezzel az ADR 0511 D8 négy „deliberately absent" Ch14 Alpha sorából kettő
   („false visible arrow hard-negative", „false confident chord hard-negative")
   gépiesíthetővé válik.
2. Legyen legalább tíz kategóriás hard-negative **taxonómia** (beszéd, taps,
   asztalkoppanás, pengető-kattintás, húrzaj, fret squeak, metronóm,
   háttérzene, tévé, ventilátor, telefonmozgatás), amellyel a negatív anyag
   címkézhető — gépi listaként és típusos validátorral.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **`ml/negatives.py` (r174):** a mért gyökérok — a confidence önmagában NEM
  szűri a zajt, mert a modell a hamis onsetre is magabiztos. Ezért kell külön
  no-strum osztály ÉS termék-oldali hamis-esemény metrika.
- **ADR 0249:** nyers audio nem kerül a repóba — a manifest igen.
- **ADR 0509 (E14-R08):** a report-fa, a `correctAccepted` halmaz és az
  `accepted` (nem abstained) szűrés — a kör ezekre épít, nem melléjük.
- **ADR 0511 D8 (E14-R09):** a szűkített metrika helye kimondva
  `recognition_metrics.dart`; az azonos nevű, más hatókörű metrika
  helyettesítése az `L549` hibaosztály.
- **E14-R10:** az abstention csökkenti a hamis nyilakat; ez a kör adja azt a
  mérőszámot, amivel ez IRÁNY-szinten bizonyítható.

## 2. Jelenlegi állapot — mért tények (`main @ 8180c9dc`)

- `lib/features/live/domain/evaluation/recognition_metrics.dart`
  - `enum RecognitionEventKind { onset, strum, chord }` (24. sor);
  - `computeRecognitionMetrics` a `correctAccepted` halmazból és az
    `acceptedDetections` listából számolja a
    `falsePositiveAcceptedCount = acceptedDetections.length - correctAcceptedCount`
    értéket, majd `durationMinutes = totalDurationMs / 60000`-rel osztja
    (~684–746). A szűkítéshez tehát **nincs szükség új adatra**: az
    eseményfajta már a `RecognitionDetectedEvent.kind`-ben ott van.
- `lib/features/live/domain/evaluation/recognition_release_gate.dart:60` —
  `recognitionMetricExtractors`: minden nevezhető metrika-út innen jön (ADR 0511 D2:
  az irány MINDIG a metrika saját `definition.higherIsBetter`-éből, sosem külön
  konstansból). A `recognition_report_renderer.dart:62` ezt a kulcshalmazt
  rendereli mindhárom formátumban.
- `evaluation/recognition/recognition_release_gate.json` — a szállított
  küszöbfájl; a `recognition_release_gate_test.dart` a TELJES bejegyzés-listáját
  pinneli (~251–266). Ez a kör **nem** módosítja (§0.0/3).
- `ml/negatives.py` — a tanító oldal hard-negative bányászata LÉTEZIK; a
  fejléce rögzíti a ~1/6 hamis onset arányt és a 0,94/0,97 medián
  confidence-párt. Ez a kör nem írja át.
- `evaluation/recognition/` — létezik (`README.md`, sémák, `fixtures/`); a
  taxonómia ide kerül.

## 3. Scope

**Benne:** taxonómia (JSON + Dart validátor + fixture + doksi), capture-lista,
két SZŰKÍTETT hamis-esemény ráta a merge-elt report-fában, a hozzájuk tartozó
extractor-bejegyzések, a dashboard „deliberately absent" listájának igazra
hozása.

**Nincs benne:** hangfájl a repóban, modelltanítás, DSP-konstans, a
`ml/negatives.py` átírása, UI, a `recognition_release_gate.json` küszöbeinek
átkötése, a `GroupKey`/`sourceId` bővítés, a manifest-séma bővítése.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `evaluation/recognition/negative_taxonomy.json` | a tíz+ kategória gépi listája |
| `evaluation/recognition/fixtures/negative_taxonomy_sample.json` | CI-fixture (annotáció-only) |
| `lib/features/live/domain/evaluation/negative_taxonomy.dart` | taxonómia-modell + típusos validátor (ÚJ fogalom, nincs merge-elt megfelelője) |
| `lib/features/live/domain/evaluation/recognition_metrics.dart` | a két SZŰKÍTETT ráta — ADR 0511 D8 kimondott helye |
| `lib/features/live/domain/evaluation/recognition_release_gate.dart` | a két új metrika-út felvétele a `recognitionMetricExtractors`-ba |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/evaluation/negative_taxonomy_test.dart` | taxonómia-cellák |
| `test/features/live/evaluation/recognition_metrics_test.dart` | a metrika-mátrix cellái |
| `test/features/live/evaluation/recognition_release_gate_test.dart` | a `_metrics` segéd új mezői + extractor-cella |
| `test/features/live/evaluation/recognition_report_renderer_test.dart` | a három formátum új metrika-sora |
| `docs/eval/recognition-hard-negatives.md` | taxonómia + capture-lista + külső workflow |
| `docs/eval/recognition-dashboard.md` | az ADR 0511 D8 „deliberately absent" lista igazra hozása |
| `docs/rounds/e14-r15-hard-negative-corpus-and-false-visible-metric.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `evaluation/recognition/recognition_release_gate.json`,
`lib/features/live/domain/evaluation/recognition_split.dart`,
`evaluation/recognition/baseline_manifest*.json`, `ml/**`, `assets/**`,
`lib/features/live/engine/**`, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

**A meglévő tesztfájlokban (`recognition_metrics_test`,
`recognition_release_gate_test`, `recognition_report_renderer_test`) KIZÁRÓLAG
ÚJ cella adható hozzá, illetve a `_metrics` segéd bővíthető az új kötelező
mezőkkel. Meglévő cella törlése, `skip`-elése vagy elvárt értékének lazítása a
kör bukása** (AGENTS.md §12, a mérce-őrszem a teszt-cellák számát is méri).

## 5. Kötött architekturális döntések (ADR 0521)

### 5.1 A szűkített metrika a MERGE-ELT metrika partíciója, nem második definíciója

A két új ráta a `RecognitionMetrics`-be kerül, ugyanabban a
`computeRecognitionMetrics` menetben, ugyanabból a `correctAccepted` halmazból
és ugyanazzal a `durationMinutes` nevezővel, mint a merge-elt
`falseVisibleEventsPerMinute`:

- `falseVisibleDirectionEventsPerMinute` — `accepted && kind == RecognitionEventKind.strum && !correctAccepted`;
- `falseVisibleChordEventsPerMinute` — `accepted && kind == RecognitionEventKind.chord && !correctAccepted`.

**NEM elfogadható:** külön fájlban élő, saját nevezővel/saját elfogadás-fogalommal
dolgozó második metrika (`false_visible_event_metric.dart`) — ez az `L549` /
ADR 0511 D8 hibaosztály, és pontosan ezért állt meg a kör az eredeti alakjában.

### 5.2 A metrika a MEGMUTATOTT eseményt számolja

A `false visible event` az, amit a felhasználó ténylegesen látott
(`accepted == true`). Az abstained (`accepted == false`) detektálás **soha** nem
hamis pozitív — ez a merge-elt szerződés (ADR 0509), a kör nem definiálja újra.
**NEM elfogadható**: a modell nyers kimenetének számolása.

### 5.3 Percre normalizált, nem eseményre

Az érték `esemény / perc`; a nevező a `totalDurationMs / 60000`, azaz a
kiértékelt anyag hossza — ugyanaz, mint az agnosztikus rátáé. `durationMinutes == 0`
esetén az érték `null` (a merge-elt viselkedés), nem `0`.

### 5.4 A partíció ÖSSZEGE zárt, és a szűkített ráta NEM alias

`onset + strum + chord` a `RecognitionEventKind` teljes partíciója, ezért
a három fajta hamis-esemény darabszámának összege **pontosan** az agnosztikus
`falseVisibleEventsPerMinute.eventCount`. Ebből két kötelező következmény:

- olyan fixture-ön, ahol csak `strum` és `chord` fajtájú hamis látható esemény
  van, `direction.eventCount + chord.eventCount == agnosztikus.eventCount`;
- olyan fixture-ön, ahol `onset` fajtájú hamis látható esemény IS van, az összeg
  **szigorúan kisebb** az agnosztikusnál. Ez az anti-`L549` cella: bizonyítja,
  hogy a szűkített ráta nem az agnosztikus átcímkézése.

### 5.5 A metrika NEVEZHETŐ — extractor nélkül nincs metrika

Mindkét új ráta bekerül a `recognitionMetricExtractors`-ba
(`falseVisibleDirectionEventsPerMinute.value`,
`falseVisibleChordEventsPerMinute.value`), az irányt a metrika SAJÁT
`definition.higherIsBetter`-éből olvasva (ADR 0511 D2). Enélkül a metrika nem
jelenik meg a report három renderelésében és nem hivatkozható küszöbfájlból.

**A szállított `recognition_release_gate.json` küszöbei VÁLTOZATLANOK.** A Ch14
§7.2 sor a kör után is az agnosztikus rátán áll; az átkötés külön kör külön
ADR-rel (ADR 0511 D9 — reviewed artefaktum).

### 5.6 Kategória kötelező — a taxonómiában

Minden negatív felvétel-szegmens pontosan egy taxonómia-kategóriát kap;
ismeretlen kategória **típusos hiba** (saját `Exception`-alosztály), nem
`other`-be söprés és nem bare `ArgumentError`/`StateError`. A kategória
manifest-hordozása és a metrika kategória-bontása külön kör (§0.0).

### 5.7 Nyers audio nem kerül a repóba

A manifest hivatkozik, nem tartalmaz. **NEM elfogadható**: „csak egy rövid
minta a fixture-höz" — a fixture szintetikus vagy annotáció-only.

## 6. Acceptance criteria

1. A taxonómia legalább **10** kategóriát tartalmaz: a hármas cella a határra —
   a küszöb **alatt** (9 kategória) a validátor hibát ad, pontosan **rajta**
   (10) elfogadott (a határ inkluzív), a küszöb **fölött** (11) elfogadott.
2. Ismeretlen kategória a fixture-annotációban **típusos** hibát ad (a kör saját
   `Exception`-alosztálya, `kind`-del), nem `other`-be sorolást és nem bare
   `StateError`-t.
3. `falseVisibleDirectionEventsPerMinute` kézzel ellenőrzött értéket ad: **3**
   megmutatott hamis IRÁNY-esemény **120 s** anyagon → **1,5 esemény/perc**.
4. `uncertain`/abstained (`accepted == false`) esemény NEM számít bele: ugyanaz
   a fixture, a három esemény egyike `accepted: false` → **1,0 esemény/perc**.
5. **Partíció-cella (5.4):** olyan fixture-ön, amelyen `strum` és `chord`
   fajtájú hamis látható esemény is van,
   `falseVisibleDirectionEventsPerMinute.eventCount +
   falseVisibleChordEventsPerMinute.eventCount ==
   falseVisibleEventsPerMinute.eventCount`.
6. **Anti-alias cella (5.4):** ugyanaz a fixture egy hamis, elfogadott `onset`
   fajtájú eseménnyel kiegészítve — a két szűkített darabszám összege
   **szigorúan kisebb**, mint az agnosztikus `eventCount`, és a
   `falseVisibleDirectionEventsPerMinute.value != falseVisibleEventsPerMinute.value`.
7. **Nevezhetőség (5.5):** mindkét új metrika-út szerepel a
   `recognitionMetricExtractors` kulcsai között, az `higherIsBetter` értéke a
   metrika saját definíciójából jön (`false`), és a két metrika sora megjelenik
   a report **mindhárom** renderelésében (JSON, Markdown, HTML) azonos értékkel.
8. **A küszöbfájl változatlan:** a `recognition_release_gate_test.dart` meglévő,
   a szállított `recognition_release_gate.json` bejegyzés-listáját pinnelő
   cellája MÓDOSÍTÁS NÉLKÜL zöld.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A nyers modell-kimenetet (abstained is) számolja | 4. pont |
| Eseményre normalizál, nem percre | 3. pont `1,5` cellája |
| A szűkített ráta valójában az agnosztikus átcímkézése (`L549`) | 6. pont |
| A partíció nem zárt (kimarad egy fajta / duplán számol) | 5. pont |
| Ismeretlen kategória → `other` | 2. pont |
| 9 kategóriás taxonómiát elfogad | 1. pont „pontosan rajta" cellája |
| A metrika nem kerül be az extractor-térképbe (nem nevezhető, nem renderelődik) | 7. pont |
| A kör „egyszerűsítésként" átköti a Ch14 §7.2 küszöböt | 8. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation/negative_taxonomy_test.dart test/features/live/evaluation/recognition_metrics_test.dart test/features/live/evaluation/recognition_release_gate_test.dart test/features/live/evaluation/recognition_report_renderer_test.dart
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: az `accepted == false` szűrés ideiglenes kikapcsolásával
a 4. pont **PIROS**, visszaállítva **ZÖLD**; továbbá a `kind` szűrés
`RecognitionEventKind.strum`-ról „minden fajtá"-ra rontásával a 6. pont
**PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `negative_taxonomy.json` + `negative_taxonomy.dart` (modell + típusos
   validátor) + fixture + cellák (1–2. acceptance).
2. A két szűkített ráta a `recognition_metrics.dart`-ban + a 3–6. cella.
3. Extractor-bejegyzések (`recognition_release_gate.dart`) + a 7–8. cella
   (gate- és renderer-teszt).
4. `public.dart` export; doksi: capture-lista és a külső (repón kívüli)
   workflow (`recognition-hard-negatives.md`), valamint a
   `recognition-dashboard.md` „deliberately absent" listájából a két lezárt sor
   átvezetése (§0.0.1/2 és ADR 0521 D9: a lezárt kettő a „false visible arrow
   hard-negative" és a „false confident chord hard-negative"; a listán MARAD
   NÉGY — „accepted direction accuracy", „weakest supported chord recall",
   „confirmed chord accepted accuracy", „chord transition p50" —, és a szakasz
   fejlécének darabszám-szava ezzel EGYÜTT írandó át).

## 9. Kockázatok

- **Hangfájl-szivárgás:** az 5.7 tiltja; a review a diffben grepeli a
  bináris kiterjesztéseket.
- **Második definíciós hely (`L549`):** az 5.1 és a 6. acceptance-pont zárja ki;
  ez a kockázat MÉRT — az eredeti brief pontosan ebbe futott bele (§0.0).
- **A küszöbfájl néma átkötése:** a 8. acceptance-pont és a tilos zóna zárja ki.
- **Duplikáció az `ml/negatives.py`-vel:** a kör termék-oldali metrikát ad,
  nem tanító-oldali bányászatot; az `ml/**` tilos zóna.
- **Scope-túlnyúlás a `GroupKey`/manifest felé:** a §0.0 kiveszi a körből; ha az
  implementer úgy találja, hogy egy cella csak ezekkel teljesíthető → `stopped`.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5). **Státusz:** `done`.

### Mit épített

1. **Hard-negative taxonómia** — `evaluation/recognition/negative_taxonomy.json`
   (schemaVersion `"1"`, 11 kategória: `speech`, `tapping`, `deskKnock`,
   `pickClick`, `stringNoise`, `fretSqueak`, `metronome`, `backgroundMusic`,
   `tv`, `fan`, `phoneHandling`) + a típusos modell/validátor
   `lib/features/live/domain/evaluation/negative_taxonomy.dart`-ban
   (`NegativeTaxonomy`, `NegativeTaxonomyCategory`, `NegativeTaxonomySample`,
   `NegativeTaxonomySegment`, `NegativeTaxonomyParser`,
   `NegativeTaxonomyException` a `NegativeTaxonomyErrorKind` enummal —
   `malformedValue`, `missingField`, `unknownField`, `unknownSchemaVersion`,
   `tooFewCategories`, `duplicateCategoryId`, `unknownCategory`). A ≥10-es
   küszöb `NegativeTaxonomy` konstruktorában van (inkluzív határ), az
   ismeretlen-kategória hiba `NegativeTaxonomy.categoryById` / a
   `parseSample` segéd hívja. CI-fixture:
   `evaluation/recognition/fixtures/negative_taxonomy_sample.json` (11
   szegmens, mindegyik `sourceRef`-fel a repón kívüli anyagra mutat, nincs
   hangfájl).
2. **A két szűkített ráta** — `RecognitionMetrics` két új mezőt kapott
   (`falseVisibleDirectionEventsPerMinute`, `falseVisibleChordEventsPerMinute`,
   mindkettő `RecognitionRateMetric`), a `computeRecognitionMetrics` UGYANAZON
   menetében, a meglévő `correctAccepted`/`acceptedDetections`
   halmazokból, `kind`-szerinti szűréssel (ADR 0521 D1–D4). A meglévő
   `falseVisibleEventsPerMinute` számítása és mezője változatlan.
3. **Extractor-bejegyzések** — `recognitionMetricExtractors`
   (`recognition_release_gate.dart`) két új kulcsot kapott
   (`falseVisibleDirectionEventsPerMinute.value`,
   `falseVisibleChordEventsPerMinute.value`), az irány mindkettőnél a
   metrika saját `definition.higherIsBetter`-éből jön. A renderer forrását
   (`recognition_report_renderer.dart`) NEM módosítottam — a §0.0.1/1 mérés
   szerint generikus, kulcslista nélküli, ezért a két új sor automatikusan
   megjelenik mindhárom formátumban.
4. **`public.dart`** — additív export:
   `export 'domain/evaluation/negative_taxonomy.dart';`.
5. **Doksi** — új `docs/eval/recognition-hard-negatives.md` (taxonómia +
   capture-lista + a repón kívüli, kézi 60 perces workflow leírása);
   `docs/eval/recognition-dashboard.md` „deliberately absent” szakasza
   frissítve — a „false visible arrow hard-negative” és a „false confident
   chord hard-negative” sor most `## Now mechanised (ADR 0521)` alatt van
   dokumentálva a két új metrika-úttal, a maradék NÉGY sor (accepted
   direction accuracy, weakest supported chord recall, confirmed chord
   accepted accuracy, chord transition p50) a „still … deliberately absent”
   bekezdésben maradt, a „Four” szó immár ténylegesen pontos.

### Amit szándékosan NEM érintettem

- `evaluation/recognition/recognition_release_gate.json` — változatlan (8.
  acceptance, a pinnelt teszt módosítás nélkül zöld).
- `recognition_report_renderer.dart` forrása — nem az allowed-listán, és a
  §0.0.1/1 mérés szerint nem is szükséges hozzá módosítás.
- A `GroupKey`/`sourceId`/manifest-séma bővítés és a taxonómia-kategória
  manifest-hordozása — a §0.0 kifejezetten kiveszi a körből.

### Falszifikáció (§7.1, ténylegesen lefuttatva és visszaállítva)

1. Az `acceptedDetections` szűrőjéből ideiglenesen kivettem a `d.accepted`
   feltételt (`.where((d) => true)`). Eredmény:
   `flutter test test/features/live/evaluation/recognition_metrics_test.dart`
   — a 4. acceptance cellája (**„abstaining one of the three -> 1.0/min"**)
   **PIROS** lett (`Expected: <2> Actual: <3>`), és vele együtt három
   meglévő cella is (`accepted accuracy`, `coverage`,
   `false visible events/min` — ugyanaz a gyökér-adat). Visszaállítás
   után (`d.accepted` visszatéve) a teljes fájl **ZÖLD** (37/37), és a
   `git diff --stat` üres — a forrás bájt-azonos a commitolt állapottal.
2. A `falseVisibleDirectionCount` szűrőjéből ideiglenesen kivettem a
   `d.kind == RecognitionEventKind.strum` feltételt (`true &&` maradt csak).
   Eredmény: a **6. (anti-alias) cella PIROS** lett
   (`Expected: a value less than <5> Actual: <7>`), és vele együtt az **5.
   (zárt partíció) cella is PIROS** — pontosan az L549 hibaosztály, amit a
   cella bizonyítani hivatott. Visszaállítás után a fájl ismét **ZÖLD**
   (37/37), `git diff --stat` üres.

### Gate — a mért eredmény

```
tools/round-gate.sh test/features/live/evaluation/negative_taxonomy_test.dart test/features/live/evaluation/recognition_metrics_test.dart test/features/live/evaluation/recognition_release_gate_test.dart test/features/live/evaluation/recognition_report_renderer_test.dart
```

`format` → ZÖLD, `analyze` → ZÖLD, mind a négy célzott teszt → ZÖLD
(11/37/18/13 zöld cella soronként), `architecture` → ZÖLD, `secrets` → ZÖLD,
`l10n` → ZÖLD. **MINDEN GATE ZÖLD.**

### Amit a review-nak látnia kell

- A négy tesztfájl közül háromban (`recognition_metrics_test.dart`,
  `recognition_release_gate_test.dart`, `recognition_report_renderer_test.dart`)
  kizárólag ÚJ `group`/`test` cellák kerültek be, egyetlen meglévő cella
  szövege/elvárása sem változott; a `_metrics` segéd
  (`recognition_release_gate_test.dart`) két új opcionális paramétert kapott
  `_rate()` alapértelmezéssel.
  `negative_taxonomy_test.dart` teljes egészében új fájl.
- A taxonómia-JSON és a fixture tartalma (kategória-nevek, leírások,
  szegmens-számok) design-döntés, nem mért érték — a review szabadon
  finomíthatja, amíg a ≥10-es darabszám és a típusos hiba-szerződés áll.

## 11. Review — a Claude tölti ki

**Jelentés:** [`docs/reviews/e14-r15-review.md`](../reviews/e14-r15-review.md)
(2026-09-05, reviewelt HEAD `e180c0d2`).

**Verdikt: APPROVED** — 0 BLOCKER, 0 MAJOR, 1 MINOR, 2 NOTE. A nyolc
acceptance-pont mind teljesül; a scope-audit `ok` (13 fájl), a célzott gate a
reviewer saját izolált klónjában is végig zöld, és a §7.1 két falszifikációját
a reviewer FÜGGETLENÜL is reprodukálta (a `d.accepted` szűrés kivételével a
4. cella, a `kind == strum` szűrés kivételével az 5. és 6. cella megy pirosra).

**Nyitva marad (nem blokkol):** MINOR-1 — a `NegativeTaxonomyParser`
doc-commentje „minden elutasítás típusos"-t állít, de az üres mezőérték és a
`endMs < startMs` a parse úton bare `ArgumentError`-t dob (L630 osztály).
Javítási irány a jelentésben; a következő körök asztalára a HANDOFF §6 viszi.
