# E03-R10 — Import application flow és security boundary

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 10; §13, §29.3–29.4
- **Branch:** `codex/e03-r10-import-flow-security-boundary`
- **Előfeltétel:** E03-R09 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/application/import/song_import_controller.dart",
  "lib/features/song_trainer/application/import/song_import_state.dart",
  "lib/features/song_trainer/application/import/song_import_effect.dart",
  "lib/features/song_trainer/application/import/import_preview.dart",
  "lib/features/song_trainer/application/import/cancellation_token.dart",
  "lib/features/song_trainer/data/importers/importer_registry.dart",
  "lib/features/song_trainer/data/importers/import_limits.dart",
  "lib/features/song_trainer/data/importers/import_workspace.dart",
  "lib/features/song_trainer/data/importers/file_picker_adapter.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "test/features/song_trainer/application/import/song_import_controller_test.dart",
  "test/features/song_trainer/application/import/song_import_controller_integration_test.dart",
  "test/features/song_trainer/data/importers/import_workspace_test.dart",
  "docs/rounds/e03-r10-import-flow-security-boundary.md",
]
gate_tests = [
  "test/features/song_trainer/application/import",
  "test/features/song_trainer/data/importers/import_workspace_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold minden útvonal, symbol, producer, resource owner, dependency/licence
> és numerikus cella mai állapotát. Drift esetén dokumentáld §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer előtt. A `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract/licence,
ellentmondó acceptance, hiányzó fixture vagy nem reprodukálható mérce esetén
`stopped`; nincs néma scope-tágítás vagy acceptance-gyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- R09 natív importer contractot ad, de nincs application orchestration.
- R07 repository és R05 validator/capability a pipeline végpontjai.
- A picker platformobjektuma és nagy byte array nem kerülhet domainbe vagy UI state-be.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Parserfüggetlen, explicit import state machine, limitrendszer, preview és temporary-workspace lifecycle létrehozása atomikus terminal committal.

## 2. Jelenlegi állapot

- R09 natív importer contractot ad, de nincs application orchestration.
- R07 repository és R05 validator/capability a pipeline végpontjai.
- A picker platformobjektuma és nagy byte array nem kerülhet domainbe vagy UI state-be.

## 3. Scope

**Benne:**

- SongImportController state/effect modell
- registry, limits, cancellation token és ImportSourceFile
- picker adapter, temporary workspace és cleanup
- probe→preview→parse→validate→commit/retry

**Kívül — ebben a körben TILOS:**

- formátumspecifikus XML/MIDI parser
- import képernyő widget
- háttérben korlátlan parse vagy nagy bytes state
- warning fatalra vagy fatal warningra gyengítése

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `lib/features/song_trainer/application/import/song_import_controller.dart` | ÚJ | state machine |
| `lib/features/song_trainer/application/import/song_import_state.dart` | ÚJ | immutable state |
| `lib/features/song_trainer/application/import/song_import_effect.dart` | ÚJ | side-effect contract |
| `lib/features/song_trainer/application/import/import_preview.dart` | ÚJ | preview/capability |
| `lib/features/song_trainer/application/import/cancellation_token.dart` | ÚJ | cancel contract |
| `lib/features/song_trainer/data/importers/importer_registry.dart` | ÚJ | content-aware registry |
| `lib/features/song_trainer/data/importers/import_limits.dart` | ÚJ | erőforráslimitek |
| `lib/features/song_trainer/data/importers/import_workspace.dart` | ÚJ | temp lifecycle |
| `lib/features/song_trainer/data/importers/file_picker_adapter.dart` | ÚJ | platform boundary |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R08-ból | production wiring |
| `test/features/song_trainer/application/import/song_import_controller_test.dart` | ÚJ | state/effect transition |
| `test/features/song_trainer/application/import/song_import_controller_integration_test.dart` | ÚJ | atomic flow |
| `test/features/song_trainer/data/importers/import_workspace_test.dart` | ÚJ | cleanup/traversal |
| `docs/rounds/e03-r10-import-flow-security-boundary.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. State és effect külön mérhető; terminal callback idempotens.
2. Registry tartalmat is vizsgál, nem csak extensiont.
3. Repository record kizárólag sikeres normalize+validate+atomic commit után látható.
4. Cancel/dispose/route leave minden worker, stream, file handle és workspace ownerét lezárja.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Idle/selecting/probing/preview/importing/validating/committing/success/failure/cancelled átmenetek explicit és teszteltek.
- [ ] Minden failure/cancel cellában 0 félkész record és 0 workspace/asset leak.
- [ ] Retry új operation ID-val indul, régi callback nem írhat az új state-be.
- [ ] Nagy bytes/parser/platform object nincs Riverpod state-ben; warning és fatal külön.
- [ ] Size/event/workspace/wall-time limit stabil failure code-dal állít le.

### Kötelező megkülönböztető mátrix

| Kiinduló state + esemény | Következő state/effect |
|---|---|
| selecting + cancel | idle / picker cleanup |
| probing + unsupported | failure / workspace cleanup |
| preview + confirm | importing / parse effect |
| committing + storage failure | failure / rollback+cleanup |
| bármely active + cancel/dispose | cancelled/terminal / minden owner close |
| régi op callback új retry alatt | state változatlan |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/application/import test/features/song_trainer/data/importers/import_workspace_test.dart
```

A brief pre-flightja a feltételes szöveget egyetlen futtatható
`tools/round-gate.sh ...` parancsra cseréli, ha a kör döntési ágas. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Írd meg a teljes state+effect transition táblát és RED controller tesztet.
2. Írd meg a workspace cleanup/traversal/limit RED teszteket.
3. Implementáld a tiszta reducert/state-et, majd az adaptereket.
4. Kösd össze a pipeline-t validator/repository terminal committal.
5. Futtasd a gate-et és reviewerrel mutáld a stale-callback guardot.

Javasolt commit: `feat(song-import): add secure import orchestration and preview state`.

## 9. Kockázatok

- Re-entry során régi async callback új sessiont korrumpálhat; operation ID kötelező.
- Workspace symlink/path traversal a parser előtt is védendő.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r10-import-flow-security-boundary-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
