# E03-R19 — Practice compiler és chord/rhythm trainer

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 19; §21
- **Branch:** `codex/e03-r19-practice-compiler-chord-rhythm`
- **Előfeltétel:** E03-R18 merge és stabil Practice public contract
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/public.dart",
  "lib/features/song_trainer/domain/services/song_practice_compiler.dart",
  "lib/features/song_trainer/domain/models/song_event_reference.dart",
  "lib/features/song_trainer/domain/models/song_trainer_result.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_controller.dart",
  "lib/features/song_trainer/application/trainer/song_trainer_state.dart",
  "lib/features/song_trainer/application/trainer/song_result_mapper.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "test/features/song_trainer/domain/song_practice_compiler_test.dart",
  "test/features/song_trainer/application/trainer/song_trainer_controller_test.dart",
  "test/features/song_trainer/application/trainer/song_trainer_integration_test.dart",
  "test/features/practice/presentation/practice_presentation_guard_test.dart",
  "docs/rounds/e03-r19-practice-compiler-chord-rhythm.md",
]
gate_tests = [
  "test/features/song_trainer/domain/song_practice_compiler_test.dart",
  "test/features/song_trainer/application/trainer",
  "test/features/practice",
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

- A planning baseline Practice public boundaryje nem bizonyítottan teljes; pre-flight hard gate.
- R18 transport, R03 time map és R17 setup config elérhető.
- Chord/rhythm/direction scorert tilos Song Trainerben újraimplementálni.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

SongDocument track/range determinisztikus PracticeDefinition fordítása, publikus Practice Engine orchestration és source-referenciás chord/rhythm result mapping.

## 2. Jelenlegi állapot

- A planning baseline Practice public boundaryje nem bizonyítottan teljes; pre-flight hard gate.
- R18 transport, R03 time map és R17 setup config elérhető.
- Chord/rhythm/direction scorert tilos Song Trainerben újraimplementálni.

## 3. Scope

**Benne:**

- SongPracticeCompiler és SongEventReference
- SongTrainerController state/effect orchestration
- PracticeResult→SongTrainerResult és measure/section aggregation
- count-in/pre-roll, scoring-only mic lease, playback-only session

**Kívül — ebben a körben TILOS:**

- monophonic pitch scoring
- trainer screen és heatmap
- Practice feature belső import
- új chord/rhythm/direction scorer

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/practice/public.dart` | feltételes meglévő | csak auditált additív public export |
| `lib/features/song_trainer/domain/services/song_practice_compiler.dart` | ÚJ | Song→PracticeDefinition |
| `lib/features/song_trainer/domain/models/song_event_reference.dart` | ÚJ | source mapping |
| `lib/features/song_trainer/domain/models/song_trainer_result.dart` | ÚJ | song result |
| `lib/features/song_trainer/application/trainer/song_trainer_controller.dart` | ÚJ | transport+Practice orchestration |
| `lib/features/song_trainer/application/trainer/song_trainer_state.dart` | ÚJ | session state |
| `lib/features/song_trainer/application/trainer/song_result_mapper.dart` | ÚJ | measure/section mapping |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R18-ból | production wiring |
| `test/features/song_trainer/domain/song_practice_compiler_test.dart` | ÚJ | compile matrix |
| `test/features/song_trainer/application/trainer/song_trainer_controller_test.dart` | ÚJ | state/effect/lifecycle |
| `test/features/song_trainer/application/trainer/song_trainer_integration_test.dart` | ÚJ | Practice integration |
| `test/features/practice/presentation/practice_presentation_guard_test.dart` | meglévő | cross-feature guard |
| `docs/rounds/e03-r19-practice-compiler-chord-rhythm.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Pre-flight minden szükséges PracticeDefinition/target/config/controller/result symbolt `public.dart` exporton bizonyít; hiány esetén STOP és bridge brief-revízió.
2. Compiler pure, nem mutál documentet, range startot local beat 0-ra visz és minden target source mappinget őriz.
3. Scoring dimenzió kizárólag capability szerint aktív; unknown direction nem kap direction score-t.
4. Playback-only nem kér microphone lease/permissiont; scoring mode ugyanazt az AudioSessionCoordinator contractot használja.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Legacy 4/4 és 3/4, több chord, section/range, tempo/meter change és speed determinisztikusan fordul.
- [ ] Chord+direction, chord unknown direction, chord-only, strum-only és note-onset rhythm-only helyes PracticeDefinition profilt ad.
- [ ] Minden verdict visszamappelhető song revision/track/event/measure/section értékre.
- [ ] Pause/resume, seek új attempt, backing+scoring, mic denied és background state/effect tesztelt.
- [ ] Nincs Practice internal import vagy duplikált scorer; playback-only mic provider call count 0.

### Kötelező megkülönböztető mátrix

| Track/range | Compiler output | Scoring dimenzió |
|---|---|---|
| chord+direction | chord+strum target | chord+rhythm+direction |
| chord+unknown direction | chord+timing | chord+rhythm, direction n.a. |
| chord-only | chord positions | chord+rhythm |
| strum-only | strum positions | rhythm+direction, ha ismert |
| note onset | onset positions | rhythm-only |
| playback-only | display/transport | minden scorer off, mic 0 |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/domain/song_practice_compiler_test.dart test/features/song_trainer/application/trainer test/features/practice
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Hard-auditáld a Practice public contractot; hiány esetén állj meg.
2. Írd meg a compiler/source-map RED matrixot és a playback-only mic call-count tesztet.
3. Implementáld a pure compilert és result mappert kizárólag public Practice típusokkal.
4. Implementáld a controller state/effectet transport és Practice orchestrationnel.
5. Futtasd a Song Trainer + teljes Practice regressziós gate-et.

Javasolt commit: `feat(song-trainer): compile songs into chord and rhythm practice sessions`.

## 9. Kockázatok

- Epic 2 contract drift miatt a tervezett signature nem létezik; belső import nem megoldás.
- Seek/pause late callback duplán finalize-olhat; operation/attempt ID és idempotency kell.
- Measure aggregáció source mapping nélkül hamisan sikeres lehet; minden target referenciája mérendő.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r19-practice-compiler-chord-rhythm-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
