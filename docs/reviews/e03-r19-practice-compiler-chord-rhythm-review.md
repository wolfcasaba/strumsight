# Review — E03-R19 — Practice compiler és chord/rhythm trainer

- **Kör:** E03-R19 · **Branch:** `codex/e03-r19-practice-compiler-chord-rhythm`
- **Implementer:** Codex (gpt-5.6-terra) · **Reviewer:** Claude Opus 4.8 (orchestrátor, független review)
- **Implementációs commit:** `65966f7` · **Pre-flight commitok:** `19c23ce`, `75279d5`, `b30972b`, `2e1a059`
- **Verdikt:** **APPROVED** — nyitott BLOCKER/MAJOR nincs; három NOTE follow-upra.
- **Dátum:** 2026-08-04

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=65966f7`, `summary=… célzott
round-gate zöld`. A `dirty_files=1` a brief §10 handoff-editje volt, a `done`
előtt commitolva — a working tree a jelzéskor tiszta. Bemondásra semmit nem
fogadtam el; a gate-et magam futtattam (§2).

## 2. Gate-újrafuttatás (izolált `/tmp/review-e03-r19` klón)

`tools/prepare-flutter-generated.sh` (gitignore-olt l10n/package output
helyreállítása) → `tools/round-gate.sh test/features/song_trainer/application/trainer
test/features/song_trainer/domain test/features/practice`:

| Lépés | Eredmény |
|---|---|
| format | zöld |
| analyze | zöld |
| test song_trainer/application/trainer | zöld |
| test song_trainer/domain | zöld (163) |
| test practice | zöld (902) |
| architecture | zöld (12 allowlisted, változatlan) |

Az architektúra-guard 12 allowlistelt deviációja VÁLTOZATLAN — a `public.dart`
additív exportok NEM hoztak új cross-feature sértést (R1 boundary tartott).

## 3. Scope-audit (allowed_paths ellen)

`git diff --stat 1d3c1ac..65966f7` — 11 fájl, mind az (R4-korrigált)
allowed_paths listán:
`practice/public.dart` (additív), `application/trainer/{song_practice_compiler,
song_result_mapper,song_trainer_controller,song_trainer_result,song_trainer_state}.dart`,
`domain/models/song_event_reference.dart`, `application/song_trainer_providers.dart`,
`test/…/trainer/{song_practice_compiler,song_trainer_controller}_test.dart`,
a brief doc. **Listán kívüli fájl nincs.** A merge-elt domain-purity és
cross-feature guardokat NEM módosította.

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium (§6) | Bizonyíték | Állapot |
|---|---|---|
| Legacy 4/4 és 3/4, több chord, section/range, tempo/meter change, speed determinisztikusan fordul | `song_practice_compiler_test.dart:27` (4/4 multi-chord), `:85` (120→60 bpm + 4/4→3/4 change, **független SongTimeMap onset-referenciával** `:137-148`), speed → `effectiveTempo` `:151` | ✅ |
| Hat track-profil helyes PracticeDefinition profil | compiler-teszt: chord-only (chordChanges), chord+direction (chordProgression), chord+unknown direction (chordChanges, direction null), strum-only (strumPattern/legacyLearnParity), note-onset (rhythmOnly), playback-only | ✅ |
| Minden verdict visszamappelhető song revision/track/event/measure/section | `song_result_mapper.dart` fail-closed (`throw StateError` hiányzó referenciára); measure/section aggregáció; `@loopIndex` suffix-kezelés | ✅ |
| Pause/resume, seek→új attempt, backing+scoring, mic denied, background | `song_trainer_controller_test.dart:40` (count-in/backing/pause/resume/seek/background), `:110` (permission denied → permissionRequired, backing nem indul), **valós `PracticeSessionController`-rel** | ✅ |
| Nincs Practice internal import / duplikált scorer; playback-only mic call count 0 | controller csak `practice/public.dart`-ot importál; `:155` teszt: `microphoneProviderReads == 0`; provider strukturálisan sosem olvassa a Practice family-t playback-only-nál | ✅ |

## 5. Próbatesztek / mért invariánsok

- **R5 reference-tempo (anti-reward-hacking):** a compiler-teszt `:137-148`
  FÜGGETLEN reference-számítást végez (`SongTimeMap` onset → `µs·bpm·480/µsPerMin`
  `.round()`) és `definition.events.first.position.ticks == independentTicks`-et
  vár — nem bemásolt zöld output. A 120→60 bpm + 3/4 meterváltó range a start
  tempóra (60) normalizál, `totalBeats=1440`, `effectiveTempo=30` (speed 0.5). ✔
- **Additív export ellenőrzés:** `public.dart` diff kizárólag új `export`/`show`-
  bővítés; egyetlen Practice forrásfájl sem módosult (R1 tartott). ✔
- **A9 réteg-tisztaság:** a controller/compiler forrása nem tartalmaz
  `AudioSessionCoordinator`/`StrumEngine`/gateway direkt hivatkozást; a Practice
  session INJEKTÁLT. ✔ (architektúra-guard zöld megerősíti.)
- **Idempotens finalize:** `_operationId`/`_attemptId`/`_finalizedOperationId`
  őrök; teszt `:129` „finalizes once when finish and a late tick race". ✔

## 6. Architektúra + termékhatárok

- Domain-tisztaság: `song_event_reference.dart` csak `song_id.dart`-ot importál
  (tiszta song-koordináta) — a merge-elt domain-purity guard zöld. ✔
- A Practice-típust importáló fájlok az `application/trainer/` rétegben (R4). ✔
- Mic/lease: playback-only path sosem konstruál Practice sessiont → gateway/mic
  nem resolvál; scoring a publikus Practice controller family-n át (a gateway/
  mic életciklust a Practice birtokolja). ✔
- Lifecycle: `SongTrainerController.dispose()` minden subscriptiont + a Practice
  sessiont + a stream-controllereket lezárja; provider `autoDispose`. ✔

## 7. Leletek

| # | Súly | Fájl:sor | Leírás | Javasolt irány |
|---|---|---|---|---|
| N1 | NOTE | `test/…/trainer/song_trainer_integration_test.dart` | Az allowed_paths listázta ÚJ integration-tesztfájl nem készült el. A `song_trainer_controller_test.dart` VALÓS `PracticeSessionController`-rel (fake clock/tick/recorder/gateway) futtatja a Practice-integrációt, tehát az integrációs út tesztelt. | Follow-up: a nevesített fájl vagy szülessen meg (pl. provider-graph override-os wiring-teszt), vagy a brief §4 vegye ki explicit — coverage nem sérül. |
| N2 | NOTE | `song_trainer_controller.dart:270-285` | `_finishAndFinalize` legfeljebb 3 `Future.delayed(Duration.zero)` fordulóig várja a `_practiceSession.result`-ot; ha az nem áll elő 3 mikrotask alatt, a finalize csendben nem emittál eredményt/`NavigateToSongTrainerResult`-ot. Kockázat alacsony (a valós Practice a terminál-átmenetkor állítja a `result`-ot, a race-teszt zöld). | Follow-up: kimerült retry esetén explicit jelzés (assert/log/failure state), ne néma no-op. |
| N3 | NOTE | `song_practice_compiler.dart:95-98` | Két distinct song-event ugyanarra a practice-tickre esve `ArgumentError`-t dob (reference tempón egyidejű események). Determinisztikus, fail-closed — de legitim többszólamú egyidejű onsetnél meglepő lehet. | Follow-up: ha egyidejű események várhatók, dedup/merge-szemantika dokumentálva; e körben elfogadható. |

BLOCKER: nincs. MAJOR: nincs. MINOR: nincs. A három NOTE nem blokkol.

## 8. Merge-döntés

A zöld kapu (ADR 0052) minden lokális eleme zöld (izolált klón, §2), a scope
tiszta, az acceptance tételesen bizonyított, nyitott BLOCKER/MAJOR nincs.
Merge a kör-branch exact `headSha`-jára futó CI (`build-apk.yml`) zöldje után,
`origin/main` mozdulatlanság-ellenőrzéssel. **APPROVED.**
