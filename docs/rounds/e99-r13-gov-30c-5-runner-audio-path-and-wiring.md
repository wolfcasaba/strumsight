# E99-R13 (GOV-30c-5) — A runner-határ audió-útja és a V2 lánc bekötése

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-15, friss `main`)
- **Típus:** **governance-kör** — a GOV-30c ÖTÖDIK és ZÁRÓ lépcsője
- **Kör-azonosító:** `E99-R13`. Emberi neve **GOV-30c-5**.
- **Branch:** `<motor>/e99-r13-gov-30c-5-runner-audio-path-and-wiring`
  (a prefix a driver által feloldott TÉNYLEGES implementer neve, ADR 0242 §5.2)
- **Előfeltétel:** `E99-R12` (GOV-30c-4) merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0254`](../adr/0254-analysis-run-request-and-v2-runner-wiring.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**

> **Ez a kör teszi FUTTATHATÓVÁ a V2 elemzést** — de **nem kapcsolja be**.
> Mind a kilenc flag OFF marad; a rollout külön, EMBERI döntés (§5.5).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/application/analysis_isolate_runner.dart",
  "lib/features/audio_analysis/application/v2_analysis_runner.dart",
  "lib/features/audio_analysis/application/analysis_providers.dart",
  "lib/features/audio_analysis/application/analyze_audio_use_case.dart",
  "lib/features/audio_analysis/application/shadow_analysis_runner.dart",
  "test/features/audio_analysis/application/v2_analysis_runner_test.dart",
  "test/features/audio_analysis/application/analysis_isolate_runner_test.dart",
  "test/features/audio_analysis/application/shadow_analysis_runner_test.dart",
  "docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md",
]
gate_tests = [
  "test/features/audio_analysis/application/v2_analysis_runner_test.dart",
  "test/features/audio_analysis/application/analysis_isolate_runner_test.dart",
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

## 1. Cél

A GOV-30c négy lépcsője alatt felépült a teljes, **20 stage-es** V2 lánc, és
a végén `AnalysisDocument` születik. Egyetlen dolog hiányzik: **az audiónak
nincs útja a láncba**, és a provider ezért még mindig `StateError`-t dob.

Ez a kör megnyitja az utat és beköti a láncot.

## 2. Jelenlegi állapot — mért tények

### 2.1 A rés (újramérve, ahogy az ADR 0253 §4 előírta)

```dart
// application/analysis_isolate_runner.dart:33-35
abstract interface class AnalysisRunner {
  AnalysisRunHandle start(AnalysisDocument input);
}
```

```dart
// domain/analysis_input_summary.dart:3
/// Privacy-safe input metadata retained with an analysis document, never PCM.
```

A runner bemenete dokumentum; a dokumentum bemenet-mezője szándékosan nem
hordoz PCM-et; a lánc viszont `ValidatedPcmAnalysisInput`-ból indul. **A rés
változatlanul fennáll.**

### 2.2 A hívói felület KICSI és a minta MÁR OTT VAN

```dart
// application/analyze_audio_use_case.dart:11
AnalysisRunHandle call(AnalysisDocument input) => _runner.start(input);
```

```dart
// application/shadow_analysis_runner.dart:40-46
required AnalysisDocument v2Input, …
final v1Result = await v1Analyze(samples, sampleRate);   // ← a MINTA MÁR ITT VAN
…
final handle = v2Runner.start(v2Input);                  // …de nem megy tovább
```

**Mérve:** a `AnalysisRunner`-t két hely használja
(`AnalyzeAudioUseCase`, `ShadowAnalysisRunner`), és a shadow runner **már
megkapja a `samples`/`sampleRate` párost** a V1-hez. A hiányzó lépés nem
adatgyűjtés, hanem **továbbadás**.

### 2.3 Az izolátum-határ ma JSON-t visz

```dart
// application/analysis_isolate_runner.dart:48-53
typedef AnalysisIsolateSpawner =
    Future<Isolate> Function(SendPort replyTo, String input,
                             AnalysisDocumentIsolateOperation operation);
```

A futtatás: `AnalysisDocumentCodec().encode(input)` → izolátum → `String` →
`decode`. A `List<double>` minta izolátumok között natívan küldhető, tehát a
határ bővíthető anélkül, hogy a dokumentumba kerülne PCM.

### 2.4 A lánc KÉSZ és összeszerelhető

`engine/stages/analysis_stage_phases.dart`: `buildFullAnalysisStages()` (20
stage), `analysisStagePhases` (fázis-térkép), `classifyAnalysisStageFailure`.
A `AnalysisPipeline` a GOV-30c-3 óta elfogadja a 20 stage-et a térképpel.

### 2.5 A flagek ma OFF-on állnak

Az Epic 6 mind a kilenc analysis-flagje `false` minden környezetben. **Ez a
kör egyiket sem mozdítja** (A8).

## 3. Scope

**Benne van:**

1. `AnalysisRunRequest` — a futtatás bemenete: dokumentum-mag +
   `ValidatedPcmAnalysisInput` + opcionális `AnalysisTarget`.
2. `AnalysisRunner.start` áttérése erre a típusra, a két hívóhely igazításával.
3. Az izolátum-határ bővítése úgy, hogy a **minta soha ne kerüljön a
   dokumentumba**.
4. `V2AnalysisRunner` — a 20 stage-es `AnalysisPipeline` futtatása, a
   `AnalysisPipelineResult` → `AnalysisRunResult` fordítással.
5. `analysisV2RunnerProvider` felülírása a valódi runnerrel.
6. Végponttól végpontig teszt: PCM be → `AnalysisDocument` ki.

**NINCS benne (tilos):**

- **Bármely flag `true`-ra állítása.** A rollout külön, EMBERI döntés (§5.5,
  A8). A `lib/core/flags/**` a tilos zónában van.
- `engine/**` bármilyen módosítása — a lánc kész, ez a kör csak hívja.
- `domain/**` módosítása; különösen az `AnalysisInputSummary` „never PCM"
  szabályának lazítása (§5.2, A4).
- Új DSP-matematika (AGENTS.md §9).
- `docs/adr/**`, `tools/**`, `.github/**`, `public.dart`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/analysis_isolate_runner.dart` | a kérés-típus + az izolátum-határ |
| `application/v2_analysis_runner.dart` | **ÚJ** — a 20 stage-es lánc futtatója |
| `application/analysis_providers.dart` | a provider felülírása |
| `application/analyze_audio_use_case.dart` | a szignatúra igazítása |
| `application/shadow_analysis_runner.dart` | a minta továbbadása |
| `test/…/application/v2_analysis_runner_test.dart` | **ÚJ** — végponttól végpontig |
| `test/…/application/analysis_isolate_runner_test.dart` | a bővült határ |
| `test/…/application/shadow_analysis_runner_test.dart` | a továbbadás bizonyítéka |
| `docs/rounds/e99-r13-…md` | a §10 handoff |

**Tilos zóna:** `lib/core/flags/**` · `lib/features/audio_analysis/engine/**` ·
`lib/features/audio_analysis/domain/**` · `public.dart` · `docs/adr/**` ·
`tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0254)

### 5.1 A futtatás bemenete ÖNÁLLÓ típus, nem a dokumentum

```dart
final class AnalysisRunRequest {
  final AnalysisDocument seed;            // identitás, mód, provenance-mag
  final ValidatedPcmAnalysisInput audio;  // CSAK memóriában él
  final AnalysisTarget? target;           // opcionális referencia (ADR 0251 §1)
}
```

`AnalysisRunner.start(AnalysisRunRequest)`.

**NEM elfogadható gyengítés:** a minta beletétele a dokumentumba (akár
átmenetileg, akár base64-ként). A dokumentum perzisztálódik és exportálható —
a §5.2 tiltás ezért abszolút.

### 5.2 A PCM SOHA nem kerül a dokumentumba, és nem is perzisztálódik

Az `AnalysisInputSummary` „never PCM" szabálya **változatlanul él**. A minta a
kérésben utazik a runnerig és onnan az izolátumba, majd a futás végén
eldobódik. A `provenance` és az `input` summary a fingerprintet viszi, nem a
mintát.

**NEM elfogadható gyengítés:** a minta „debug célból" naplózása vagy
ideiglenes fájlba írása.

### 5.3 A lánc a MEGLÉVŐ építőket használja

A `V2AnalysisRunner` a `buildFullAnalysisStages()`, `analysisStagePhases` és
`classifyAnalysisStageFailure` hármast hívja — **nem állít össze saját
stage-listát**, és nem másol classifier-logikát.

**NEM elfogadható gyengítés:** „csak ehhez a futtatáshoz" összeállított,
rövidebb stage-lista. Az két igazságforrást csinálna a láncból.

### 5.4 A cancellation és a progress a MEGLÉVŐ szerződésen megy

Az `AnalysisRunHandle` (`runId`, `progress`, `result`, `cancel()`) változatlan.
A `cancel()` a pipeline `cancellationToken`-jét billenti, és a megszakított
futás **nem ad részleges dokumentumot** (a `AnalysisPipelineResult` már így
viselkedik).

### 5.5 A kör futtathatóvá tesz, de NEM kapcsol be

A provider a valódi runnert adja, de a felhasználói út továbbra is a
kilenc OFF flag mögött van. **A rollout külön, emberi döntés** — a
`lib/core/flags/**` ezért tilos zóna, és az A8 cella méri.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `analysisV2RunnerProvider` VALÓDI runnert ad, nem dob `StateError`-t | `v2_analysis_runner_test.dart` |
| A2 | **PCM be → `AnalysisDocument` ki**, a teljes 20 stage-es láncon | `v2_analysis_runner_test.dart` — végponttól végpontig |
| A3 | A runner a `buildFullAnalysisStages()`-t hívja, nem saját listát | teszt: a stage-ek száma és id-sorrendje egyezik a builderével |
| A4 | A minta SEHOL nem kerül a dokumentumba | teszt: a kimeneti dokumentum kódolt JSON-ja nem tartalmazza a mintákat |
| A5 | A referencia (`target`) átjut és hat | teszt: targettel vs. nélküle — a timing-capability különbözik |
| A6 | `cancel()` után NINCS részleges dokumentum | `v2_analysis_runner_test.dart` |
| A7 | A shadow runner továbbadja a mintát a V2-nek | `shadow_analysis_runner_test.dart` — injektált V2 runner, a kapott kérés audiója azonos a V1-nek adottal |
| A8 | **Egyetlen flag sem mozdult** | `git diff` — a `lib/core/flags/**` érintetlen |
| A9 | Az `engine/**` érintetlen | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A provider marad `StateError`-on | A1 |
| A runner saját, rövidített stage-listát épít | **A3** |
| A minta bekerül a dokumentumba (akár base64-ként) | **A4** |
| A `target` nem jut át a kérésből a seedbe | A5 |
| A megszakított futás részleges dokumentumot ad | A6 |
| A shadow runner a mintát nem adja tovább | A7 |
| A kör „hasznosságból" bekapcsol egy flaget | **A8** |
| A lánc helyett az `engine/`-t módosítja, hogy illeszkedjen | A9 |

**A futtathatóság három kötelező cellája** (a határ: a referencia megléte):

| Cella | Bemenet | Elvárt |
|---|---|---|
| referencia nélkül | PCM, `target == null` | dokumentum SZÜLETIK, timing-capability `unavailable` |
| a határon | PCM, `target` üres `expectedEvents`-szel | ugyanaz — az üres lista nem referencia (ADR 0251 §2) |
| referenciával | PCM + legalább egy `ExpectedEvent` | dokumentum születik, timing-metrikák JELEN vannak |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd bele a mintát
a dokumentum egy mezőjébe → az **A4** cellának PIROSNAK kell lennie → vedd ki.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/application/v2_analysis_runner_test.dart test/features/audio_analysis/application/analysis_isolate_runner_test.dart test/features/audio_analysis/application/shadow_analysis_runner_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli, és a
kör `unknown`-ba fut (L254).

## 8. Implementációs sorrend

1. `AnalysisRunRequest` + a `AnalysisRunner.start` szignatúra, a két hívóhely
   fordíthatóvá tétele (még a régi viselkedéssel).
2. Az izolátum-határ bővítése a mintával, a dokumentum érintetlenül hagyásával.
3. `V2AnalysisRunner` — a meglévő builderekből összeállított pipeline
   futtatása, eredmény-fordítás.
4. A provider felülírása.
5. A shadow runner minta-továbbadása.
6. A §6.1 három cellája + a valódi-sértés próba.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A minta szivárgása.** Ez a kör legfontosabb invariánsa: a dokumentum
  perzisztálódik és exportálható, a PCM nem kerülhet bele. Az A4 a kódolt
  JSON-t vizsgálja, nem a típusokat.
- **A flag bekapcsolásának csábítása.** „Már fut, mutassuk is meg" — a
  rollout emberi döntés, az A8 méri.
- **Az izolátum-payload mérete.** Egy perces 48 kHz-es mono felvétel ~2,9 M
  `double`. Ha a másolás mérhetően lassú, a `TransferableTypedData` a
  megoldás — **de csak ha mérve indokolt**, ne előre optimalizálva.
- **A `cancel()` félkész állapota.** A pipeline már helyesen viselkedik; a
  runner-fordításnak ezt nem szabad elrontania (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
