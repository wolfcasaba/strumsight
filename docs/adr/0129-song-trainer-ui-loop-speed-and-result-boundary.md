# ADR 0129 — Song Trainer UI, loop, Speed Builder és result boundary

- **Státusz:** Elfogadva (E03-R21 pre-flight, 2026-08-04)
- **Kör:** E03-R21 — Trainer UI, loop, Speed Builder és result
- **Implementer motor:** MiniMax M3 (örökölt kézi override, `mm-round.sh`)
- **Kontext-ADR-ek:** [0056](0056-audio-session-lease.md)
  (AudioSessionCoordinator + exkluzív mic-lease),
  [0125](0125-song-trainer-setup-configuration-boundary.md)
  (TrainerConfig capability gating),
  [0127](0127-song-practice-compiler-and-practice-engine-orchestration-boundary.md)
  (Practice session orchestration a `SongTrainerController`-ből),
  [0128](0128-shared-pitch-observation-dsp-and-monophonic-note-scoring.md)
  (közös pitch-observation DSP + monophonic note scoring).

## Kontextus

Az E03 song-trainer törzs (R18 transport, R19 chord/rhythm, R20 note scoring)
kész, de nincs teljes, akadálymentes trainer-felület, sem A–B/section loop, sem
publikus Speed Builder, sem result/heatmap/problem-retry, sem idempotens
progress/resume boundary. R21 ezt zárja a **UI + orchestration** rétegen, a
scoring/DSP érintése nélkül.

**Pre-flight méréssel (2026-08-04, baseline `main` @ `fbe1e82`) igazolt tények:**

1. **A trainer-fázis enum tényleges neve `SongTrainerStatus`, és NEM tartalmaz
   `playing`/`error` értéket.** Mért felület
   (`lib/features/song_trainer/application/trainer/song_trainer_state.dart:8`):
   `enum SongTrainerStatus { idle, preparing, permissionRequired, ready,
   countIn, running, paused, completed, cancelled, failed }`. A brief §6 és a
   megkülönböztető mátrix informális UI-fázis-nevei így képződnek le a mért
   enumra: **`playing` → `SongTrainerStatus.running`**, **`error` →
   `SongTrainerStatus.failed`** (a `permissionRequired`/`preparing`/`cancelled`
   is valós, produkált állapot). A `countIn`/`paused`/`completed` bitre
   egyeznek. Nincs dedikált „loop 2/5" enum: a loop-index egy ebben a körben
   épülő UI-mező a state/controller rétegen (mindkettő `allowed_paths`-on).

2. **A mikrofon-lease egyetlen megszerzője a `MicCapture`.**
   `MicCapture._doStart` → `AudioSessionCoordinator.acquire(...)`
   (`lib/core/audio/mic_capture.dart:82`). A `SongTrainerController` **soha nem
   `acquire`-el**: subscription-öket birtokol és a
   `PitchObservationGateway.start/stop` + backing player start/stop láncot
   vezényli. A `dispose()`
   (`song_trainer_controller.dart:214`) minden subscriptiont cancel-el
   (`_practiceSubscription`, `_practiceEffectsSubscription`, `_pitchSubscription`,
   `_transportSubscription`, `_transportEffectsSubscription`), `stopPitchScoring`-ol,
   `_practiceSession?.dispose()`-ol és minden streamet `close`-ol. A „route
   leave/dispose után 0 mic/player/subscription" acceptance tehát a
   **subscription/gateway/player** rétegen mérendő (a lease nem a controlleré);
   a lease-tulajdon a `MicCapture`-nél marad (analóg a Practice úttal, ADR 0128
   §2).

3. **A `SpeedBuilderEngine` és állapotai ma NEM exportáltak a Practice publikus
   contractján.** `SpeedBuilderEngine`
   (`lib/features/practice/domain/service/speed_builder_engine.dart:7`),
   `SpeedBuilderState`/`SpeedBuilderStatus`
   (`.../domain/model/speed_builder_state.dart`), `SpeedBuilderPolicy`
   (`.../domain/model/speed_builder_policy.dart`) léteznek, de a
   `lib/features/practice/public.dart` (mérve) nem exportálja őket. A „Speed
   Builder csak publikus contracton" előírás ezért a `practice/public.dart`
   **additív exportját** igényli — pontosan a §4-ben jelzett auditált publikus
   boundary. Saját (trainer-oldali) Speed Builder policy továbbra is TILOS (§3).

4. **A backing-rate capability kapuja a `PlaybackCapabilities.supportsRate`.**
   `bool supportsRate(double rate)`
   (`lib/features/song_trainer/data/playback/playback_capabilities.dart:26`).
   A „backing rate capability hiányában speed disabled indoklással" acceptance
   ezen a metóduson mérendő, nem feltételezett mezőn.

5. **A trainer route a `FeatureFlags.songTrainerV2Enabled` flag mögött él**
   (`lib/app/config/feature_flags.dart:18/50/79` — minden környezetben `false`;
   `lib/app/routing/app_router.dart:57`). R21 a route-ot a meglévő flag mögött
   drótozza; **feature-flag production rollout TILOS (§3)**.

## Döntés

1. **Windowolt lane-render.** A chord/strum/note/tab lane csak a viewport +
   buffer window eseményeit rendereli; a teljes dal widgetlistája tilos (long-song
   child-count méréssel bizonyítva, nem kis dallal).
2. **Egyetlen authoritative commit owner + idempotency key.** Minden loop külön
   attempt ID-t/result-ot kap; a terminal callback és a progress commit
   idempotency key alapján pontosan egyszer fut, akárhány producer hívja. Az
   idempotens boundary a `song_progress_committer.dart`.
3. **Akadálymentes result.** A heatmap szín MELLETT label/icon/text semanticsot
   ad; a screen-reader live feedback throttled (túl gyakori update tilos).
4. **Biztonságos resume checkpoint.** Resume biztonságos időközönként és
   pause/stopkor; a scoring state nem állítható vissza fél attemptként;
   revision-mismatch explicit invalidáció (`song_resume_repository.dart`).
5. **Speed Builder csak publikus contracton.** A trainer a Practice
   `SpeedBuilderEngine`-t kizárólag a `practice/public.dart` additív exportján
   át használja; nincs belső cross-feature import, nincs trainer-saját policy.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen (brief §5).

## Következmények

- **+:** Teljes, akadálymentes trainer/result UI, A–B/section loop, publikus
  Speed Builder és idempotens progress/resume boundary — a scoring/DSP
  változatlanul hagyásával.
- **+:** A commit-owner + idempotency key kizárja a több-producerből érkező
  terminal callback dupla-commitját (R9 kockázat).
- **−:** A windowing és a semantics-throttling méréshez dedikált teszt kell
  (long-song child-count, reader-update frekvencia) — bemásolt zöld nem
  evidencia.
- A végleges progress-repository/Setlist integráció R22-re marad; R21 csak az
  idempotens commit/resume contractot adja.
