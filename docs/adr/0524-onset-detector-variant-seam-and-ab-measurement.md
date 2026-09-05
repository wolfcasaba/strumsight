# ADR 0524 — Onset-detektor variáns-szeám és A/B mérés: a pontosságot a MERGE-ELT felismerési szerződés pontozza, a gépfüggő idő nem a determinisztikus riport része

- **Státusz:** Elfogadva
- **Kör:** `E14-R16` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 16)
- **Dátum:** 2026-09-05
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [ADR 0509](0509-grouped-recognition-evaluation-and-leakage-protection.md)
  (a felismerési metrika-fa: inkluzív tűrés, Kuhn-féle maximális párosítás,
  `null` ≠ `0`, a definíció a számmal utazik — ez a kör ERRE épül),
  [ADR 0511](0511-recognition-release-gate-and-single-source-report.md)
  (D5: egyetlen köztes modell, egyszeri kerekítés; a csoportosítás a
  dashboardé), [ADR 0521](0521-scoped-false-visible-event-rates-and-hard-negative-taxonomy.md)
  (ugyanez a minta: a merge-elt harness KITERJESZTÉSE, nem második fa),
  [ADR 0474](0474-benchmark-record-and-performance-budget-comparison.md)
  (a benchmark-szám `deviceId`+`buildSha` nélkül értelmetlen; a fal-óra
  gépfüggő), [ADR 0248](0248-analysis-cache-key-and-performance-budget.md)
  („a szám gépfüggő, nem merge-kapu"),
  [ADR 0249](0249-analysis-evaluation-dataset-governance.md) (nyers audio nem
  kerül a repóba), [L269](../LESSONS.md#l269) (a mohó párosítás nem maximális),
  [L549](../LESSONS.md#l549), [L636](../LESSONS.md#l636), [L645](../LESSONS.md#l645)

## Kontextus — a pre-flight MÉRT tényei (2026-09-05, `main @ 1e235320`)

Az `E14-R16` briefje **2026-08-20-án, `main @ 6371aa3`-on** készült. A
`brief-lint` **S15** és **S12** fokot jelzett rá, és a mérés mindkettőt
igazolta: a brief alapja elmozdult. A hat döntő tény:

### 1. Az előre kiosztott `0368` szám elavult

`docs/adr/0368-*.md` nem létezik, az E14 sáv valós ADR-jei az `0505`/`0509`/
`0511`/`0518`/`0520`/`0521` tartományban járnak. A foglaló
(`tools/round-slots.py reserve-adr --round E14-R16`) a **`0524`** számot adta;
az `O_CREAT|O_EXCL` marker miatt ez az érvényes szám (a `ls docs/adr | tail`
alak sorszám-választásra kifejezetten tiltott). Ugyanez mérve az E14-R08-nál
(`0360` → `0509`) és az E14-R15-nél (`0367` → `0521`).

### 2. Az onset-pontozás szerződése MÁR MERGE-ELVE VAN

`lib/features/live/domain/evaluation/recognition_metrics.dart` (E14-R08,
ADR 0509) ma kimondja mindazt, amit a régi brief 1., 2., 3. és 6.
acceptance-pontja ÚJRA eldöntött volna:

```dart
const int onsetToleranceMsPrimary = 50;
const List<int> onsetTolerancesMs = [25, onsetToleranceMsPrimary, 100];
// …
matchingRule: "Kuhn's maximum-cardinality one-to-one matching, closest-gap-"
    'first candidate order, boundary inclusive (<=)',
```

- a tűrés-hármas (**25/50/100 ms**) konstansként él;
- a határ **inkluzív** (`<=`), és a párosítás **Kuhn-féle maximális** — épp
  azért, mert a mohó „legközelebbi szabad pár" mérhetően alulszámolja a
  találatokat ([L269](../LESSONS.md#l269));
- a nulla nevezőjű arány **`null`, sosem `0`** (ADR 0509 D6), és a
  renderer a `null`-t „nincs érték"-ként viszi tovább, nem kerekíti számmá
  (`recognition_report_renderer.dart:35-38`);
- a report **időbélyeg-mentes és determinisztikus**
  (`RecognitionEvaluationReport.toDeterministicJson`).

Egy második, a benchmark belsejében élő párosítás/tűrés/P-R-F1 tehát pontosan
az `L549`/`L636`/`L645` hibaosztály volna: két divergens definíció ugyanarra a
kérdésre, mindkettő zöld a saját cellái alatt.

### 3. A fában MÁR KETTŐ onset-párosító van — harmadik nem kell

`tool/benchmarks/real_audio_dsp_baseline.dart:matchOnsetsUs` (µs-alapú,
inkluzív, de NEM maximális párosítás) a régebbi, tool-lokális változat; a
merge-elt domain-szerződés a fenti. Ez a kör a **domain-szerződéshez**
delegál, és a régi tool-lokális párosítót **nem** módosítja és nem is hívja —
az más kör dolga (a fájl ennek a körnek tilos zónája).

### 4. A kör VALÓDI hiánya megvan

Nincs olyan futtatható artefaktum, amely **több onset-detektáló függvényt**
mérne ugyanazon a bemeneten: a `real_audio_dsp_baseline.dart` a szállított
pipeline EGY útját futtatja. A variáns-szeám és az A/B összemérés tehát nem
merge-elt döntés — **ez a kör egyetlen döntési helye**.

### 5. A determinizmus és a CPU-mérés ütközik — a régi 3. és 4. acceptance-pont

A régi brief egyszerre kérte, hogy a riport kétszeri futásra **bájtra azonos**
legyen (3. pont), és hogy **CPU-oszlopot** tartalmazzon (4. pont). A fal-óra és
a CPU-idő futásonként és gépenként változik (ADR 0248, ADR 0474) — a két
követelmény egy fájlban kielégíthetetlen.

### 6. A `public.dart` szándékosan NEM exportálja a DSP-motort

`lib/features/live/public.dart:3-7` merge-elt döntést hordoz: „a Live DSP/ML
motor (`engine/dsp/`, `engine/ml/`) szándékosan NINCS exportálva" (SDD Ch2
§10.3/10.4). A régi brief „additív export" sora tehát egy merge-elt döntést
írna felül. Mérve: a `tool/check_architecture.dart` kizárólag a `lib/` fát
vizsgálja (`Architecture check requires a lib/ directory`), a
`tool/benchmarks/real_audio_dsp_baseline.dart` pedig ma is közvetlenül importál
`package:strumsight/features/analyze/engine/clip_analyzer.dart`-ot — a
benchmarknak és a tesztjének **nincs szüksége** barrel-exportra.

### 7. Nincs commitolható audio-korpusz

`test/fixtures/audio/` 16 KB, kizárólag `song_trainer` anyaggal; nyers audio a
repóba nem kerül (ADR 0249). A `real_audio_dsp_baseline.dart` ezért külső
korpusz-könyvtárat vesz argumentumként, a tesztje pedig
(`test/tooling/real_audio_dsp_baseline_test.dart`) a tool-fájl **tiszta
függvényeit** hívja teszt-időben előállított adatokkal, fixture nélkül. Ez a
kör ugyanezt a mintát követi.

## Döntés

### D1 — A variáns-szeám új fájl, a szállított detektor egyetlen sora sem mozdul

`lib/features/live/engine/dsp/onset_detector_variant.dart` deklarál egy
`OnsetDetectorVariant` szeámot (`id`, `describe()`, és egy tiszta
„PCM → detektált onsetek" függvény), négy implementációval:

| Variáns-id | Mi ez |
|---|---|
| `current` | a SZÁLLÍTOTT `SuperFluxOnsetDetector`-t hívja, alapértelmezett konstansokkal — nem másolja, nem paraméterezi újra |
| `canonicalSuperFlux24` | Böck–Widmer SuperFlux a **24 sáv/oktáv** log-frekvenciás szűrősoron, ugyanazon az STFT-en |
| `complexDomain` | komplex-domain ODF (magnitúdó+fázis predikció) ugyanazon az STFT-en |
| `spectralFlux` | egyszerű félhullám-egyenirányított magnitúdó-flux |

A `superflux_onset_detector.dart` és a `dsp_config.dart` diffje a kör végén
**üres**; a live pipeline bekötése nem változik. A mérés eredménye **nem
jogosít** konstans-átállításra ebben a körben (AGENTS.md §9: shipping
DSP-konstans csak mért A/B **és ADR** után mozdul — ez a kör a mérést
szállítja, az átállítás külön kör külön ADR-rel).

### D2 — A három ÚJ variáns a szállított detektor PUBLIKUS hangoló-értékeit olvassa, nem gépeli újra

A közös csúcs-kiválasztó (adaptív küszöb + lokális maximum + IOI + release)
a `SuperFluxOnsetDetector` egy példányának publikus mezőiből veszi a
`delta`, `lambda`, `minIoiSec`, `lag`, `window`, `hop` értékeket — nincs
újragépelt `12.0`/`1.0` literál. Így egy jövőbeli production-retune nem
csúsztatja szét némán az A/B-t.

**Kimondott korlát:** a `_floor`, `_medianFrames`, `_postFrames`,
`_releaseFrames`, `_peakDecay`, `_peakRatio` a szállított fájl PRIVÁT
konstansai — ezeket a variáns-fájl dokumentált **tükörként** deklarálja, és a
doksi kimondja, hogy ez a tükör kézi szinkronban van, nem gépiben. Ez nem
elrejtett hiányosság, hanem a variáns-fájl határa.

### D3 — Minden pontossági szám a merge-elt `computeRecognitionMetrics`-ből jön

A benchmark variánsonként `RecognitionCase`-eket épít (`expectedEvents` =
annotáció, `detectedEvents` = a variáns onsetjei `kind:
RecognitionEventKind.onset`, `accepted: true`), és a pontozást **kizárólag**
a `computeRecognitionMetrics` (ADR 0509) végzi. A benchmark:

- **nem** deklarál saját tűrés-listát (`onsetTolerancesMs`-t importálja);
- **nem** implementál párosítást, P/R/F1-et, kerekítést;
- a `null` értéket „nem mért"-ként rendereli, sosem `0`-ként (ADR 0509 D6).

### D4 — Két kimeneti csatorna: determinisztikus pontosság, gépfüggő idő

- **`onset-ab-report.json` (+ Markdown)** — kizárólag a bemenetből
  következő értékek: variáns-id-k, eset- és eseményszámok, a merge-elt
  metrika-fa, az **algoritmikus késleltetés** (a döntés pillanata mínusz a
  jelentett onset-idő, mintánként egész ms — determinisztikus, a merge-elt
  `latencyP50Ms`/`latencyP95Ms` viszi). Kétszeri futás **bájtra azonos**.
- **`onset-ab-timing.json`** — a fal-óra/CPU mérés (variánsonként teljes
  feldolgozási idő, egy audio-másodpercre jutó µs), `deviceId`+`buildSha`
  metaadattal, **kimondottan gépfüggőként** jelölve. Sosem merge-kapu, és
  egyetlen kulcsa sem szivárog a determinisztikus riportba.

Ez oldja fel a Kontextus 5. pontjában mért ütközést: a Pareto-nézet
(pontosság vs késleltetés vs CPU) megmarad, de a bájt-azonosság csak arra
vonatkozik, ami valóban a bemenet függvénye.

### D5 — A csoportosítás a dashboardé marad; a benchmark manifestet ad át

A benchmark variánsonként egy **`schemaVersion: "1.0"`** felismerési
manifestet is kiír, amit a merge-elt
`RecognitionEvaluationRunner.runFromJsonString` visszaolvas. A per-alcsoport
bontást így a MEGLÉVŐ dashboard (`recognition_report_renderer.dart`, ADR 0511)
adja — a benchmark **nem** épít második csoportosítást és nem másolja a
`(unknown)` vödör szemantikáját.

### D6 — Nincs barrel-export

A variáns-fájl **nem** kerül be a `lib/features/live/public.dart`-ba: a
merge-elt „a DSP-motor nincs exportálva" döntés érvényben marad (Kontextus 6).
A benchmark és a tesztje közvetlenül importál.

### D7 — Nincs commitolt audio-fixture

A kötelező cellák teszt-időben előállított, determinisztikus szintetikus
jelekkel és kézzel épített esemény-listákkal dolgoznak; a valódi korpusz a
CLI külső könyvtár-argumentuma (`real_audio_dsp_baseline.dart` alakja).
`test/fixtures/**` ennek a körnek tilos zónája.

## Következmények

- A kör kimenete **mérés és javaslat**, nem hangolás: a
  `docs/eval/onset-detector-ab.md` a Pareto-nézetet és a következő lépés
  javaslatát rögzíti, a döntést egy KÉSŐBBI kör ADR-je hozza meg.
- A benchmark a merge-elt metrika-fához kötött: ha az ADR 0509 tűrés-listája
  vagy párosítási szabálya változik, az A/B automatikusan követi — ez
  szándékos.
- A gépfüggő idő külön fájlban él, ezért a determinizmus-cella egy CPU-oszlop
  hozzáadásától sem lesz lobogó.
- A `canonicalSuperFlux24` a 24 sáv/oktáv **saját** log-frekvenciás
  szűrősorát építi az STFT fölé; a `CqtExtractor` (`binsPerOctave = 24`) NEM
  használható erre, mert `hop = 2048` @ 22,05 kHz ≈ **93 ms**, ami
  onset-felbontásnak nagyságrendekkel durva. Ez mérve, nem feltételezve.

## Mérce

`test/tooling/onset_ab_benchmark_test.dart` (a kör `gate_tests`-e):

| Cella | Mit fog pirosra |
|---|---|
| a 49/50/51 ms-os hármas a benchmark SAJÁT útján | exkluzív határ vagy saját párosítás (D3) |
| a riport tűrés-kulcsai `== onsetTolerancesMs`, és a `definition.matchingRule` tartalmazza a `Kuhn's maximum-cardinality` szöveget | a benchmark saját, nem-delegált pontozása (D3) |
| kétszeri futás bájtra azonos determinisztikus riport | időbélyeg vagy fal-óra a riportban (D4) |
| a determinisztikus riport JSON-ja egyetlen időzítés-kulcsot sem tartalmaz | a CPU-oszlop beszivárgása (D4) |
| a négy variáns-id mind szerepel, és a `current` a szállított detektor kimenetét adja | hiányzó vagy újraimplementált `current` (D1) |
| a variáns `delta`/`lambda`/`minIoiSec` a szállított detektor publikus alapértékével egyezik | újragépelt konstans (D2) |
| annotáció nélküli esetre `null` („nem mért"), nem `0` | a hiány számmá kerekítése (D3) |
| a `superflux_onset_detector.dart` + `dsp_config.dart` konstansai a mért értéken (`_delta = 12.0`, `_lambda = 1.0`, floor `-9.0`) | menet közbeni hangolás (D1) |
| a kiírt manifest visszaolvasható `RecognitionEvaluationRunner`-rel, azonos metrikákkal | séma-drift a D5 átadási ponton |
