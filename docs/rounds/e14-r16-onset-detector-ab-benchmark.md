# E14-R16 — Onset-detektor variáns-szeám és A/B mérés

- **Státusz:** REVISED (pre-flight, 2026-09-05 — mért alap: `main @ 1e235320`;
  az eredeti előre-írás 2026-08-20, `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 16 (strum recovery blokk)
- **Kör-azonosító:** `E14-R16`
- **Branch:** `sonnet-impl/e14-r16-onset-detector-ab-benchmark`
- **Előfeltétel:** `E14-R08` (ADR 0509 — a metrika-fa, amit ez a kör FOGYASZT)
  és `E14-R15` (ADR 0521) merge-elve. Mérve: mindkettő a `main`-en.
- **Brief szerzője:** Claude (Opus 5) · **revízió:** E14-R16 pre-flight
- **Előre kiosztott ADR:** `0524` (foglaló:
  `tools/round-slots.py reserve-adr --round E14-R16`) — **a Claude írta meg**
  (`docs/adr/0524-onset-detector-variant-seam-and-ab-measurement.md`), a
  `docs/adr/` a TILOS zónában van. A 2026-08-20-i előre-írás `0368`-at mondott;
  az a szám elavult (§0.0).

> ⚠ **Indítás előtt KÖTELEZŐ:** olvasd el a §0.0 revíziót, majd
> az **ADR 0524** Döntés-szakaszát, végül
> `lib/features/live/domain/evaluation/recognition_metrics.dart` 460–530.
> sorát (`onsetTolerancesMs`, `onsetDefinition`, `_matchEvents` hívása). Ez a
> kör NEM ír második párosítást/tűrést/P-R-F1-et — a pontozást a merge-elt
> szerződés végzi. Eltérésnél `stopped` jelzés, nem improvizáció.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tool/benchmarks/onset_ab_benchmark.dart",
  "lib/features/live/engine/dsp/onset_detector_variant.dart",
  "test/tooling/onset_ab_benchmark_test.dart",
  "docs/eval/onset-detector-ab.md",
  "docs/rounds/e14-r16-onset-detector-ab-benchmark.md",
]
gate_tests = [
  "test/tooling/onset_ab_benchmark_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl → `stopped`**, nem
„gyors javítás": ha a munkához bármi kellene az öt engedélyezett útvonalon
kívül (pl. `test/fixtures/**`, `lib/features/live/public.dart`,
`superflux_onset_detector.dart`), az `stopped` + egy soros indoklás.

## 0.0 Revízió — MÉRT tények (pre-flight, 2026-09-05, `main @ 1e235320`)

A brief 2026-08-20-án készült; azóta a mért alapja elmozdult (`brief-lint`
**S15** + **S12**). A revízió a teljes mérést az
[ADR 0524](../adr/0524-onset-detector-variant-seam-and-ab-measurement.md)
Kontextus-szakaszába írta; a rövid tábla:

| Amit a régi brief állított | MA mért igazság |
|---|---|
| a 2. acceptance-pont ELDÖNTI, hogy a tűrés-határ inkluzív | **MÁR MERGE-ELT DÖNTÉS.** `recognition_metrics.dart:460-461` + `onsetDefinition` — `[25, 50, 100]`, `boundary inclusive (<=)`, Kuhn-féle **maximális** párosítás (a mohó alulszámol, `L269`). Egy második párosítás a benchmarkban az `L549`/`L636`/`L645` hibaosztály |
| a report ÚJ P/R/F1-et számol variánsonként | **NEM.** a pontozás a `computeRecognitionMetrics`-é (ADR 0509); a benchmark bemenetet épít és riportot rendez, metrikát nem definiál |
| 3. pont: bájtra azonos riport **és** 4. pont: CPU-oszlop | **ÜTKÖZIK.** a fal-óra/CPU futásonként és gépenként változik (ADR 0248/0474) → két csatorna kell (ADR 0524 D4) |
| `lib/features/live/public.dart` — „additív export" | **MERGE-ELT DÖNTÉST ÍRNA FELÜL.** `public.dart:3-7`: a `engine/dsp/` szándékosan NINCS exportálva (SDD Ch2 §10.3/10.4). A `tool/check_architecture.dart` csak a `lib/` fát méri, a benchmark közvetlenül importálhat → az export felesleges. **A fájl kikerült az `allowed_paths`-ból** (szűkítés) |
| „a harmadik benchmark ide illeszkedik" (§2) | **IGAZ, de** a `real_audio_dsp_baseline.dart` saját, tool-lokális `matchOnsetsUs`-a NEM használható referenciának (nem maximális párosítás); az a fájl tilos zóna |
| előre kiosztott ADR `0368` | **ELAVULT.** a foglaló `0524`-et ad |
| a korpusz „az E14-R08 fixture-e" | **NINCS ilyen audio-fixture.** `test/fixtures/audio/` 16 KB, csak `song_trainer`; nyers audio nem kerül a repóba (ADR 0249). A cellák teszt-időben előállított szintetikus jelekkel mérnek, a valódi korpusz CLI-argumentum (ADR 0524 D7) |

**A kör EGYETLEN döntési helye ezért:** az **onset-detektáló függvények
variáns-szeáma** és az azonos bemeneten futó **A/B mérés** — a pontozás
delegált, a csoportosítás a merge-elt dashboardé, a production konstans nem
mozdul.

**A revízió által KIVETT munka (későbbi kör, saját ADR-rel):**

1. **Konstans-átállítás** a mérés eredménye alapján (AGENTS.md §9: külön ADR).
2. **Per-alcsoport A/B-bontás** — a benchmark manifestet ad át a merge-elt
   dashboardnak (ADR 0524 D5), második csoportosítást nem épít.
3. **A tool-lokális `matchOnsetsUs` nyugdíjazása** a `real_audio_dsp_baseline.dart`-ban.

## 1. Cél

Egy futtatható artefaktum, amely **négy onset-detektáló függvényt** mér össze
ugyanazon a bemeneten, ugyanazzal a — **merge-elt** — pontozó szerződéssel, és
a pontosság mellé algoritmikus késleltetést és (külön, gépfüggő csatornán)
CPU-időt ad. A kör kimenete **mérés + javaslat**; a production konstans NEM
mozdul.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **[L269](../LESSONS.md#l269):** időablakos one-to-one értékelésben a mohó
  „legközelebbi szabad pár" nem maximális — ezért van a merge-elt szerződésben
  Kuhn-párosítás, és ezért nem írunk másodikat.
- **[L549](../LESSONS.md#l549) / [L645](../LESSONS.md#l645):** a metaadat
  MEGLÉTE nem a jelentése; és egy „legyen rá ÚJ fájl" előírás némán második
  döntési hellyé válik, ha a képességnek már van megnevezett kiterjesztési
  pontja.
- **[L636](../LESSONS.md#l636):** az előre megírt brief mért alapja elmozdul —
  ezt a §0.0 méri ki.
- **[L173](../LESSONS.md#l173):** hiba-metrikán a generikus „magasabb=jobb"
  sablon csendben megfordítja a döntést → a merge-elt metrika a saját
  `definition.higherIsBetter`-ét hozza, a riport azt olvassa.
- **ADR 0474 / 0248:** a benchmark-szám gépfüggő; `deviceId`+`buildSha` nélkül
  értelmetlen, és nem merge-kapu.
- **AGENTS.md §9:** shipping DSP-konstans csak mért A/B **és** ADR után mozdul.

## 2. Jelenlegi állapot — mért tények (`main @ 1e235320`)

- `lib/features/live/engine/dsp/superflux_onset_detector.dart` — maximum-szűrt
  log-mel flux, adaptív küszöb. **Mérve:** `_floor = -9.0` (60. sor),
  `_delta = 12.0` (78.), `_lambda = 1.0` (79.), `_medianFrames = 69`,
  `_postFrames = 2`, `_releaseFrames = 3`, `_peakDecay = 0.985`,
  `_peakRatio = 0.15`. A publikus konstruktor-mezők: `window = 1024`,
  `hop = 256`, `bands = 64`, `lag = 2`, `minIoiSec = 0.06`, `delta`, `lambda`.
  `processFrame(Float64List frame)` a megerősített onset **idejét** adja
  (másodperc, keret-kezdet) vagy `null`-t.
- `lib/features/live/domain/evaluation/recognition_metrics.dart` —
  `onsetTolerancesMs = [25, 50, 100]`, inkluzív határ, Kuhn-féle maximális
  párosítás, `null ≠ 0`, `RecognitionEvaluationReport.toDeterministicJson`.
- `lib/features/live/data/evaluation/recognition_evaluation_runner.dart` —
  `schemaVersion "1.0"` manifest-parszer, tipizált hibákkal.
- `tool/benchmarks/` — `real_audio_dsp_baseline.dart` (külső korpusz-könyvtár
  argumentumból, `main([List<String> arguments])`, tiszta függvények +
  `dart:io` a szélén), `song_trainer_pitch_benchmark.dart`,
  `benchmark_record.dart`, `recognition_baseline_manifest.dart`.
- `test/tooling/real_audio_dsp_baseline_test.dart` — a bevált teszt-alak:
  `import '../../tool/benchmarks/…'`, fixture nélkül, teszt-időben épített
  adatokkal.
- `package:fftea/fftea.dart` elérhető (`FFT(nFft).realFft(...)` → komplex
  spektrum); `LogMelExtractor` a mel-front-end, `CqtExtractor` **NEM
  használható** (hop 2048 @ 22,05 kHz ≈ 93 ms).
- Nincs olyan artefaktum, amely TÖBB onset-függvényt mérne egy bemeneten.

## 3. Scope

**Benne:** variáns-szeám + négy implementáció, közös STFT és közös
csúcs-kiválasztó, benchmark-CLI, determinisztikus pontossági riport, külön
gépfüggő időzítés-fájl, variánsonkénti manifest-kiírás, doksi.

**Nincs benne:** a production konstansok módosítása (`superflux_onset_detector.dart`,
`dsp_config.dart`), a live pipeline bekötése, barrel-export, per-alcsoport
csoportosítás, `ml/**`, `test/fixtures/**`, a `real_audio_dsp_baseline.dart`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/dsp/onset_detector_variant.dart` | a variáns-szeám és a négy implementáció (ÚJ fájl; a szállított detektor változatlan) |
| `tool/benchmarks/onset_ab_benchmark.dart` | a futtatható A/B (tiszta mag + `dart:io` a szélén) |
| `test/tooling/onset_ab_benchmark_test.dart` | a kör kapuja |
| `docs/eval/onset-detector-ab.md` | a report-alak, a Pareto-nézet és a javaslat |
| `docs/rounds/e14-r16-onset-detector-ab-benchmark.md` | §10 handoff |

**Tilos zóna:** minden más — **kiemelten**
`lib/features/live/engine/dsp/superflux_onset_detector.dart` és
`dsp_config.dart` (a konstansok!), `lib/features/live/public.dart`,
`lib/features/live/domain/evaluation/**` és `data/evaluation/**` (ezeket
IMPORTÁLOD, nem módosítod), `tool/benchmarks/real_audio_dsp_baseline.dart`,
`test/fixtures/**`, `lib/features/live/engine/ml/**`, `assets/**`, `ml/**`,
`docs/adr/**`, `docs/rag/chunks/**`, `.github/workflows/**`,
`tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0524)

### 5.1 A production út érintetlen (D1)

A `superflux_onset_detector.dart` és a `dsp_config.dart` diffje a kör végén
**üres**. **NEM elfogadható:** „a canonical jobb, ezért átállítom".

### 5.2 A `current` variáns a SZÁLLÍTOTT detektort hívja (D1)

Nem másolat, nem újra-implementáció: `SuperFluxOnsetDetector`-t példányosít az
alapértelmezett konstansokkal, és annak `processFrame`-jét futtatja.

### 5.3 A hangoló-értékek a szállított detektor publikus mezőiből jönnek (D2)

A közös csúcs-kiválasztó a `delta`, `lambda`, `minIoiSec`, `lag`, `window`,
`hop` értékeket egy `SuperFluxOnsetDetector` példány publikus mezőiből veszi —
**újragépelt `12.0`/`1.0` literál tilos**. A privát konstansok
(`_floor`, `_medianFrames`, `_postFrames`, `_releaseFrames`, `_peakDecay`,
`_peakRatio`) dokumentált, kézi **tükörként** kerülnek a variáns-fájlba, és a
doc-comment ezt kimondja.

### 5.4 A pontozás a merge-elt szerződésé (D3)

A benchmark `RecognitionCase`-eket épít és `computeRecognitionMetrics`-et hív.
**Tilos:** saját tűrés-lista, saját párosítás, saját P/R/F1, saját kerekítés.
A hiányzó érték `null` marad, és „nem mért"-ként renderelődik.

### 5.5 Két csatorna: determinisztikus pontosság, gépfüggő idő (D4)

- determinisztikus riport: se `DateTime.now()`, se fal-óra, se gépnév;
- időzítés-fájl: külön, kimondottan gépfüggőként jelölve.

Az **algoritmikus késleltetés** determinisztikus, és a merge-elt
`latencyP50Ms`/`latencyP95Ms` viszi: mintája a `RecognitionCase.detectionLatenciesMs`,
értéke `döntés_ideje_ms − jelentett_onset_ms`, ahol a döntés ideje a
`processFrame` hívás keretének VÉGE (`(frameIndex * hop + window) / sampleRate`).

### 5.6 A csoportosítás a dashboardé (D5)

Variánsonként `schemaVersion: "1.0"` manifest íródik ki, amit a merge-elt
`RecognitionEvaluationRunner.runFromJsonString` visszaolvas. Második
csoportosítás nem épül.

## 6. Acceptance criteria

1. **Négy variáns egy bemeneten.** A `spectralFlux`, `complexDomain`,
   `canonicalSuperFlux24` és `current` id mind megjelenik a riportban,
   mindegyik UGYANAZT az eset-listát kapja, és mindegyikhez a merge-elt
   metrika-fa tartozik a 25/50/100 ms tűrésekre.
2. **A `current` a szállított detektor kimenete.** Egy determinisztikus
   szintetikus jelen a `current` variáns onset-listája **elemre azonos** azzal,
   amit a közvetlenül példányosított `SuperFluxOnsetDetector` ad ugyanarra a
   keretezésre.
3. **A pontozás delegált.** A riport tűrés-kulcsai `== onsetTolerancesMs`, és
   minden onset-metrika `definition.matchingRule`-ja tartalmazza a
   `Kuhn's maximum-cardinality` szöveget (ez csak a merge-elt kódból
   származhat).
4. **Inkluzív határ a benchmark SAJÁT útján.** Egy kézzel épített esettel, a
   `onsetToleranceMsPrimary == 50` ms tűrésen, cellahármas: a küszöb **alatt**
   (49 ms eltérés) párosít (`truePositives == 1`), pontosan **rajta** (50 ms)
   párosít — a határ ide tartozik —, a küszöb **fölött** (51 ms) nem párosít
   (`truePositives == 0`, `falsePositives == 1`, `falseNegatives == 1`).
   A három eltérés az elvárt esemény `timeMs` értékéhez képest
   (`python3 -c "t=50; print([t-1, t, t+1])"` → `[49, 50, 51]`).
5. **Determinizmus.** Ugyanarra a bemenetre kétszer futtatva a determinisztikus
   riport JSON-ja **bájtra azonos**, és nem tartalmaz egyetlen időzítés-kulcsot
   sem (`elapsed`, `wallClock`, `cpu`, `durationMicros`, `timestamp`).
6. **Idő- és CPU-mérés van, külön csatornán.** Az időzítés-kimenet
   variánsonként ad fal-óra/CPU értéket, `deviceId` + `buildSha` mezővel, és
   kimondottan gépfüggőként jelölve; az **algoritmikus késleltetés** a
   determinisztikus riportban van (`latencyP50Ms`, `latencyP95Ms`).
7. **Nem mért ≠ 0.** Annotáció nélküli esetre a riport `null`-t hordoz és „nem
   mért"-et renderel; egyetlen metrika sem kerekedik `0`-ra emiatt.
8. **A production konstans nem mozdult.** A `superflux_onset_detector.dart` és
   a `dsp_config.dart` diffje üres, és a teszt pinneli a mért értékeket
   (`delta == 12.0`, `lambda == 1.0`, `minIoiSec == 0.06`, `window == 1024`,
   `hop == 256`, `bands == 64`, `lag == 2`) a szállított detektor publikus
   alapértékein keresztül.
9. **A manifest-átadás él.** A kiírt, variánsonkénti manifest
   `RecognitionEvaluationRunner.runFromJsonString`-gel visszaolvasva
   **ugyanazokat** az onset-metrikákat adja, mint a riport.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Melyik őr |
|---|---|---|
| a production konstans „menet közben" módosul | 8. pont | unit-cella + `git diff --stat` a review-ban |
| a benchmark saját párosítót/tűrést ír | 3. és 4. pont | unit-cella (a `matchingRule` szöveg csak a merge-elt kódból jön) |
| a párosítás exkluzív határral | 4. pont **50 ms** cellája | unit-cella |
| a riportba időbélyeg vagy fal-óra kerül | 5. pont | unit-cella (kulcs-tiltó lista + bájt-azonosság) |
| csak pontosság, idő-mérés nélkül | 6. pont | unit-cella |
| a `current` variáns újra-implementálja a detektort | 2. pont | unit-cella (elemre azonos onset-lista) |
| a variáns újragépeli a `12.0`/`1.0` konstanst | 8. pont | unit-cella (a publikus alapértékkel szemben) |
| hiányzó annotáció → `0` | 7. pont | unit-cella |
| a kiírt manifest sémája elcsúszik | 9. pont | unit-cella (round-trip) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/onset_ab_benchmark_test.dart
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). A parancs a `gate_tests`
listát tükrözi. CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld **mért** kimenettel: a variáns-fájl közös
csúcs-kiválasztójában a `delta` forrását ideiglenesen `12.0` literálra
cserélve **és** a szállított detektor `delta` alapértékét gondolatban
elmozdítva a 8. pont cellája **PIROS**; visszaállítva **ZÖLD**. Ugyanígy: a
párosítás tűrését `<` határra cserélve a 4. pont 50 ms-os cellája **PIROS**.
A `superflux_onset_detector.dart`-ot a próbához **nem** módosítod — a cella a
variáns-fájl oldaláról falszifikálható.

## 8. Implementációs sorrend

1. **STFT-mag + közös csúcs-kiválasztó** a variáns-fájlban (`fftea`; a
   hangoló-értékek a `SuperFluxOnsetDetector` publikus mezőiből, ADR 0524 D2).
2. **A négy variáns:** `current` (a szállított detektort hívja),
   `spectralFlux`, `complexDomain`, `canonicalSuperFlux24` (24 sáv/oktáv
   log-frekvenciás háromszög-szűrősor az STFT fölé, max-szűrt lag-flux).
3. **Benchmark-mag:** esetek → variánsonként onsetek + késleltetés-minták →
   `RecognitionCase` → `computeRecognitionMetrics` → determinisztikus riport
   (JSON + Markdown). Tiszta függvények, `dart:io` nélkül.
4. **CLI-héj** (`main([List<String> arguments])`) a
   `real_audio_dsp_baseline.dart` alakja szerint: korpusz-könyvtár argumentum,
   riport + időzítés-fájl + variánsonkénti manifest kiírása.
5. **Teszt** a §6 kilenc pontjára, fixture nélkül, teszt-időben előállított
   determinisztikus jelekkel és kézzel épített esemény-listákkal.
6. **Doksi** (`docs/eval/onset-detector-ab.md`): a riport-alak, a két csatorna
   közti határ, a Pareto-nézet olvasata és a javaslat — a döntés egy KÉSŐBBI
   kör ADR-je.

A brief §8 a terved — nincs külön task-lista. Doc-commentben csak tesztben
bizonyított állítás szerepeljen (`const`, `immutable`, „determinisztikus").

## 9. Kockázatok

- **Hangolás-csúszás:** a legnagyobb kockázat, hogy a mérés után a production
  konstans „gyorsan" átáll — az 5.1, a tilos zóna és a 8. acceptance-pont ezt
  fail-closed tiltja.
- **Második metrika-definíció:** a benchmarkba írt saját párosítás/tűrés az
  `L549`/`L645` hibaosztály — a 3. és 4. pont ezt fogja meg.
- **Determinizmus-szennyezés:** a CPU-oszlop beszivárgása a riportba — az 5.
  pont kulcs-tiltó listája fogja meg.
- **Korpusz-hiány:** valódi korpusz nélkül a CLI nem tud éles számot adni; ez
  **nem** akadály (a kör a harnesst szállítja), de kitalált szám a doksiba nem
  kerülhet — ami nem mért, az „nem mért".

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5), `--effort medium`.

### Fájlonként mit épített

- **`lib/features/live/engine/dsp/onset_detector_variant.dart`** (ÚJ) —
  `OnsetVariantId` (`current`, `canonicalSuperFlux24`, `complexDomain`,
  `spectralFlux`) + `OnsetDetectorVariant` interfész
  (`id`/`window`/`hop`/`delta`/`lambda`/`minIoiSec`/`describe()`/`processFrame()`)
  + `createOnsetDetectorVariant`.
  - `_shippedTuning(sampleRate)` egy `SuperFluxOnsetDetector(sampleRate:
    sampleRate)` példányt hoz létre és a publikus mezőiből (`delta`,
    `lambda`, `minIoiSec`, `lag`, `window`, `hop`) épít egy rekordot (ADR
    0524 D2) — ez az EGYETLEN forrás mind a négy variánsnak.
  - `_CurrentVariant` a szállított `SuperFluxOnsetDetector`-t hívja
    közvetlenül (ADR 0524 D1/5.2); a `delta`/`lambda`/`minIoiSec`/`window`/`hop`
    gettere is `_detector`-ra delegál.
  - `_PeakPicker` a szállított detektor csúcs-megerősítő állapotgépének
    dokumentált, KÉZI tükre (`_medianFrames=69`, `_postFrames=2`,
    `_releaseFrames=3`, `_peakDecay=0.985`, `_peakRatio=0.15`) — a
    hangoló-értékeket (`delta`/`lambda`/`minIoiSec`/`hop`) a hívó adja át,
    sosem újragépelt literál.
  - `_Stft` (Hann-ablak + `fftea` `realFft`) a közös STFT-mag, a
    `LogMelExtractor` framing-konvencióját tükrözve.
  - `_LogFreqFilterbank` a `canonicalSuperFlux24`-hez épített 24 sáv/oktáv,
    log2-frekvenciás háromszög-szűrősor 27,5 Hz-től Nyquistig — a
    `LogMelExtractor._buildFilterbank` mintáját követi, de log2-osztással
    (nem mel-skálával); a `CqtExtractor`-t NEM használja (indoklás: ADR 0524
    Következmények, ~93 ms hop). `fMin`/`binsPerOctave` végül `static const`
    lett (nem konstruktor-paraméter), mert a `flutter analyze`
    `unused_element_parameter`-t jelzett — ez a variáns szándékosan NEM
    konfigurálható felbontású.
  - `_CanonicalSuperFlux24Variant` a szállított algoritmus log-power
    floor+max-filtered lag-flux lépését futtatja a 24-sávos szűrősoron.
  - `_SpectralFluxVariant` félhullám-egyenirányított magnitúdó-flux
    (fázis nélkül), `_ComplexDomainVariant` komplex-domain ODF (a
    magnitúdó+fázis lineáris predikciója az előző két keretből, az eltérés
    összesített magnitúdója) — mindkettő a közös `_Stft`+`_PeakPicker`-t
    használja.
- **`tool/benchmarks/onset_ab_benchmark.dart`** (ÚJ) — tiszta mag +
  `dart:io`-s CLI-héj a `real_audio_dsp_baseline.dart` alakja szerint.
  - `runOnsetVariant(id, OnsetAbCase)`: a bemenetet `variant.window`/`hop`
    szerint keretezi, `RecognitionDetectedEvent`-eket épít, és az
    algoritmikus késleltetést a brief 5.5 pontja szerinti képlettel számolja
    (`(frameIndex*hop+window)/sampleRate*1000 − onsetMs`).
  - `scoreCases(cases)` az EGYETLEN pontozó belépési pont —
    `computeRecognitionMetrics`-et hívja, nem definiál tűrést/párosítást.
    `buildOnsetAbReport` és `onsetAbManifestJson` is ezen keresztül fut.
  - `OnsetAbReport.toJson()` a `onsetTolerancesMs` konstanst literálisan
    beágyazza (a 3. acceptance-pont ezt ellenőrzi), variánsonként a teljes
    `RecognitionEvaluationReport.toJson()`-t.
  - `manifestJson(cases)` a `RecognitionManifest` pontos alakját írja
    (`schemaVersion`, `cases[].expectedEvents/detectedEvents/…`) —
    `RecognitionEvaluationRunner.runFromJsonString`-gel visszaolvasható.
  - `OnsetAbTiming`/`measureOnsetAbTiming` a KÜLÖN, gépfüggő csatorna
    (`Stopwatch`, `deviceId`, `buildSha`, kimondó `note` mező); egyetlen
    mezője sem kerül az `OnsetAbReport`-ba.
  - `main()` egy ÚJ, ebben a körben bevezetett sidecar-formátumot vár
    (`<stem>.wav` + `<stem>.onsets.json` = `{"onsets": [seconds, ...]}`),
    mert a repóban nincs commitolt, tiszta onset-only annotáció (a
    `.strums` chord-eseményeket hordoz). Korpusz hiányában is fut (üres
    esetlistával), és a kihagyott fájlokat jelzi.
- **`test/tooling/onset_ab_benchmark_test.dart`** (ÚJ) — a §6 mind a kilenc
  pontjára egy-egy teszt, fixture nélkül: `test/support/synth.dart`
  (`strumSignal`/`strumPattern`/`frames`, MÁR létező, nem ehhez a körhöz
  tartozó segédfájl, csak importált) szintetikus jeleket és kézzel épített
  `RecognitionCase`/`RecognitionExpectedEvent`/`RecognitionDetectedEvent`
  eseteket használ.
- **`docs/eval/onset-detector-ab.md`** (ÚJ) — a riport-alak, a két csatorna
  határa, a Pareto-nézet olvasata, a `<stem>.onsets.json` sidecar-formátum
  és a javaslat (a döntés egy KÉSŐBBI kör ADR-je) — mért szám NINCS benne
  (nincs korpusz, ADR 0249).

### §7.1 falszifikációs próba — MÉRT kimenet

**1. próba (8. pont, D2 — a hangoló-érték a szállított detektorból jön):**
a `_SpectralFluxVariant` faktorában a `delta: tuning.delta` sort
`delta: 99.0` literálra cseréltem (ideiglenesen, csak a variáns-fájlban —
a `superflux_onset_detector.dart`-ot NEM érintettem). Futtatva:

```
00:00 +7 -1: … 8. the production constants have not moved … [E]
  Expected: <12.0>
    Actual: <99.0>
  spectralFlux
```

→ **PIROS**, pontosan a 8. ponton. Visszaállítva (`delta: tuning.delta`):
a teljes `test/tooling/onset_ab_benchmark_test.dart` **9/9 ZÖLD**.

**2. próba (4. pont, D3 — az 50 ms-os határ inkluzív, a benchmark saját
útján):** a teszt `cellFor` segédfüggvényében a valódi
`scoreCases([recognitionCase]).overall.onsetTolerance50Ms` hívást
ideiglenesen egy kézzel írt, EXKLUZÍV (`deviationMs < 50`) szimulált
matcherre cseréltem (nem a `computeRecognitionMetrics`-et, hanem a
tesztben szimulált, nem-delegált eredményt). Futtatva:

```
00:00 +3 -1: … 4. inclusive 50 ms boundary … [E]
  Expected: <1>
    Actual: <0>
  50 ms — ON the boundary, inclusive
```

→ **PIROS**, pontosan az 50 ms-os cellán. Visszaállítva (`scoreCases`
hívás): a teljes suite **9/9 ZÖLD** (`git diff` a két fájlon a próbák után
üres — ellenőrizve `git diff --stat`).

### A gate tényleges eredménye

```
tools/round-gate.sh test/tooling/onset_ab_benchmark_test.dart
```

`format` → `analyze` → `test test/tooling/onset_ab_benchmark_test.dart` →
`architecture` → `secrets` → `l10n`: **mind ZÖLD** („MINDEN GATE ZÖLD”).
A gate első `analyze` futása két `unused_element_parameter` warningot és
hat `prefer_initializing_formals` info-t adott (a `_LogFreqFilterbank`
konfigurálhatatlan `fMin`/`binsPerOctave` paraméterei, illetve a három ÚJ
variáns privát konstruktorai) — ezeket javítottam (a paramétereket
`static const`-ra váltottam, a konstruktorokat `this._mező` inicializáló
formális paraméterre), a második futás tiszta.

### Döntések, amiket a brief nem írt elő

1. **`OnsetDetectorVariant` kiterjesztve `delta`/`lambda`/`minIoiSec`
   getterrel** (a brief csak `id`/`describe()`/`processFrame()`-et írt elő).
   Enélkül a 8. acceptance-pont csak `window`/`hop`-ot tudta volna pinnelni
   — a `delta`/`lambda`/`minIoiSec` újragépelt-literál hibaosztályt (a
   mérce-mátrix kifejezetten megnevezi) semmilyen teszt nem fogta volna meg.
   Az 1. falszifikációs próba ezt igazolja.
2. **`<stem>.onsets.json` sidecar-formátum** a CLI korpusz-bemenetéhez — új
   formátum, mert a repóban nincs tiszta onset-only annotáció; dokumentálva
   `docs/eval/onset-detector-ab.md`-ben.
3. **`deviceId`/`buildSha` szabad string**, NEM a `benchmark_record.dart`
   zárt eszköz-szótára (ADR 0474 D2) — az a fájl nincs az engedélyezett
   listán, és ez a kör nem köti be az ADR 0474 összehasonlító csővezetékbe
   (a timing csatorna kimondottan „sosem merge-kapu”).

### Ismert korlátok (szándékos, a brief szerint)

- A `_medianFrames`/`_postFrames`/`_releaseFrames`/`_peakDecay`/`_peakRatio`/
  log-power floor kézi tükör — ha a szállított fájl privát konstansai
  változnak, ezt kézzel kell frissíteni (ADR 0524 D2, dokumentálva a
  variáns-fájl fejlécében is).
- Valódi korpuszon mért Pareto-szám ebben a körben NINCS (nincs commitolt
  audio, ADR 0249) — a `docs/eval/onset-detector-ab.md` ezt kimondja.

## 11. Review — a Claude tölti ki
