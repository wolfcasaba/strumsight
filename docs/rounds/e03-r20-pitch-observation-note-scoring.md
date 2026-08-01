# E03-R20 — Pitch observation és monophonic note scoring

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 20; §22
- **Branch:** `codex/e03-r20-pitch-observation-note-scoring`
- **Előfeltétel:** E03-R19 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

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

- YIN a Tuner belső `engine/dsp` fájljában él; Tuner provider/UI import tilos.
- A thresholdök és observation latency a planning baseline-on nincsenek note-trainer fixture benchmarkkal bizonyítva.
- R19 controller külön scoring módot tud orchestrálni.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

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

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Közös DSP kiemelés paritást tart; Tuner behavior thresholdja benchmark/ADR nélkül nem változik.
2. Target sounding pitch = written MIDI + transposition + capo effect; display fret/tuning külön warning policy.
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

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r20-pitch-observation-note-scoring-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
