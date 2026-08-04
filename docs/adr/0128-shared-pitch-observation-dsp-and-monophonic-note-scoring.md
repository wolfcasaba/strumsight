# ADR 0128 — Közös pitch-observation DSP boundary és monophonic note-scoring

- **Státusz:** Elfogadva (E03-R20 pre-flight, 2026-08-04)
- **Kör:** E03-R20 — Pitch observation és monophonic note scoring
- **Kontext-ADR-ek:** [0056](0056-audio-session-lease.md)
  (AudioSessionCoordinator + exkluzív mic-lease), [0057](0057-core-music-domain.md)
  /[0058](0058-core-audio-domain.md) (közös zenei/audio domain),
  [0113](0113-song-track-event-model.md) (SongNoteEvent + canonical Tuning
  contract), [0125](0125-song-trainer-setup-configuration-boundary.md)
  (TrainerConfig capability gating), [0127](0127-song-practice-compiler-and-practice-engine-orchestration-boundary.md)
  (Practice session orchestration a SongTrainerControllerből).

## Kontextus

A Song Trainer egyhangú (monophonic) note trackjeit őszintén kell pontozni:
pitch correctness, onset timing, duration coverage, missed/extra note és
unstable pitch. Ehhez (1) a Tunerben már élő YIN pitch-DSP-t közös core audio
boundary mögé kell emelni a Tuner regressziója nélkül, (2) egy note-trainerre
hangolt, alacsony latency-jű, confidence-gated observation gateway kell, és
(3) egy tiszta, determinisztikus, latency-kompenzált scorer, amely polyphonic
tartományban nem ad hamis pontot.

**Pre-flight méréssel (2026-08-04, baseline `main` @ `bd4bb4a`) igazolt tények:**

1. **A YIN pure DSP-je ma a Tuner belsejében él, egyetlen külső importőrrel.**
   `lib/features/tuner/engine/dsp/yin_pitch_detector.dart` — mért publikus
   felület: `class YinPitchDetector({required int sampleRate, int
   bufferSize = 4096, double threshold = 0.12, double minFrequency = 60})`,
   `double? detect(Float64List buffer)`, `double clarity` mező, és a
   top-level `({String note, double cents}) noteForFrequency(double f0,
   {double a4 = 440})`. Az `engine/dsp/yin_pitch_detector.dart`-ot rajta kívül
   **egyedül** a `test/features/tuner/dsp/yin_test.dart` és a
   `tuner_analyzer.dart` importálja (`grep` mérve); Tuner provider/UI nem.

2. **A mikrofon-lease egyetlen megszerzője a `MicCapture`.** A lease-t
   `MicCapture._doStart` szerzi `AudioSessionCoordinator.acquire(...)`-ral
   (`lib/core/audio/mic_capture.dart:82`); a motorok a
   `createMicCapture(ref, AudioOwner owner)`-ből
   (`lib/core/audio/audio_providers.dart:43`) kapják. A mért analóg — a
   Practice scoring útja — **nem** birtokol saját lease-t: a
   `LivePracticeObservationGateway` a `StrumEngine` `LiveFrame` streamjére
   iratkozik fel, és a lease a `RealStrumEngine` `AudioOwner.live` MicCapture-jén
   marad (`practice_session_controller.dart` §3: „the audio session lease is
   **NOT** owned here — `MicCapture` acquires it on the gateway's behalf").

3. **Az `AudioOwner` enumnak nincs song-trainer/pitch értéke.**
   `lib/core/audio/lifecycle/audio_session_lease.dart:5` — az enum mért
   értékei: `live`, `tuner`, `analyzeRecorder`, `latencyCalibration`,
   `diagnostics`. Sem ez a fájl, sem a `createMicCapture` gazdája
   (`audio_providers.dart`) **nincs** az E03-R20 `allowed_paths`-on.

4. **Nincs `transposition` forrásmező a domainben.** `grep -rniE "transpos"`
   a `song_trainer/domain/`-ban és a `core/music/`-ban csak a `Chord`
   display-transpozíciót találja; `SongInstrument` (name + opcionális
   `Tuning`), `SongTrack`, `SongMetadata` (`capo` 0–15) és `SongNoteEvent`
   (`midiPitch` 0–127, „the canonical scoring input", SDD §11.4) egyikén sincs
   transposition mező. A `ChordEvent` mérve concert (sounding) pitch-en tárol
   (`chord_event.dart:8`).

## Döntés

### D1 — Közös YIN DSP boundary, delegálással megőrzött Tuner-paritás

A pure YIN estimator és a `noteForFrequency` a
`lib/core/audio/dsp/yin_pitch_detector.dart` alá kerül **változatlan
algoritmussal és változatlan default paraméterekkel** (`bufferSize = 4096`,
`threshold = 0.12`, `minFrequency = 60`). A régi
`lib/features/tuner/engine/dsp/yin_pitch_detector.dart` a core típusra
**delegál/re-exportál**, így a `TunerAnalyzer` és a
`test/features/tuner/dsp/yin_test.dart` viselkedése **bitre azonos** marad.
A Tuner threshold/lock-viselkedés benchmark + ADR nélkül **nem** változik
(brief §5.1). A közös DSP a `docs/rag/chunks/` chunk-008 igazságát követi;
paraméterhangolás csak ADR + chunk-frissítés mellett.

### D2 — PitchObservation model és gateway a közös core audio pitch boundary alatt

`lib/core/audio/pitch/` — `PitchObservation` (SDD §22.2:
`observedAt`, `frequencyHz`, `midiPitch`, `centsFromNearest`, `clarity`,
`rms`, `stable`), `PitchObservationConfig` (note-trainerre hangolt, alacsony
latency-jű, confidence-gated küszöbökkel; minden numerikus küszöb §22.4/§22.9
fixture benchmarkból), és a `PitchObservationGateway` interfész
(`Stream<PitchObservation> get observations; Future<AppResult<void>>
start(PitchObservationConfig); Future<AppResult<void>> stop();`, SDD §22.3).
A gateway és config a Live/Tuner detektortól függetlenül tesztelhető.

### D3 — A lease tulajdonlása a `MicCapture`-nél marad; a gateway soha nem szerez lease-t

A `live_pitch_observation_gateway.dart` (song_trainer/data/audio) egy
**injektált** mic/frame forrásból (MicCapture vagy raw frame stream +
permission gateway) fogyaszt; **soha nem hívja** az
`AudioSessionCoordinator.acquire`-t, és nem konstruál saját lease-t (D2.
mérés — a `MicCapture` az egyetlen megszerző). Az acceptance „közös lease"
kritériuma injektált fake MicCapture/lease életciklusával igazolt
(idempotens `start`/`stop`/`dispose`, nincs kettős acquire, minden terminal
ágon release). **Új `AudioOwner` érték és a
`audio_session_lease.dart`/`audio_providers.dart` szerkesztése tilos** ebben a
körben (mindkettő `allowed_paths`-on kívül → tilos zóna); a production
provider-drótozás és bármely új `AudioOwner` érték a Trainer UI-drótozó körre
(R21) halasztva — pontosan az R17–R19 „hívó UI/runner még nincs" mintája.

### D4 — Sounding-target: `midiPitch` az írott alap, transposition = 0, capo külön policy

Mivel a domainben **nincs** `transposition` forrásmező (D4. mérés), a scorer
egy **már feloldott** target MIDI pitch-et kap tiszta függvényként; a
`sounding target = written MIDI + transposition + capo effect` (SDD §22.5)
feloldást a controller-integrációs réteg számolja a **létező** mezőkből:
`SongNoteEvent.midiPitch` az írott pitch, a `transposition` tag **0** (nincs
forrásmező — ebben a körben **nem hozunk létre** újat), a capo/tuning a
§22.6 policy szerint (a pitch target továbbra is értékelhető; tuning-mismatch
tab-warningot kap; bizonytalan fret nem jelenik meg). A scorer maga a
`midiPitch`-re nézve determinisztikus és polyphonic tartományban a scoring
capability **false**, a scorer el sem indul.

### D5 — Küszöbök kizárólag fixture benchmarkból

Minden pitch/onset/coverage/extra-note/latency küszöb a provenance-olt
`test/fixtures/audio/song_trainer/pitch_fixture_manifest.json` + a
`tool/benchmarks/song_trainer_pitch_benchmark.dart` méréséből, a
`docs/baseline/epic-03-pitch-observation-benchmark.md` derived boundary
mátrixával rögzítve. Találomra választott küszöb tilos; a brief §6
megkülönböztető mátrix minden cellája fixture ID + raw + kompenzált + várt
grade géppel számított hármassal.

## Következmények

- A Tuner változatlan; a közös DSP-t a note-trainer és a Tuner egyaránt
  használja, egyetlen igazságforrásból.
- A pitch scorer őszinte: polyphonic tartományban nincs pontszám, beszéd/noise
  nem sorozatos correct note (clarity/stability gate).
- A production mic-drótozás (és bármely új `AudioOwner`) egy későbbi kör
  felelőssége; ez a kör flag/hívó nélküli, production-viselkedés-semleges.
- A transposition mint tárolt mező nem létezik; ha egy jövőbeli import-forrás
  igényli, önálló körben, saját ADR-rel vezetendő be — nem itt, csendben.
