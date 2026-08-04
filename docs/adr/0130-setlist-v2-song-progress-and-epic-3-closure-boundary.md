# ADR 0130 — Setlist V2, revision-aware Song progress és Epic 3 zárási boundary

- **Státusz:** Elfogadva (E03-R22 pre-flight, 2026-08-04)
- **Kör:** E03-R22 — Setlist V2, progressintegráció és Epic-zárás
- **Implementer motor:** Codex (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`)
- **Kontext-ADR-ek:** [0116](0116-legacy-setlist-adapter.md)
  (R06 legacy setlist adapter — lossless, nem-perzisztens dokumentum-mapping),
  [0056](0056-audio-session-lease.md)
  (AudioSessionCoordinator + exkluzív mic-lease),
  [0127](0127-song-practice-compiler-and-practice-engine-orchestration-boundary.md)
  (Practice session orchestration a `SongTrainerController`-ből),
  [0129](0129-song-trainer-ui-loop-speed-and-result-boundary.md)
  (idempotens `SongProgressCommitter` + resume boundary).

## Kontextus

Az E03 song-trainer törzs kész (R06 legacy adapter, R07 storage, R17 setup,
R18 transport, R19 practice compiler, R20 note scoring, R21 UI/loop/result +
idempotens progress-commit contract). Hiányzik a felhasználó felé mérhető
**Setlist V2** (Practice/Performance), a **revision-aware, verziózott Song
progress**, ennek a **napi cél / streak / Practice History** integrációja a
tényleges publikus wiringen, a teljes quality/security/performance evidencia és
a tényszerű **Epic 3 completion report**. R22 ezt zárja — a scoring/DSP
algoritmusok érintése nélkül.

**Pre-flight méréssel (2026-08-04, baseline `main` @ `3a5762a`) igazolt tények:**

1. **A `progress/public.dart` ma NEM exportálja a napi cél providert.** A
   `lib/features/progress/public.dart` (mérve) csak a practice-log contractot
   exportálja (`practice_entry`, `practice_stats`, `practice_log_provider`). A
   `dailyGoalProvider` (`NotifierProvider<DailyGoalController, int>`) és a
   `dailyGoalActiveSecondsProvider` (`Provider.family<int, int>`) a
   `lib/features/progress/providers/daily_goal_provider.dart:33/50`-ben él, a
   publikus barrelen kívül. A brief §6 „daily goal a tényleges public
   wiringen integrált" előírása ezért a `progress/public.dart` **additív
   exportját** igényli — pontosan a §4-ben jelzett auditált publikus boundary.
   Trainer-oldali napi-cél másolat továbbra is TILOS (§3). Belső
   `progress/providers/...` közvetlen import a song_trainer-ből TILOS; kizárólag
   a barrel additív exportján át.

2. **A streak-kredit egyetlen belépési pontja a `StreakController.recordPracticeToday`.**
   A `streak/public.dart` exportálja a `providers/streak_provider.dart`-ot;
   `Future<bool> recordPracticeToday([DateTime? now])`
   (`lib/features/streak/providers/streak_provider.dart:23`). Nincs külön
   „eligibility" szimbólum: a **streak-eligibility a hívó döntése** — a
   playback-only Performance út **nem hívja** a `recordPracticeToday`-t
   (streak credit 0, matrix „playback-only" sor), a scored Practice út igen.
   Ez a boundary már a publikus barrelben van; nem igényel új exportot.

3. **A mikrofon-lease egyetlen megszerzője a `MicCapture`.**
   `MicCapture` → `AudioSessionCoordinator.acquire(...)`
   (`lib/core/audio/mic_capture.dart:82`) — az egyetlen `.acquire(` a
   song_trainer + core/audio úton. A Setlist Practice mód a meglévő injektált
   gateway/trainer úton fut (a gateway sosem `acquire`-el, ADR 0128 §2, 0129 §2);
   a **Performance (playback-only) mód NEM konstruál scoring gateway-t**, tehát
   mic-igénye 0. A „Practice vs Performance mic policy külön" acceptance
   (matrix) ezen a mért tényen áll: a lease-tulajdon a `MicCapture`-nél marad,
   a mód-különbség a gateway konstrukciójának meglétén/hiányán mérendő.

4. **A verziózott progress terminal-commit idempotenciája már adott.** Az
   idempotens `SongProgressCommitter` (exactly-once idempotency key, R21/ADR 0129,
   `song_progress_committer.dart`) a bázis; R22 a `SongPracticeRecord`
   verziózását, a measure/section aggregációt, a revision-aware mappinget és a
   **perzisztens** `song_progress_repository` + `file_song_progress_repository`
   réteget adja hozzá. A „duplicate terminal callback → egy record/daily/streak/
   history commit" matrix-sor ezen az idempotency-kulcson mérendő.

5. **A legacy setlist adapter (R06/ADR 0116) ma szándékosan nem perzisztál.**
   `legacy_setlist_adapter.dart` doc-commentje: „The adapter never persists
   anything (§3 … no V2 repository write in this round)". R22 ezt kiterjeszti a
   perzisztens V2 setlist-mappingre (`file_setlist_repository` + `setlist_repository`
   contract), a lossless order/duplicate/missing-skip fidelity megtartásával
   (ADR 0116 kötött contractja NEM lazul: order preserved, duplicates survive,
   missing SKIPPED nem dob).

6. **Az ÚJ fájlok mind hiányoznak, a meglévők jelen vannak** (mérve, 22/22
   allowed-path egyezés): a `song_setlist/setlist_result/song_practice_record`
   modellek, a két repository contract, a controllerek, az aggregator/mapper és
   a két data-repo mind ÚJ; a `legacy_setlist_adapter` (R06), `song_result_screen`
   (R21), `song_trainer_providers` (R21), a három `public.dart` barrel és a
   `check_architecture.dart` létező, additívan bővítendő fájlok. A
   `check_song_schema.dart`/`check_song_fixture_licenses.dart` CI-gate-ek ÚJak.

## Döntés

1. **Setlist V2 fidelity a legacy contract fölött.** A Setlist item order és a
   duplicate megmarad; a hiányzó song/asset recoverable skip/repair, nem
   session-crash. A legacy→V2 migráció order/duplicate/missing parity zöld és
   restart-safe, az ADR 0116 lossless mapping kiterjesztéseként.
2. **Practice vs Performance külön mód, per-song result.** Practice mód trainer
   configot indít (scoring, mic-igény a scored úton); Performance mód
   playback/navigáció (playback-only, **nincs** scoring gateway → mic 0). Minden
   dal külön `SetlistResult`-ot kap.
3. **Revision-aware, verziózott progress.** A progress key = song ID + revision +
   source measure/event; a revision mapping csak bizonyítottan stabil
   referenciára visz át, más adat archived/stale (nincs hamis átvitel törölt/
   ambiguous measure ID-knál). A measure/section aggregate determinisztikus és
   idempotens.
4. **Integráció csak publikus/production wiringen.** A napi cél a
   `progress/public.dart` **additív** napi-cél exportján, a streak-kredit a már
   exportált `recordPracticeToday`-en, a Practice History a `practice/public.dart`
   recording/aggregator felületén át integrált. Belső cross-feature import
   hiányzó bridge esetén STOP (nem belső import). Puszta playback nem
   streak-eligible.
5. **Kontrollált Epic-zárás.** A feature flag production bekapcsolása és a legacy
   Song/Setlist kód/storage törlése **külön release/cleanup döntés** — ebben a
   körben TILOS. A completion report csak mért tényt ír (import subset, GP út,
   codec, capability, limit, migráció, performance, nyitott korlát), minden
   támogatási állításhoz evidence-linkkel. A valós device checklist minden sora
   külön mért evidencia vagy név szerinti release blocker.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen (brief §5).

## Következmények

- **+:** Felhasználó felé mérhető Setlist V2 (Practice/Performance) + verziózott,
  revision-aware Song progress a napi cél / streak / Practice History valós
  publikus wiringjén, teljes quality/security/performance evidenciával és
  tényszerű Epic 3 completion reporttal.
- **+:** A napi-cél és Practice-History integráció additív publikus exporton
  megy — nincs belső cross-feature import, nincs allowlist-deviáció.
- **−:** A kör nagy diffje review-vakságot okozhat; a §8 szeletek külön
  commitolhatók, de egy körgate + független review szükséges. Minden központi
  invariánst (order/duplicate parity, idempotency, revision no-false-transfer,
  playback-only streak 0) eldobható mutációval vagy független reference-
  számítással kell pirosra váltani — bemásolt zöld nem evidencia.
- **−:** A CI-zöld nem bizonyít Bluetooth/audio/storage device viselkedést; a
  valós device checklist a végső acceptance, szintetikus teszt nem helyettesíti.
- A feature-flag production rollout és a legacy delete R22 után, külön release/
  cleanup döntésre marad.
