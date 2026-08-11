# E06-R05 — Input abstraction és biztonságos import

- **Státusz:** PREPARED → PLANNING (R1 revízió, 2026-08-11, orchesztrátor
  pre-flight — kód újraellenőrizve: main @ `03cbbf86`, előre megírva
  2026-08-07 @ `a6e6f3d`)
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

**PREPARED → PLANNING (R1 revízió, 2026-08-11, orchesztrátor pre-flight).**
Új ADR nincs — a kör az R01-ben már elfogadott ADR (ld. R1 lent) és a SDD
§6.2, §11.1, §28.6 szerződéseit ülteti át konkrét Dart kódba.

### R1 — ADR-átszámozás (mért, pipeline-prompt §1)

A brief 2026-08-07-i megírásakor az E06-R01 hat ADR-jét még nem foglalták le,
ezért a §0.0 (eredeti) a `0202` placeholder-számot idézte. A tényleges
`reserve-adr` futás **0215–0220**-at adott — a „raw audio" témájú ADR
[**ADR 0217**](../adr/0217-analysis-raw-audio-retention.md) (fejlécében
saját maga rögzíti: „a teljes hatos blokk 0200–0205-ről 0215–0220-ra
tolódott", és a hatóköre pontosan §28.1-28.3 — nyers audio, temp fájl,
fájlnév —, ami ennek a körnek a §5 pont 4 fájlnév-privacy döntését
megalapozza). A hivatkozás mindenhol **ADR 0202 → ADR 0217**-re javítva.

### R2 — `AnalysisInputSource` MÁR LÉTEZIK — a brief tévesen sorolja új típusnak

Mérve: `lib/features/audio_analysis/domain/analysis_mode.dart:5-10` egy
**már merge-elt** (E06-R02), négyértékű enumot definiál —
`AnalysisInputSource { microphone, importedFile, practiceSession,
songSession }` —, amit hat helyen már használ élő kód és teszt
(`analysis_input_summary.dart:24` mezőtípusa, `legacy_analyze_adapter.dart:102`,
`analysis_document_codec.dart:112` az enum `.values`-ét dekódolja, három
teszt). A `public.dart` MA is exportálja (`export
'domain/analysis_mode.dart';`). Az eredeti §3/§4 szövege („`AnalysisInput`
sealed hierarchia … + `AnalysisInputSource` + …") ezt új típusként sorolta
fel — ha az implementer szó szerint követi és egy MÁSODIK
`AnalysisInputSource`-t ír az új `analysis_input.dart`-ba, a `public.dart`
két azonos nevű exportja **ambiguous export** fordítási hibát ad.

A SDD saját literálja (§9.3, 07-epic-06-audio-analysis-2.md:844-865) is
**megerősíti az újrahasználatot, nem újradefiniálást**: `PcmAnalysisInput`
mezője pontosan `final AnalysisInputSource source;` — vagyis a Kör 5
`AnalysisInput`-jának a MEGLÉVŐ enumot kell importálnia.

**Javítás — §3 és §4 az irányadó, az alábbi pontosítással:** az új
`domain/analysis_input.dart` a meglévő `AnalysisInputSource`-t **importálja**
(`analysis_mode.dart`-ból), nem definiálja újra. A két konkrét variáns a
meglévő négy érték egy-egy részhalmazát hordozza: `PcmAnalysisInput.source`
∈ {`microphone`, `practiceSession`, `songSession`} (a PCM már dekódolva
érkezik), `FileAnalysisInput.source` = `importedFile` (nyers bájtok, a
gateway dekódol). Az enum értékkészlete **változatlan** — nincs additív
bővítés ezen a ponton.

### R3 — a FailureCode-lista hiányos a §6 acceptance-hez képest

A §5 pont 1 hét additív kódot sorol, de a §6 acceptance criteria egy
NYOLCADIKAT is névvel követel (`clipTooShort`, a hossz-küszöb hármas
minimum-ágán), a maximum-ágának (hossz felső korlát túllépése) pedig
**egyáltalán nincs neve**. `clipTooLong` (a `clipTooShort` mintájára) a
repóban sehol nem foglalt (`grep -rn "clipTooLong" lib/ docs/` → 0 találat) —
**nem ütközik** a domain MÁR LÉTEZŐ, más típusú
`CapabilityUnavailableReason.clipTooShort`-jával
(`domain/analysis_capability.dart:22`, E06-R02): más enum, más névtér, csak
a leíró szó közös. **Javítás:** a §5 pont 1 additív kódlistája kilenc elemű:
`unsupportedFormat`, `unsupportedBitDepth`, `truncatedChunk`, `invalidRiff`,
`chunkSizeOutOfBounds`, `fileTooLarge`, `nonFiniteSample`, `clipTooShort`,
`clipTooLong` — az utolsó kettő a `AnalysisInputValidator` hossz-küszöbének
két ága (alul/felül).

### Egyéb §2 állítás újra mérve — egyezik

`lib/core/audio/codec/wav_decoder.dart` pontosan 104 sor, a leírt fejléc-
(`bytes.length < 44`) és chunk-ciklus (`off + 8 <= bytes.length`) feltételek
bitre egyeznek; `analyze_providers.dart:195-200` (`analyzeImported`) néma
no-op-ja üres PCM-re/`sampleRate <= 0`-ra és felvétel közben egyaránt
igazolva; `clip_recorder.dart:15` `final List<double> _buffer = []`
korlátlan puffere igazolva; `app_failure.dart` `FailureCode`/
`PermissionFailure`/`AudioFailure` megléte igazolva, a fájl saját
doc-commentje kimondja az additív-only szabályt; a hivatkozott
`test/features/analyze/wav_decoder_test.dart` létezik (139 sor). Nincs
további revízió.

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
`FileAnalysisInput`) a MEGLÉVŐ `AnalysisInputSource` enumot újrahasználva
(`domain/analysis_mode.dart`, ld. §0.0 R2 — **importálva, nem
újradefiniálva**) + privacy-flagelt `sourceDisplayName`;
`AudioDecoderGateway` (typed failure, **soha nem null**);
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
| `.../domain/analysis_input.dart` | ÚJ | sealed input (a meglévő `AnalysisInputSource`-t importálva, §0.0 R2) + privacy flag |
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
   gateway/validator `AppResult<DecodedAudio>`-t ad, a failure-kód megnevezi
   az okot — kilenc additív `FailureCode` érték (§0.0 R3):
   `unsupportedFormat`, `unsupportedBitDepth`, `truncatedChunk`,
   `invalidRiff`, `chunkSizeOutOfBounds`, `fileTooLarge`, `nonFiniteSample`,
   `clipTooShort` (hossz **alul**), `clipTooLong` (hossz **fölül**).
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
4. **A fájlnév privacy-metaadat** (ADR 0217, SDD §28.3): a domain
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
      **28 799 999 / 28 800 000 / 28 800 001** minta (a `28 800 000` átmegy,
      a **határ inkluzív**, a `28 800 001` → `clipTooLong`, §0.0 R3).
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
| A maximum hossz `<` helyett `<=` | a **pontosan** 28 800 000 mintás cella |
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

### Módosítások

- `analysis_input.dart`: sealed PCM- és file-input boundary, a meglévő
  `AnalysisInputSource` importjával; a `SourceDisplayName` minden
  diagnosztikus `toString()`-ben redaktált.
- `input_limits.dart` és `analysis_input_validator.dart`: a verziózott
  méret-, sample-rate-, csatorna- és inkluzív hosszkorlátok; mikrofonos
  non-finite minta nullázása `nonFiniteSample` warninggal, importált minta
  typed failurerel.
- `wav_decoder_adapter.dart` és `audio_decoder_gateway.dart`: RIFF/chunk
  bounds-check az örökölt core dekóder hívása előtt, `null` helyett typed
  failure, fájlnév-logger nélküli kapu.
- `app_failure.dart` és `public.dart`: a kilenc additív audio failure-kód és
  az új public contractok exportja.
- Új gateway-, validator- és 500-es, `PROPERTY_SEED`-vezérelt fuzz tesztek.

### Futtatott ellenőrzések

- `flutter gen-l10n` — exit 0; kizárólag a gitignore-olt localizációs
  generátumkimenetet állította elő a Flutter-tesztek fordításához.
- `flutter test test/features/audio_analysis/data test/property/analysis_input_fuzz_property_test.dart`
  — **20 teszt zöld** (formátum-, malformed-, méret-, hossz-, NaN- és fuzz
  mátrix).
- `flutter test test/features/analyze/wav_decoder_test.dart` — **5 teszt
  zöld**, a fagyasztott core codec változatlan.
- A fájlméret-őr valódi-sértés próbája: a `<=` ideiglenes `<`-re rontásakor a
  pontosan `maxFileBytes` cella piros lett; visszaállítás után ugyanaz a célzott
  teszt zöld.
- `tools/round-gate.sh test/features/audio_analysis test/property test/core test/features/analyze`
  — **zöld**: format, analyze, a négy külön tesztútvonal és architecture.

### Eltérés és nem futtatott ellenőrzés

- Nincs scope- vagy architekturális eltérés.
- CI-dispatch és merge nem implementer-feladat; az orchesztrátor az exact-SHA
  kör-commit után végzi el.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r05-input-abstraction-and-safe-import-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
