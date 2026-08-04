# E03-R20 — Pitch observation és monophonic note scoring

- **Státusz:** **PLANNING** (pre-flight mérve 2026-08-04, baseline: `main` @ `bd4bb4a`; korábbi tervezési baseline `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 20; §22
- **Branch:** `codex/e03-r20-pitch-observation-note-scoring`
- **Előfeltétel:** E03-R19 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/audio/pitch/pitch_observation.dart",
  "lib/core/audio/pitch/pitch_observation_config.dart",
  "lib/core/audio/pitch/pitch_observation_gateway.dart",
  "lib/core/audio/dsp/yin_pitch_detector.dart",
  "lib/features/tuner/engine/dsp/yin_pitch_detector.dart",
  "lib/features/tuner/engine/dsp/tuner_analyzer.dart",
  "lib/features/song_trainer/domain/services/monophonic_note_scorer.dart",
  "lib/features/song_trainer/domain/models/note_scoring_models.dart",
  "lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_controller.dart",
  "lib/features/song_trainer/presentation/widgets/note_lane.dart",
  "tool/benchmarks/song_trainer_pitch_benchmark.dart",
  "docs/baseline/epic-03-pitch-observation-benchmark.md",
  "test/core/audio/dsp/yin_pitch_detector_test.dart",
  "test/features/tuner/dsp/yin_test.dart",
  "test/features/song_trainer/domain/monophonic_note_scorer_test.dart",
  "test/features/song_trainer/data/audio/live_pitch_observation_gateway_test.dart",
  "test/features/song_trainer/application/trainer/song_note_trainer_test.dart",
  "test/fixtures/audio/song_trainer/pitch_fixture_manifest.json",
  "docs/rounds/e03-r20-pitch-observation-note-scoring.md",
]
gate_tests = [
  "test/core/audio/dsp",
  "test/features/tuner",
  "test/features/song_trainer/domain/monophonic_note_scorer_test.dart",
  "test/features/song_trainer/data/audio",
  "test/features/song_trainer/application/trainer/song_note_trainer_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold minden útvonal, public symbol, state producer, recorder-input,
> resource owner és numerikus cella mai állapotát. Drift esetén dokumentáld
> §0.0-ban, javítsd a scope/fájllistát, majd commitold a `PLANNING` briefet
> a körbranchre az implementer előtt. A `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, hiányzó public contract/fixture/device,
ellentmondó acceptance vagy megkülönböztetésre alkalmatlan teszt esetén
`stopped`; nincs néma scope-tágítás vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight mérve 2026-08-04, baseline `main` @ `bd4bb4a` (E03-R19 merge után).
Előre kiosztott ADR: nincs → [ADR 0128](../adr/0128-shared-pitch-observation-dsp-and-monophonic-note-scoring.md)
ebben a pre-flightban megírva.** Minden `allowed_paths` útvonal létezés-ellenőrzött
(a 13 „ÚJ" fájl mérve hiányzik, a 3 „meglévő" mérve létezik), minden hivatkozott
publikus szimbólum, state producer, resource owner és numerikus cella
`rg`-vel újramérve. A négy mért drift és feloldása:

**R1 — Közös YIN DSP extrakció, Tuner-paritás delegálással.** A pure YIN mért
publikus felülete `lib/features/tuner/engine/dsp/yin_pitch_detector.dart`-ban:
`class YinPitchDetector({required int sampleRate, int bufferSize = 4096, double
threshold = 0.12, double minFrequency = 60})`, `double? detect(Float64List)`,
`double clarity` mező, top-level `noteForFrequency(double f0, {double a4 = 440})`.
Rajta kívül **egyedül** a `tuner_analyzer.dart` és a
`test/features/tuner/dsp/yin_test.dart` importálja (mérve; Tuner provider/UI nem).
Feloldás: a pure DSP a `lib/core/audio/dsp/yin_pitch_detector.dart` alá kerül
**változatlan algoritmussal + default paraméterekkel**, a tuner-fájl delegál/
re-exportál → bitre azonos Tuner viselkedés (ADR 0128 D1).

**R2 — A mic-lease tulajdonosa a `MicCapture`, nem a gateway.** Mérve: a lease-t
egyedül `MicCapture._doStart` szerzi `AudioSessionCoordinator.acquire`-ral
(`lib/core/audio/mic_capture.dart:82`); a Practice scoring-analóg
`LivePracticeObservationGateway` **nem** birtokol lease-t, a `StrumEngine`
`LiveFrame`-jére iratkozik (`AudioOwner.live`). Feloldás: a
`live_pitch_observation_gateway.dart` **injektált** mic/frame forrásból fogyaszt,
`acquire`-t soha nem hív; „közös lease" acceptance = injektált fake
MicCapture/lease idempotens `start`/`stop`/`dispose` életciklusa (ADR 0128 D3).

**R3 — Nincs song-trainer `AudioOwner` érték; a production-drótozás halasztott.**
Mérve: `AudioOwner` = {`live`, `tuner`, `analyzeRecorder`, `latencyCalibration`,
`diagnostics`} (`audio_session_lease.dart:5`); sem ez, sem a `createMicCapture`
gazdája (`audio_providers.dart`) **nincs** az `allowed_paths`-on. Feloldás: új
`AudioOwner` érték és e két core-fájl szerkesztése **tilos zóna** ebben a körben;
a production provider-drótozás + bármely új `AudioOwner` a Trainer UI-körre
(R21) halasztva (R17–R19 „hívó UI/runner még nincs" mintája). Kívül esést az
implementer `stopped`-dal jelez, nem néma tágítással.

**R4 — Nincs `transposition` forrásmező; sounding-target = `midiPitch`.** Mérve:
`grep -rniE "transpos"` a domainben csak `Chord` display-transpozíciót ad;
`SongNoteEvent.midiPitch` (0–127, „canonical scoring input") az írott alap,
`SongMetadata.capo` (0–15) létezik, `SongInstrument.tuning` opcionális; a
`ChordEvent` concert pitch-en tárol. Feloldás (a §5 D2-t finomítja): a scorer
**már feloldott** target MIDI-t kap tiszta függvényként; a
`written + transposition + capo` feloldás a controller-integrációs rétegé a
létező mezőkből, `transposition` tag **0** (nincs forrásmező → ebben a körben
**nem hozunk létre** újat), capo/tuning a §22.6 tab-warning policy szerint
(ADR 0128 D4). Új tárolt domain-mező tilos.

A fenti négy revízió a kör **saját, még nem merge-elt** briefjét és az ebben a
pre-flightban írt ADR 0128-at érinti (orchestrátor-autonómia, ADR 0087 §2) —
merge-elt döntést nem módosít.

## 1. Cél

Közös audio boundary mögötti, benchmarkolt pitch observation és tiszta, latency-kompenzált monophonic note scorer integrálása a tuner regressziója és polyphonic false scoring nélkül.

## 2. Jelenlegi állapot

- YIN a Tuner belső `engine/dsp` fájljában él; Tuner provider/UI import tilos.
- A thresholdök és observation latency a planning baseline-on nincsenek note-trainer fixture benchmarkkal bizonyítva.
- R19 controller külön scoring módot tud orchestrálni.

## 3. Scope

**Benne:**

- core PitchObservation/Config/Gateway és YIN DSP boundary
- live gateway közös audio lease-szel
- MonophonicNoteScorer és benchmarkolt pitch/onset/coverage/extra-note policy
- controller integration és minimális note lane feedback

**Kívül — ebben a körben TILOS:**

- polyphonic pitch transcription
- Tuner UI/provider import
- threshold találomra választása
- teljes R21 Trainer UI

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/core/audio/pitch/pitch_observation.dart` | ÚJ | közös observation model |
| `lib/core/audio/pitch/pitch_observation_config.dart` | ÚJ | note/tuner config boundary |
| `lib/core/audio/pitch/pitch_observation_gateway.dart` | ÚJ | gateway contract |
| `lib/core/audio/dsp/yin_pitch_detector.dart` | ÚJ | kiemelt pure DSP |
| `lib/features/tuner/engine/dsp/yin_pitch_detector.dart` | meglévő | delegálás/compatibility |
| `lib/features/tuner/engine/dsp/tuner_analyzer.dart` | meglévő | közös DSP bekötés |
| `lib/features/song_trainer/domain/services/monophonic_note_scorer.dart` | ÚJ | pure scorer |
| `lib/features/song_trainer/domain/models/note_scoring_models.dart` | ÚJ | grades/result |
| `lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart` | ÚJ | mic/DSP adapter |
| `lib/features/song_trainer/application/trainer/song_trainer_controller.dart` | R19-ből | note mode orchestration |
| `lib/features/song_trainer/presentation/widgets/note_lane.dart` | ÚJ | minimális feedback |
| `tool/benchmarks/song_trainer_pitch_benchmark.dart` | ÚJ | fixture benchmark |
| `docs/baseline/epic-03-pitch-observation-benchmark.md` | ÚJ | latency/distribution evidence |
| `test/core/audio/dsp/yin_pitch_detector_test.dart` | ÚJ | közös DSP |
| `test/features/tuner/dsp/yin_test.dart` | meglévő | tuner regression |
| `test/features/song_trainer/domain/monophonic_note_scorer_test.dart` | ÚJ | deterministic scoring |
| `test/features/song_trainer/data/audio/live_pitch_observation_gateway_test.dart` | ÚJ | lease/lifecycle |
| `test/features/song_trainer/application/trainer/song_note_trainer_test.dart` | ÚJ | integration |
| `test/fixtures/audio/song_trainer/pitch_fixture_manifest.json` | ÚJ | provenance/labels |
| `docs/rounds/e03-r20-pitch-observation-note-scoring.md` | meglévő | §10 handoff |
| `docs/adr/0128-shared-pitch-observation-dsp-and-monophonic-note-scoring.md` | ÚJ (pre-flight, **orchestrátor** — NEM implementer-diff, NEM a TOML `allowed_paths`-on) | közös DSP/gateway/scorer döntés |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Közös DSP kiemelés paritást tart; Tuner behavior thresholdja benchmark/ADR nélkül nem változik.
2. Target sounding pitch = written MIDI + transposition + capo effect; display fret/tuning külön warning policy. **(§0.0 R4 / ADR 0128 D4 finomítás: nincs `transposition` forrásmező a domainben — a `transposition` tag `0`, a scorer már feloldott target MIDI-t kap; új tárolt mező tilos.)**
3. Polyphonic range hard disable; scorer nem választ hangot overlapből.
4. Pitch/onset/coverage/extra-note threshold kizárólag fixture benchmarkból, derived boundary matrixszal.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] E2/A2/E4/chromatic és early/late/half-step/octave/short/vibrato/bend/noise/speech/silence/two-note/Drop-D/capo fixture manifest lefedett.
- [ ] Deterministic replay azonos observation streamre bit/stabil resultot ad.
- [ ] Latency compensation a boundary-mátrix szerint; pause/resume/seek/loop új attempt resetel.
- [ ] Speech/noise nem sorozatos correct note; polyphonic range score capability false és scorer nem indul.
- [ ] Gateway közös lease-t használ és minden terminal ágon stop/dispose; teljes Tuner regresszió zöld.

### Kötelező megkülönböztető mátrix

| Származtatott érték | alatta | pontosan rajta | fölötte |
|---|---|---|---|
| abs cents error | exact/near policy | kötött inclusive policy | következő grade |
| compensated onset error | early/in-window | boundary grade | late/outside |
| duration coverage | fail | kötött pass boundary | pass |
| observation latency | kompenzál | max policy | unstable/unsupported |

Minden cella tartalmazza a fixture ID-t, raw timestampet, kompenzált értéket és várt grade-et; értékek géppel számítandók.

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/audio/dsp test/features/tuner test/features/song_trainer/domain/monophonic_note_scorer_test.dart test/features/song_trainer/data/audio test/features/song_trainer/application/trainer/song_note_trainer_test.dart
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Készíts provenance-olt fixture manifestet, benchmark harnesset és mérési reportot.
2. Pre-flightban döntsd el, kell-e ADR a közös DSP/threshold változáshoz; hiányzó evidence-nél STOP.
3. Írd meg a pure scorer boundary/replay és Tuner parity RED teszteket.
4. Emeld ki a DSP contractot, implementáld gatewayt/scorert és controller integrációt.
5. Futtasd a core+tuner+song trainer gate-et; real-device latency evidence-t külön jelöld.

Javasolt commit: `feat(song-trainer): add monophonic pitch and note scoring`.

## 9. Kockázatok

- Tuner lock window onsetre túl lassú; változtatás csak parity+benchmark mellett.
- Audio fixture licenc/privacy és eszközvariancia; manifest és több device class szükséges.
- Shared mic lease kettős startot okozhat; production owner chain audit kötelező.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

### 2026-08-04 — implementáció

| Fájl | Változás és mérce |
|---|---|
| `lib/core/audio/dsp/yin_pitch_detector.dart` | Közös, pure YIN detector és hangnév-függvény a korábbi defaultokkal; `test/core/audio/dsp/yin_pitch_detector_test.dart` összeveti a legacy kimenettel. |
| `lib/core/audio/pitch/pitch_observation.dart` | Immutable timestampelt pitch-observation modell. |
| `lib/core/audio/pitch/pitch_observation_config.dart` | Érvényesített confidence, RMS, frekvencia, stabilitás és latency konfiguráció. |
| `lib/core/audio/pitch/pitch_observation_gateway.dart` | Platformfüggetlen observation-stream és lifecycle contract. |
| `lib/features/tuner/engine/dsp/yin_pitch_detector.dart` | Core YIN re-export a meglévő Tuner importútvonal megtartásához. |
| `lib/features/tuner/engine/dsp/tuner_analyzer.dart` | A core YIN importja; a Tuner regressziós tesztek változatlanul futnak. |
| `lib/features/song_trainer/domain/models/note_scoring_models.dart` | Pitch/onset grade-ek, targetek, update-ek és determinisztikus eredménymodellek. |
| `lib/features/song_trainer/domain/services/monophonic_note_scorer.dart` | Latency-kompenzált, monofón target-scoring és coverage-összesítés; a domain teszt rögzített szekvenciákkal ellenőrzi. |
| `lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart` | Injektált frame/MicCapture adapter, confidence-gate és idempotens lifecycle; a teszt fake lease-szel ellenőrzi a release-ágakat. |
| `lib/features/song_trainer/application/trainer/song_trainer_controller.dart` | Opcionális monofón scoring-session, pause/resume/seek/finish leállítás és `midiPitch + capo` target-feloldás; nincs új transposition mező. |
| `lib/features/song_trainer/presentation/widgets/note_lane.dart` | Minimális, szemantikailag címkézett monofón note-lane szegmensekkel. |
| `test/core/audio/dsp/yin_pitch_detector_test.dart` | Core–legacy YIN és hangnév bitazonos regresszió. |
| `test/features/song_trainer/domain/monophonic_note_scorer_test.dart` | Inclusive küszöbök, latency, miss, coverage, extra note, alacsony confidence és determinisztikus replay. |
| `test/features/song_trainer/data/audio/live_pitch_observation_gateway_test.dart` | Injektált lease/frame forrás start/stop/dispose és latency-határ tesztek. |
| `test/features/song_trainer/application/trainer/song_note_trainer_test.dart` | Controller lifecycle, capo-target, transposition-hiány és polyphonic no-score, valamint note-lane widget teszt. |
| `test/fixtures/audio/song_trainer/pitch_fixture_manifest.json` | 20 determinisztikus observation-fixture: nyers timestamp, kompenzált timestamp és várt grade minden felsorolt SDD-kategóriához. |
| `tool/benchmarks/song_trainer_pitch_benchmark.dart` | Manifest-olvasó referencia-benchmark. |
| `docs/baseline/epic-03-pitch-observation-benchmark.md` | A manifest küszöbei és a mérés hatóköre. |

Futtatott parancsok és tényleges eredmény:

```text
dart run tool/benchmarks/song_trainer_pitch_benchmark.dart
→ 20/20 fixture PASS

tools/round-gate.sh test/core/audio/dsp test/features/tuner test/features/song_trainer/domain/monophonic_note_scorer_test.dart test/features/song_trainer/data/audio test/features/song_trainer/application/trainer/song_note_trainer_test.dart
→ exit 0: format, analyze, az öt célzott tesztcsoport és architecture zöld
```

Eltérés nincs: az `AudioOwner`/provider-drótozás változatlan maradt, a production
UI-bekötés R21-re halasztott. Nem futott a teljes Flutter suite, a randomizált
property gate és a release APK: ezek CI/orchestrátor-kötelezettségek. Valós
Android mikrofon+gitár latency-mérés sem futott; a benchmark dokumentáltan
determininsztikus observation replay, nyers audio nélkül.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r20-pitch-observation-note-scoring-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
