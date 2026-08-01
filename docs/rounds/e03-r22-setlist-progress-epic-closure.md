# E03-R22 — Setlist V2, progressintegráció és Epic-zárás

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 22; §25–35
- **Branch:** `codex/e03-r22-setlist-progress-epic-closure`
- **Előfeltétel:** E03-R21 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/domain/models/song_setlist.dart",
  "lib/features/song_trainer/domain/models/setlist_result.dart",
  "lib/features/song_trainer/domain/models/song_practice_record.dart",
  "lib/features/song_trainer/domain/repositories/setlist_repository.dart",
  "lib/features/song_trainer/domain/repositories/song_progress_repository.dart",
  "lib/features/song_trainer/application/setlists/setlist_controller.dart",
  "lib/features/song_trainer/application/setlists/setlist_session_controller.dart",
  "lib/features/song_trainer/application/progress/song_progress_aggregator.dart",
  "lib/features/song_trainer/application/progress/song_revision_progress_mapper.dart",
  "lib/features/song_trainer/data/local/file_setlist_repository.dart",
  "lib/features/song_trainer/data/local/file_song_progress_repository.dart",
  "lib/features/song_trainer/data/migration/legacy_setlist_adapter.dart",
  "lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart",
  "lib/features/song_trainer/presentation/screens/setlist_session_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_result_screen.dart",
  "lib/features/progress/public.dart",
  "lib/features/streak/public.dart",
  "lib/features/practice/public.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "tool/check_architecture.dart",
  "tool/ci/check_song_schema.dart",
  "tool/ci/check_song_fixture_licenses.dart",
  ".github/workflows/build-apk.yml",
  "test/features/song_trainer/application/setlists/setlist_session_controller_test.dart",
  "test/features/song_trainer/data/local/file_setlist_repository_test.dart",
  "test/features/song_trainer/application/progress/song_progress_test.dart",
  "test/features/song_trainer/data/local/song_progress_wiring_test.dart",
  "test/features/song_trainer/integration/legacy_setlist_migration_test.dart",
  "test/features/song_trainer/integration/song_progress_public_integration_test.dart",
  "test/features/song_trainer/security/import_security_suite_test.dart",
  "test/features/song_trainer/performance/long_song_performance_test.dart",
  "test/property/song_progress_property_test.dart",
  "README.md",
  "docs/sdd/00-index.md",
  "docs/sdd/epic-03-completion-report.md",
  "docs/execution/06-requirements-traceability-matrix.md",
  "HANDOFF.md",
  "docs/rounds/e03-r22-setlist-progress-epic-closure.md",
]
gate_tests = [
  "test/features/song_trainer",
  "test/features/songs",
  "test/features/practice",
  "test/property",
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

- R06 legacy setlist adapter, R07 storage, R21 trainer result/commit contract rendelkezésre áll.
- A current Progress, Streak és Practice History csak saját `public.dart` boundaryn auditálható.
- Feature flag production enable és legacy delete külön release/cleanup döntés.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Setlist V2 Practice/Performance, revision-aware Song progress, daily-goal/streak/history integráció, teljes quality/security/performance evidence és tényszerű Epic completion report.

## 2. Jelenlegi állapot

- R06 legacy setlist adapter, R07 storage, R21 trainer result/commit contract rendelkezésre áll.
- A current Progress, Streak és Practice History csak saját `public.dart` boundaryn auditálható.
- Feature flag production enable és legacy delete külön release/cleanup döntés.

## 3. Scope

**Benne:**

- Setlist V2 model/repository/editor/session/result és legacy migration
- versioned SongPracticeRecord, measure/section/revision mapping
- daily goal, streak eligibility és Practice History V2 public integráció
- CI/architecture/schema/recovery/performance gate, docs és valódi device checklist

**Kívül — ebben a körben TILOS:**

- feature flag production bekapcsolása
- legacy Song/Setlist code vagy storage törlése
- polyphonic pitch scoring
- valós device evidence szintetikus teszttel kipipálása

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/models/song_setlist.dart` | ÚJ | Setlist V2/item/override |
| `lib/features/song_trainer/domain/models/setlist_result.dart` | ÚJ | per-song result |
| `lib/features/song_trainer/domain/models/song_practice_record.dart` | ÚJ | versioned progress |
| `lib/features/song_trainer/domain/repositories/setlist_repository.dart` | ÚJ | setlist contract |
| `lib/features/song_trainer/domain/repositories/song_progress_repository.dart` | ÚJ | progress contract |
| `lib/features/song_trainer/application/setlists/setlist_controller.dart` | ÚJ | editor/list |
| `lib/features/song_trainer/application/setlists/setlist_session_controller.dart` | ÚJ | Practice/Performance |
| `lib/features/song_trainer/application/progress/song_progress_aggregator.dart` | ÚJ | measure/section |
| `lib/features/song_trainer/application/progress/song_revision_progress_mapper.dart` | ÚJ | revision mapping |
| `lib/features/song_trainer/data/local/file_setlist_repository.dart` | ÚJ | atomic setlist storage |
| `lib/features/song_trainer/data/local/file_song_progress_repository.dart` | ÚJ | progress storage |
| `lib/features/song_trainer/data/migration/legacy_setlist_adapter.dart` | R06-ból | persistent V2 mapping |
| `lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart` | ÚJ | list/editor |
| `lib/features/song_trainer/presentation/screens/setlist_session_screen.dart` | ÚJ | Practice/Performance |
| `lib/features/song_trainer/presentation/screens/song_result_screen.dart` | R21-ből | progress/setlist result |
| `lib/features/progress/public.dart` | meglévő | daily goal public bridge |
| `lib/features/streak/public.dart` | meglévő | eligibility/credit bridge |
| `lib/features/practice/public.dart` | R21-ből | Practice History public bridge |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R21-ből | production wiring |
| `lib/l10n/app_en.arb` | meglévő | EN copy |
| `lib/l10n/app_hu.arb` | meglévő | HU copy |
| `tool/check_architecture.dart` | meglévő | Song Trainer dependency gate |
| `tool/ci/check_song_schema.dart` | ÚJ | schema snapshot gate |
| `tool/ci/check_song_fixture_licenses.dart` | ÚJ | fixture provenance gate |
| `.github/workflows/build-apk.yml` | meglévő | fixture/security/schema/recovery/perf CI |
| `test/features/song_trainer/application/setlists/setlist_session_controller_test.dart` | ÚJ | mode/boundary |
| `test/features/song_trainer/data/local/file_setlist_repository_test.dart` | ÚJ | atomic persistence |
| `test/features/song_trainer/application/progress/song_progress_test.dart` | ÚJ | aggregate/revision/idempotency |
| `test/features/song_trainer/data/local/song_progress_wiring_test.dart` | ÚJ | production re-open |
| `test/features/song_trainer/integration/legacy_setlist_migration_test.dart` | ÚJ | migration |
| `test/features/song_trainer/integration/song_progress_public_integration_test.dart` | ÚJ | daily/streak/history |
| `test/features/song_trainer/security/import_security_suite_test.dart` | ÚJ | malicious aggregate |
| `test/features/song_trainer/performance/long_song_performance_test.dart` | ÚJ | baseline |
| `test/property/song_progress_property_test.dart` | ÚJ | idempotent aggregate |
| `README.md` | meglévő | user-facing capability |
| `docs/sdd/00-index.md` | meglévő | Epic status/index |
| `docs/sdd/epic-03-completion-report.md` | ÚJ | measured completion |
| `docs/execution/06-requirements-traceability-matrix.md` | meglévő | DoD evidence |
| `HANDOFF.md` | meglévő | pipeline handoff a lezárási protokoll szerint |
| `docs/rounds/e03-r22-setlist-progress-epic-closure.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Setlist item order és duplicate megmarad; missing song/asset recoverable, nem session-crash.
2. Practice mode trainer configot indít, Performance mode playback/navigáció; minden dal külön result.
3. Progress key song ID+revision+source measure/event; revision mapping csak bizonyított stabil referenciára, más adat archived/stale.
4. Puszta playback nem streak-eligible; progress terminal commit idempotens.
5. Device checklist minden sora külön mért evidencia vagy explicit release blocker.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Setlist repository/editor, item override, Practice/Performance, missing reference és per-song result működik.
- [ ] Legacy setlist sorrend/duplicate/missing mapping parity zöld és restart-safe.
- [ ] SongPracticeRecord verziózott; measure/section aggregate és revision-aware mapping determinisztikus/idempotens.
- [ ] Daily goal, streak eligibility és Practice History a tényleges public/production wiringen integrált; playback-only nem kap streaket.
- [ ] Importer/security/architecture/schema/recovery/property/full suite/APK exact-SHA CI zöld; long-song baseline dokumentált.
- [ ] Completion report a tényleges import subsetet, GP utat, codecet, capabilityt, limitet, migrációt, performance-t és nyitott korlátot írja.
- [ ] Valós device checklist lezárt, vagy minden hiányzó sora release blockerként név szerint szerepel.

### Kötelező megkülönböztető mátrix

| Setlist/progress eset | Kötelező eredmény |
|---|---|
| duplicate song item | két külön item/result, eredeti sorrend |
| missing song/asset | recoverable skip/repair, session folytatható |
| Practice vs Performance | scoring config / playback-only, mic policy külön |
| duplicate terminal callback | egy record/daily/streak/history commit |
| same revision retry | idempotens |
| új revision stabil measure IDs | dokumentált mapping |
| új revision törölt/ambiguous IDs | stale/archive, nincs hamis átvitel |
| playback-only | progress policy szerint, streak credit 0 |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer test/features/songs test/features/practice test/property
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Írd meg a Setlist model/repository/session és legacy migration RED teszteket.
2. Írd meg a revision/idempotency és public production-wiring RED teszteket.
3. Implementáld a Setlist és progress domain/data/application/UI szeletet.
4. Bővítsd a quality gate-eket és futtasd a lokális round gate-et.
5. Az orchestrátor futtassa exact-SHA CI-t; hajtsd végre és dokumentáld a valós device checklistet.
6. Csak a mért állapotra frissítsd README/index/RTM/HANDOFF/completion reportot; flag enable és delete maradjon külön.

Javasolt commit: `docs(song-trainer): close Epic 3 and prepare controlled rollout`.

## 9. Kockázatok

- A kör nagy diffje review-vakságot okozhat; §8 szerinti szeletek külön commitolhatók, de egy körgate/review szükséges.
- Cross-feature progress/streak belső import kísértés; public bridge hiányánál STOP.
- CI-zöld nem bizonyít Bluetooth/audio/storage device viselkedést.
- Completion report könnyen aspirációt ír tényként; minden támogatási állítás evidence linket kap.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r22-setlist-progress-epic-closure-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
