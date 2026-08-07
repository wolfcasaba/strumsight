# E06-R05 — Input abstraction és biztonságos import

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 5; §6.2, §11.1, §28.2–28.6
- **Branch:** `codex/e06-r05-input-abstraction-and-safe-import`
- **Előfeltétel:** **E06-R03, E06-R04 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/analysis_input.dart",
  "lib/features/audio_analysis/data/input/audio_decoder_gateway.dart",
  "lib/features/audio_analysis/data/input/wav_decoder_adapter.dart",
  "lib/features/audio_analysis/data/input/analysis_input_validator.dart",
  "lib/features/audio_analysis/data/input/input_limits.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/core/foundation/app_failure.dart",
  "test/features/audio_analysis/data/audio_decoder_gateway_test.dart",
  "test/features/audio_analysis/data/analysis_input_validator_test.dart",
  "test/property/analysis_input_fuzz_property_test.dart",
  "docs/rounds/e06-r05-input-abstraction-and-safe-import.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/core",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R03/R04 merge. Olvasd
> újra `lib/core/audio/codec/wav_decoder.dart`-ot (a batch idején 104 sor,
> 16-bit PCM + 32-bit IEEE float, mono/stereo átlagolás, **`null` visszatérés**
> minden nem támogatott esetre) és a `test/features/analyze/wav_decoder_test.dart`
> tényleges eseteit — a mai viselkedést **nem** szabad megváltoztatni, a kör
> **adaptert** tesz köré. Ellenőrizd a `lib/core/foundation/app_failure.dart`
> `FailureCode` enumját: az új kódok **additívak**, meglévő nem nevezhető át.
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — az R01 ADR 0202 (raw audio) és a SDD §28.6
(biztonságos dekódolás) végrehajtása.

## 1. Cél

A mikrofonos és importált audio **közös, validált boundary** mögé helyezése:
typed failure minden elutasításnál, bounds-safe parser, méret- és
hosszkorlát, és a fájlnév **privacy-flagelt** kezelése.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- `lib/core/audio/codec/wav_decoder.dart` (104 sor): `DecodedAudio =
  (List<double> pcm, int sampleRate)`; támogat **format 1** (16-bit PCM) és
  **format 3** (32-bit IEEE float), mono/stereo (csatorna-átlagolás);
  minden más esetben **`null`** — indoklás nélkül. Fejlécnél `bytes.length < 44`
  → `null`; chunk-ciklus `off + 8 <= bytes.length` feltétellel jár.
- `lib/features/analyze/engine/wav_decoder.dart` = 2 soros **deprecated
  re-export** a core codecre.
- Az import útvonal ma az `AnalyzeController.analyzeImported(pcm, sampleRate)`
  (`analyze_providers.dart` 195–200): üres PCM vagy `sampleRate <= 0` esetén
  **néma no-op**, felvétel közben szintén.
- **Nincs** maximális kliphossz és **nincs** fájlméret-korlát sehol.
- A `ClipRecorder` in-memory `List<double>` puffere korlátlan
  (`clip_recorder.dart` 15).
- `lib/core/foundation/app_failure.dart` adja a `FailureCode` enumot és a
  `PermissionFailure`/`AudioFailure` altípusokat.
- **Nincs** `test/property/` alatt fuzz-jellegű WAV-teszt.

## 3. Scope

**Benne:** `AnalysisInput` sealed hierarchia (`PcmAnalysisInput`,
`FileAnalysisInput`) + `AnalysisInputSource` + privacy-flagelt
`sourceDisplayName`; `AudioDecoderGateway` (typed failure, **soha nem null**);
`WavDecoderAdapter` a meglévő core dekóder köré, a mai `null`-okat
**indokolt** failure-kódra fordítva; `AnalysisInputValidator` (üres minta,
sample rate, csatornaszám, véges értékek, min/max hossz, fájlméret);
`InputLimits` (verziózott, dokumentált konstansok); a szükséges **additív**
`FailureCode` értékek; fuzz-jellegű property-teszt véletlen byte-okra.

**Kívül — TILOS:** a `lib/core/audio/codec/wav_decoder.dart` **algoritmusának**
módosítása, új codec (AAC/MP3/FLAC), recorder (R06), preprocessing (R08),
`lib/features/analyze/**` érintése.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/analysis_input.dart` | ÚJ | sealed input + source + privacy flag |
| `.../data/input/audio_decoder_gateway.dart` | ÚJ | typed failure kapu |
| `.../data/input/wav_decoder_adapter.dart` | ÚJ | adapter a meglévő core dekóderre |
| `.../data/input/analysis_input_validator.dart` | ÚJ | kötelező ellenőrzések |
| `.../data/input/input_limits.dart` | ÚJ | verziózott korlátok |
| `.../public.dart` | meglévő | input típusok exportja |
| `lib/core/foundation/app_failure.dart` | meglévő | **additív** FailureCode értékek |
| `test/features/audio_analysis/data/*` | ÚJ | gateway + validator tesztek |
| `test/property/analysis_input_fuzz_property_test.dart` | ÚJ | random byte fuzz |

**Tilos zóna:** `lib/core/audio/codec/**` (az adapter **köré** épül, nem bele),
`lib/features/analyze/**`, `lib/features/live/**`, `pubspec.yaml`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A dekóder soha nem ad `null`-t indoklás nélkül** (SDD Kör 5 §3): a
   gateway `AppResult<DecodedAudio>`-t ad, a failure-kód megnevezi az okot
   (`unsupportedFormat`, `unsupportedBitDepth`, `truncatedChunk`,
   `invalidRiff`, `chunkSizeOutOfBounds`, `fileTooLarge`, `nonFiniteSample`).
   **NEM elfogadható:** a mai `null` továbbadása vagy egyetlen gyűjtőkód
   minden hibára.
2. **A meglévő core dekóder viselkedése VÁLTOZATLAN.** Az adapter a `null`-t
   **fordítja**, nem a parsert írja át. **NEM elfogadható:** a
   `wav_decoder.dart` „menet közbeni megjavítása"; ha a mai parser
   bizonyítottan bounds-unsafe egy fixture-ön, az **megállás és jelentés**
   (külön kör), nem néma javítás.
3. **Bounds-safety a gateway szintjén:** a kapu a **bájtok átadása ELŐTT**
   ellenőrzi a fájlméretet és a deklarált chunk-méretek konzisztenciáját;
   integer overflow ellen az összeadás **előtt** vizsgál
   (`size > bytes.length - body`, nem `body + size > bytes.length`).
   **NEM elfogadható:** a túlcsordulás utáni ellenőrzés.
4. **A fájlnév privacy-metaadat** (ADR 0202, SDD §28.3): a domain
   `sourceDisplayName`-je `redacted: true` jelzéssel jár, a `toString()` és
   minden logolt alak **redaktált**. **NEM elfogadható:** a fájlnév
   megjelenése egy `AppLogger` hívás `fields`-ében.
5. **Verziózott korlátok:** `InputLimits` konstansai néven nevezettek, a
   verzió a provenance-be kerül. Kezdeti értékek (dokumentált, mérésig
   ideiglenes): `maxFileBytes = 64 MiB`, `maxDuration = 10 perc`,
   `minDuration = 250 ms`, `maxSampleRate = 192 000`, `minSampleRate = 8 000`,
   `maxChannels = 2`. **NEM elfogadható:** ezek szórása a hívási helyekre.
6. **NaN/Infinity minta:** elutasítás (nem sanitization) az **importált**
   úton; a mikrofonos úton `nonFiniteSample` warning + a minta **nullázása**,
   mert egy plugin-hiba nem teheti elemezhetetlenné a felvételt. A két út
   különbsége szándékos és tesztelt.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A maximum kliphossz értéke mérés nélkül rögzíthető?
    blocking: true
    resolution_policy: use_default
    default: >-
      IGEN, de IDEIGLENESKÉNT jelölve: 10 perc, a `InputLimits` doc-commentje
      kimondja, hogy a végleges érték az E06-R28 benchmarkjából jön
      (SDD §22.5: "nem szabad vakon beégetni"). A device-mátrix kap egy
      PENDING sort a valós eszközös méréshez.
  - id: OD-02
    question: A stereo downmix itt vagy az R08-ban történjen?
    blocking: true
    resolution_policy: use_default
    default: >-
      A dekóder-adapter megtartja a MAI viselkedést (a core dekóder átlagol),
      de a csatornaszámot metaadatként MEGŐRZI; a verziózott downmix-policy
      az R08-é.
```

## 6. Acceptance criteria

- [ ] **Formátum-mátrix — hét cella:** 16-bit mono / 16-bit stereo /
      float32 mono / float32 stereo → **Success**; 8-bit / 24-bit /
      ADPCM (format 2) → **Failure** `unsupportedBitDepth`/`unsupportedFormat`,
      **kódonként külön** cella.
- [ ] **Malformed-mátrix — hat cella:** nem-RIFF fejléc; `WAVE` helyett más;
      csonkolt `fmt `; csonkolt `data`; `data` chunk mérete **nagyobb**, mint a
      hátralévő bájtok; `0xFFFFFFFF` chunk-méret (integer overflow próba) →
      mind **Failure**, a hívó **nem** kap crash-t.
- [ ] **Fájlméret-küszöb hármas:** `maxFileBytes − 1` → Success,
      **pontosan** `maxFileBytes` → Success (a határ **inkluzív**),
      `maxFileBytes + 1` → `fileTooLarge`. A három bájtszámot `python3 -c`-vel
      kiszámolva a briefbe/tesztbe (64 MiB = 67 108 864; a cellák
      **67 108 863 / 67 108 864 / 67 108 865**).
- [ ] **Hossz-küszöb hármas:** 48 000 Hz-en `minDuration = 250 ms` →
      **11 999 / 12 000 / 12 001** minta (a `12 000` átmegy, a `11 999`
      `clipTooShort`); a maximumnál `maxDuration = 10 perc` →
      **28 799 999 / 28 800 000 / 28 800 001** minta (a `28 800 000` átmegy).
- [ ] **NaN-mátrix:** importált úton NaN/+Inf/−Inf → `nonFiniteSample`
      Failure (3 cella); mikrofonos úton ugyanez → **Success + warning +
      a minta 0.0**, a többi minta bitre változatlan (3 cella).
- [ ] **Fuzz property:** `PROPERTY_SEED`-ből vezérelt **legalább 500** véletlen
      byte-tömb (részben valós RIFF-fejléccel kezdve) — egyik sem dob nem
      kezelt kivételt, mindegyik `AppResult`-ot ad, és a Success-ágak PCM-je
      csak véges számokat tartalmaz.
- [ ] **Fájlnév-redakció:** teszt méri, hogy a `sourceDisplayName` a
      `toString()`-ben nem jelenik meg nyersen, és hogy a gateway **nulla**
      logger-hívása tartalmazza a fájlnevet.
- [ ] **A core dekóder bitre változatlan:** `git diff --stat` nem tartalmazza
      `lib/core/audio/codec/wav_decoder.dart`-ot, és a
      `test/features/analyze/wav_decoder_test.dart` **átírás nélkül** zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A gateway a `null`-t egyetlen `decodeFailed` kóddá lapítja | a formátum-mátrix kódonkénti celláinak 3 sora |
| A chunk-ellenőrzés `body + size > bytes.length` alakú | a `0xFFFFFFFF` overflow-cella (nem dob, de rossz ágra megy) |
| A méret-ellenőrzés `>` helyett `>=` | a **pontosan** `maxFileBytes` cella |
| A minimum hossz `>` helyett `>=` | a **pontosan** 12 000 mintás cella |
| A NaN mindkét úton elutasításra kerül | a mikrofonos NaN→0.0 warning-cella |
| A NaN mindkét úton nullázódik | az importált NaN `Failure`-cella |
| A fájlnév a `toString()`-ben marad | a redakciós cella |
| A parser algoritmusa „menet közben javul" | a `git diff --stat` core-codec cella + a V1 wav-teszt |
| **Valódi-sértés próba (§10):** a fájlméret-ellenőrzés ideiglenes kiszedése → a `maxFileBytes + 1` cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/core test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `input_limits.dart` (dokumentált, verziózott konstansok).
2. RED: formátum-, malformed-, küszöb- és NaN-mátrix.
3. `analysis_input.dart` (sealed + privacy flag).
4. `wav_decoder_adapter.dart` + `audio_decoder_gateway.dart`.
5. `analysis_input_validator.dart` + additív `FailureCode`-ok.
6. Fuzz property-teszt; gate.

## 9. Kockázatok

- **A `FailureCode` bővítése közös fájl** — kizárólag **additív** módon, a
  meglévő értékek átnevezése/átsorszámozása azonnali BLOCKER.
- **A fuzz-teszt futásideje** — a `PROPERTY_SEED`-es 500 eset mérete legyen
  korlátozott (≤ 64 KiB/eset), hogy a gate ne lassuljon érdemben; a
  §10-ben a mért futásidőt rögzíteni kell.
- **A `maxDuration` a `ClipRecorder`-t is érinti** — de a recorder az R06
  területe; itt csak a **validátor** ismeri a korlátot.

**STOP:** ha a core WAV-parser bizonyítottan bounds-unsafe (a fuzz talál
kezeletlen kivételt), az **megállás és jelentés** külön javító körért — a
parser átírása ebben a körben scope-sértés.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r05-input-abstraction-and-safe-import-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
