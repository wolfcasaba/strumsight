# E03-R16 — Song Editor V2

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 16; §6.1, §27.5
- **Branch:** `codex/e03-r16-song-editor-v2`
- **Előfeltétel:** E03-R15 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/application/editor/song_editor_controller.dart",
  "lib/features/song_trainer/application/editor/song_editor_state.dart",
  "lib/features/song_trainer/application/editor/editor_command.dart",
  "lib/features/song_trainer/application/editor/editor_history.dart",
  "lib/features/song_trainer/presentation/screens/song_editor_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_library_screen.dart",
  "lib/features/song_trainer/presentation/widgets/song_metadata_editor.dart",
  "lib/features/song_trainer/presentation/widgets/song_section_editor.dart",
  "lib/features/song_trainer/presentation/widgets/measure_grid.dart",
  "lib/features/song_trainer/presentation/widgets/song_event_editor.dart",
  "lib/features/song_trainer/presentation/widgets/backing_asset_editor.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "lib/app/routing/route_guards.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/song_trainer/application/editor/song_editor_controller_test.dart",
  "test/features/song_trainer/application/editor/editor_history_test.dart",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/song_editor_route_guard_test.dart",
  "test/app/routing/route_guards_test.dart",
  "test/app/routing/app_router_test.dart",
  "docs/rounds/e03-r16-song-editor-v2.md",
  "docs/reviews/e03-r16-song-editor-v2-review.md",
]
gate_tests = [
  "test/features/song_trainer/application/editor",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/song_editor_route_guard_test.dart",
  "test/app/routing/route_guards_test.dart",
  "test/app/routing/app_router_test.dart",
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

- R15 Libraryből V2 dokumentum nyitható; R07 optimistic revision és R05 validation rendelkezésre áll.
- A legacy Song Builder flag fallbackként marad.
- Draft/command/history contract még nincs.

**Módosítás (ADR 0112 önjavító kör, 2026-08-04; E03-R16/H3).** A futtatható
pre-flight mérése szerint az `AppRoutes` katalogizálja a kanonikus editor
útvonalat, az `app_router.dart` regisztrálja, a `SongLibraryScreen` pedig a
Libraryből indítja a dokumentumra célzott megnyitást. E három owner, a route
regresszió `test/app/routing/app_router_test.dart` fájlja és a kötelező,
független review-jelentés addig hiányzott a prepared scope-ból. A §4 és az
`ai-router.allowed_paths` most pontosan ezeket a fájlokat is megnyitja; a
review artefaktumot kizárólag a független reviewer írhatja. A §7 route
regressziós gate-je is a `app_router_test.dart`-tal bővül. Ez scope-helyreállítás,
nem termékkód- vagy mérceváltozás.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Persisted documenttől elkülönített, command-alapú, determinisztikus undo/redo editor metadata-, section-, measure-, chord/strum-, alap note- és backing szerkesztéshez.

## 2. Jelenlegi állapot

- R15 Libraryből V2 dokumentum nyitható; R07 optimistic revision és R05 validation rendelkezésre áll.
- A legacy Song Builder flag fallbackként marad.
- Draft/command/history contract még nincs.

## 3. Scope

**Benne:**

- SongEditorController/State, EditorCommand és limitált history
- metadata/section/measure/chord/strum/tempo/meter/basic note editing
- backing attach/detach, validate+atomic save, conflict
- unsaved route guard és draft snapshot preview

**Kívül — ebben a körben TILOS:**

- teljes notation/tablature editor
- autosave, collaborative merge vagy silent conflict overwrite
- Trainer scoring és transport
- legacy Builder törlése

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/song_trainer/application/editor/song_editor_controller.dart` | ÚJ | editor orchestration |
| `lib/features/song_trainer/application/editor/song_editor_state.dart` | ÚJ | draft/dirty/conflict |
| `lib/features/song_trainer/application/editor/editor_command.dart` | ÚJ | reversible command |
| `lib/features/song_trainer/application/editor/editor_history.dart` | ÚJ | bounded undo/redo |
| `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` | ÚJ | screen shell |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | meglévő | Libraryből editor megnyitás |
| `lib/features/song_trainer/presentation/widgets/song_metadata_editor.dart` | ÚJ | metadata |
| `lib/features/song_trainer/presentation/widgets/song_section_editor.dart` | ÚJ | section |
| `lib/features/song_trainer/presentation/widgets/measure_grid.dart` | ÚJ | measure grid |
| `lib/features/song_trainer/presentation/widgets/song_event_editor.dart` | ÚJ | chord/strum/note |
| `lib/features/song_trainer/presentation/widgets/backing_asset_editor.dart` | ÚJ | attach/detach |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R15-ből | wiring |
| `lib/app/routing/route_guards.dart` | meglévő | unsaved guard |
| `lib/app/routing/app_route.dart` | meglévő | kanonikus editor route-katalógus |
| `lib/app/routing/app_router.dart` | meglévő | editor route |
| `lib/l10n/app_en.arb` | meglévő | EN copy |
| `lib/l10n/app_hu.arb` | meglévő | HU copy |
| `test/features/song_trainer/application/editor/song_editor_controller_test.dart` | ÚJ | command/save/conflict |
| `test/features/song_trainer/application/editor/editor_history_test.dart` | ÚJ | undo/redo limit |
| `test/features/song_trainer/presentation/song_editor_screen_test.dart` | ÚJ | widget states |
| `test/features/song_trainer/presentation/song_editor_route_guard_test.dart` | ÚJ | unsaved flow |
| `test/app/routing/route_guards_test.dart` | meglévő | route regression |
| `test/app/routing/app_router_test.dart` | meglévő | editor route-regisztráció |
| `docs/rounds/e03-r16-song-editor-v2.md` | meglévő | §10 handoff |
| `docs/reviews/e03-r16-song-editor-v2-review.md` | ÚJ | kötelező, független review artefaktum; csak reviewer írja |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Draft immutable snapshot, persisted document csak sikeres expectedRevision save után változik.
2. Command apply/revert determinisztikus; új command undo után törli a redo ágat; history limit dokumentált.
3. Minden save R05 validáció + R07 atomic update; conflict nem automatikus last-write-wins.
4. Backing attach csak sikeres asset commit után kerül draftba; failure/cancel nem hagy referenciát.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Create/edit, metadata, section reorder, measure insert/delete, két chord/measure, meter/tempo marker, pattern bulk apply és basic note működik.
- [ ] Undo/redo minden commandnál round-trip az eredeti draftig; limit határa és dispose tesztelt.
- [ ] Invalid save repository-call nélkül marad draftban; stale revision érthető conflict és nincs overwrite.
- [ ] Unsaved back stay/discard/save kombinációval, re-entryvel és browser backkel védett.
- [ ] Legacy song V2 drafttá alakítva menthető; legacy Builder flag fallback érintetlen.

### Kötelező megkülönböztető mátrix

| Editor state + action | Várt state/effect |
|---|---|
| clean + edit | dirty, undo=1 |
| dirty + undo/redo | exact előző/következő snapshot |
| undo után új edit | redo ürül |
| history limit−1/limit/limit+1 | bounded oldest eviction |
| invalid + save | validation error, 0 repository write |
| stale revision + save | conflict, draft megmarad |
| backing copy fail | draft reference változatlan |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/application/editor test/features/song_trainer/presentation/song_editor_screen_test.dart test/features/song_trainer/presentation/song_editor_route_guard_test.dart test/app/routing/route_guards_test.dart test/app/routing/app_router_test.dart
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Írd meg a pure command/history és controller save/conflict RED teszteket.
2. Írd meg a route/re-entry és widget RED kombinációkat.
3. Implementáld az immutable draft/state/command/history magot.
4. Implementáld a controller validáció/asset/repository effectjeit.
5. Implementáld a UI-t és route guardot; l10n generálás után futtasd a gate-et.

Javasolt commit: `feat(song-editor): add structured V2 song editing`.

## 9. Kockázatok

- Commandban reference-alias maradhat, ami undo snapshotot mutál; deep immutability teszt kell.
- Revision conflict UI scope-tágulhat merge editorrá; első verzió explicit reload/save-copy döntés.
- Measure edit megsértheti map/event range-eket; minden command után draft validation summary kell.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r16-song-editor-v2-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
