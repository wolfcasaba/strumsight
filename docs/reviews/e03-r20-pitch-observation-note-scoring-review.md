# Review — E03-R20 Pitch observation és monophonic note scoring

- **Kör:** E03-R20 — Pitch observation és monophonic note scoring
- **Branch:** `codex/e03-r20-pitch-observation-note-scoring`
- **Implementer:** Codex (gpt-5.6-terra) · **Reviewer:** Claude Opus 4.8 (orchestrátor)
- **Implementációs commit:** `45eb5d3` (rebase után `14d3a39` `origin/main` @ `63b8746`-ra)
- **Dátum:** 2026-08-04
- **Módszer:** független, read-only review izolált `/tmp/review-e03-r20` klónban;
  saját kézzel újrafuttatott `tools/round-gate.sh`; scope-audit; eldobható
  mutáció-próbák a központi invariánsokra (ADR 0055 / `sdd-round-review` skill).

## Verdikt: **APPROVED** — nulla OPEN BLOCKER/MAJOR

## 1. Gate (saját kéz, izolált klón)

`tools/round-gate.sh test/core/audio/dsp test/features/tuner
test/features/song_trainer/domain/monophonic_note_scorer_test.dart
test/features/song_trainer/data/audio
test/features/song_trainer/application/trainer/song_note_trainer_test.dart`
→ **exit 0**. format, analyze, mind az öt célzott tesztcsoport és az
architecture (OK, 12 allowlisted deviation) zöld. Független benchmark-reprodukció:
`dart run tool/benchmarks/song_trainer_pitch_benchmark.dart` → **20/20 PASS**.

## 2. Scope-audit

- **20 megváltozott fájl, mind a brief §4 `allowed_paths`-on belül.** Listán
  kívüli fájl nincs.
- **Tilos zóna érintetlen:** `git diff origin/main HEAD` nulla változás a
  `lib/core/audio/lifecycle/audio_session_lease.dart` és a
  `lib/core/audio/audio_providers.dart` fájlokon.
- **Nincs új `AudioOwner` érték:** az enum változatlanul `{live, tuner,
  analyzeRecorder, latencyCalibration, diagnostics}`.
- **Domain purity:** a `song_trainer/domain/` nem importál framework/Riverpod/
  practice-belső szimbólumot; a scorer csak a pure core `PitchObservation`-t
  használja. core↛feature megtartva.

A négy pre-flight §0.0 revízió (R1–R4 / ADR 0128 D1/D3/D4) mérve teljesül:
R1 a tuner YIN mostantól a core fájl tiszta `export`-ja, a core algoritmus
`origin/main`-nel **bitre azonos** (a diff csak kommenteket távolít); R2/R3 a
gateway soha nem hív `.acquire`-t, nincs core-lease/provider edit; R4 a target
= `note.midiPitch + capo`, transposition tag 0, nincs új tárolt mező.

## 3. Acceptance criteria (brief §6)

| Kritérium | Verdikt | Bizonyíték |
|---|---|---|
| Fixture manifest lefedi E2/A2/E4/chromatic/early/late/half-step/octave/short/vibrato/bend/noise/speech/silence/two-note/Drop-D/capo | PASS | `pitch_fixture_manifest.json` — 20 fixture, minden felsorolt kategória (drop-d, capo-two, coverage-boundary 0.6, latency-above-maximum is) |
| Determinisztikus replay → bit-stabil result | PASS | `monophonic_note_scorer_test.dart` „replaying the same observation sequence yields an equal result" + value-equal `NoteScoringResult` |
| Latency compensation a boundary-mátrix szerint; pause/resume/seek/loop új attempt | PASS | manifest-teszt géppel számított `compensatedAt`; `song_note_trainer_test.dart` pause→stop, resume→start, seek→stop, friss scorer minden startra |
| Speech/noise nem sorozatos correct; polyphonic capability false és scorer nem indul | PASS | clarity/RMS gate (0.8499 → noStablePitch); speech/silence/transition-noise → noStablePitch/missed; „controller never starts a polyphonic pitch session" → startCalls 0 |
| Gateway közös lease + stop/dispose minden terminal ágon; teljes Tuner regresszió zöld | PASS | `live_pitch_observation_gateway_test.dart` egyszeri acquire/egyszeri release valódi `AudioSessionCoordinator`-ral; a gateway sosem hív `.acquire`-t; tuner suite zöld |

## 4. Mutáció-próbák (eldobható, visszaállítva)

| Invariáns | Mutáció | RED? |
|---|---|---|
| Scorer inclusive exact-cents boundary | `cents <= exactCents` → `<` | **IGEN** (2 teszt bukott: inclusive-boundary + clean-a2 @ cents=12.0) |
| YIN viselkedési paritás | `sampleRate/tauF` → `/(tauF+1)` | **IGEN** (2 tuner teszt bukott) |
| YIN threshold default 0.12 → 0.20 | numerikus default | **NEM** → NOTE 1 |

## 5. Leletek (mind nem-blokkoló)

- **NOTE 1** — a YIN `threshold` numerikus default (0.12) nincs teszttel
  kipinnelve (`lib/core/audio/dsp/yin_pitch_detector.dart:9`): a tiszta-tónusú
  fixture-ök CMNDF-dipje mindkét küszöb alatt van, így a default értéket semmi
  nem rögzíti. A *viselkedés* őrzött (formula-mutáció → RED). Javaslat: explicit
  assert a `threshold`/`bufferSize`/`minFrequency` defaultokra, vagy egy
  marginális-jelű fixture. Alacsony súly (algoritmus bitre azonos + re-export).
- **NOTE 2** — a paritás-teszt szerkezetileg tautologikus
  (`test/core/audio/dsp/yin_pitch_detector_test.dart`): a re-export miatt a core
  és a tuner típus ugyanaz az osztály, a „bit-identical" teszt konstrukció
  szerint nem bukhat. Szándékot dokumentál, divergencia-őrt nem ad; a NOTE 1
  javaslatába olvad.
- **MINOR 3** — a polyphonic-disable teszt nem izolálja az `isMonophonic`
  kaput (`test/.../song_note_trainer_test.dart:89`): a no-start eset
  `scoring:false, isMonophonic:false, notes:[]` — mindhárom külön letiltja a
  scoringot. A guard (`capability.scoring && capability.isMonophonic`) inspekció
  szerint helyes, de nincs teszt, ami CSAK a polyphonic flagre bizonyítaná a
  no-startot. Javaslat: `scoring:true, isMonophonic:false, notes` nem-üres eset,
  `startCalls == 0`. Follow-up, nem hizlalja a merge-diffet.
- **NOTE 4** — az onset felső határ pontosan-rajta (+80000µs onTime) nincs
  fixture-rel kipinnelve (a −80000 onTime, −80001 early, +80001 late igen); a
  mátrix egyéb tengelyei teljesen kipinnelve.

## 6. Follow-up (a kör NEM blokkolt)

NOTE 1/2/4 + MINOR 3 opcionális teszt-keményítés egy későbbi körre. Egyik sem
gátolja a merge-et: nulla BLOCKER/MAJOR, tilos zóna tiszta, scope tiszta, gate
zöld, a központi invariánsok független RED-mutációval bizonyítva.
