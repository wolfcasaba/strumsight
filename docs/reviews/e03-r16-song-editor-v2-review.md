# E03-R16 — Song Editor V2 — Review

Brief: `docs/rounds/e03-r16-song-editor-v2.md`

Diff: `git diff origin/main...codex/e03-r16-song-editor-v2` (25 files, +2316/−56)

Reviewer: Claude Opus 4.8, isolated `/tmp/review-e03-r16` clone

Dátum: 2026-08-04
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

Ez a termékbeli Song Editor V2 implementáció független review-ja, a korábbi
`CHANGES REQUESTED` (baseline `c037993`, F1/F2/F3 MAJOR) javító köre után. A
javító commit (`fix(song-editor): expose V2 editing flows`) mindhárom leletet
zárja; a jelen review a zárást leletenként méri, nem olvassa.

## Korábbi lelet-zárás (leletenként, teszttel)

| Lelet | Állapot | Bizonyíték a mai diffben |
|---|---|---|
| **F1** — backing attach elérhetetlen a UI-ból | ZÁRVA | `song_editor_screen.dart:246` `onAttach: () => _attachBacking(...)` → `_attachBacking` (254) `controller.attachBacking(SongAssetWriteRequest(...))` (266). Teszt: `song_editor_controller_test.dart` „successful backing attachment updates the draft after asset put" + a megőrzött „backing asset failure leaves draft reference unchanged". |
| **F2** — tempo/meter és event-szerkesztés hard-coded | ZÁRVA | `song_event_editor.dart` kiválasztható `_measureIndex` dropdown (30/40/53) + `onSetTempo`/`onSetMeter`/`onAddChord`/`onAddNote`/`onApplyPattern` callbackek; `song_editor_screen.dart:223-238` a controller `addChord`/`setTempo`/`setMeter`/`addBasicNote`/`applyPattern` API-jaira kötve a kiválasztott measure-rel. |
| **F3** — create-new V2 út elérhetetlen | ZÁRVA | `song_library_screen.dart:40` `Key('song-editor-create')` → `context.push(AppRoutes.songTrainerNewEditor)`; `song_editor_screen.dart:65` `startNew(_newDraft(...))`. Teszt: `app_router_test.dart` „library offers a canonical new V2 editor route" + `song_editor_controller_test.dart` „new valid draft saves through repository create". |

## Scope-audit

`git diff --name-only origin/main...HEAD` = 25 fájl, mind a brief §4
engedélyezett listáján (+ a pre-flight ADR 0124 és a brief maga). Listán kívüli
fájl: **nincs**. A merge-be húzott router-heal `tools/` változás a jelenlegi
`origin/main`-hez képest **nulla** (három-pontos diff), tehát nem része a
kör-diffnek.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Create/edit, metadata, section reorder, measure insert/delete, két chord/measure, meter/tempo marker, pattern bulk apply, basic note | ✅ | `song_editor_controller_test.dart` + `song_editor_screen_test.dart` (186 sor widget-lefedettség), `app_router_test.dart` új-editor route |
| 2 | Undo/redo round-trip, limit-határ és dispose tesztelt | ✅ | `editor_history_test.dart` „bounded history evicts oldest command and clears redo after a new edit"; **valódi-sértés próba lentebb** |
| 3 | Invalid save repository-call nélkül; stale revision conflict, nincs overwrite | ✅ | „invalid save does not call repository create and retains draft" + „stale revision retains draft and exposes conflict without overwrite"; **valódi-sértés próba lentebb** |
| 4 | Unsaved back stay/discard/save, re-entry, browser back | ✅ | `song_editor_route_guard_test.dart`, `route_guards_test.dart` (`mayLeaveEditor`) |
| 5 | Legacy song V2 drafttá menthető; legacy Builder flag fallback érintetlen | ✅ | controller `load`/`startNew`; a legacy Builder flag nem módosult (scope-on kívül) |

## Próbatesztek (eldobható, izolált `/tmp/review-e03-r16` klón, visszaállítva)

1. **Invalid-save-no-write invariáns.** `song_editor_controller.dart:393`
   `if (report.hasFatalIssue)` → `if (false)` (invalid draft átcsúszik a
   `repository.create`-re). Eredmény: „invalid save does not call repository
   create and retains draft" → **PIROS** (`+5 -1`, Some tests failed).
   Visszaállítva → zöld.
2. **Undo round-trip invariáns.** `editor_history.dart` `takeUndo`
   `_undo.removeLast()` → `_undo.removeAt(0)` (rossz command visszaadása).
   Eredmény: „bounded history evicts oldest command and clears redo after a new
   edit" → **PIROS** (`+6 -1`, Some tests failed). Visszaállítva → zöld.

Mindkét központi invariáns tesztje ténylegesen megkülönböztet; nem üres zöld.
A route-guard invariánst a korábbi review már `mayLeaveEditor` mutációval
pirosra váltotta.

## Kötött architekturális döntések (§5)

1. Draft immutable snapshot, persisted csak sikeres expectedRevision save után változik — ✅ `save()` `repository.update(draft, expectedRevision: persisted.revision)` (413), conflict ág nem ír felül (418-423).
2. Command apply/revert determinisztikus; új command undo után redo-t töröl; history limit dokumentált — ✅ `EditorHistory.record` `_redo.clear()` + `limit` eviction; probe 2 bizonyítja.
3. Save = R05 validáció + R07 atomic update; nincs auto last-write-wins — ✅ `validator.validate` gate + expectedRevision; probe 1 bizonyítja.
4. Backing attach csak sikeres asset commit után draftba; failure/cancel nem hagy referenciát — ✅ „backing asset failure leaves draft reference unchanged" teszt.

## Gate-bizonyíték ellenőrzése

| Gate | Eredmény | Ellenőrizve |
|---|---|---|
| `tools/round-gate.sh` (format/analyze/5 test-terület/architecture) | MINDEN ZÖLD | ✅ izolált munkapéldányban, csonkítatlan kimenettel |
| Valódi-sértés próba (2 invariáns) | RED → GREEN | ✅ izolált `/tmp` klónban |
| Flutter full suite + property + APK | orchestrátor CI-dispatch exact `headSha`-ra | a merge előtti CI-run a build-evidencia |

## Merge-döntés

F1/F2/F3 zárva, teszttel; scope tiszta; a két központi invariáns
valódi-sértésre pirosra vált; a lokális gate zöld. Nincs nyitott BLOCKER vagy
MAJOR. Merge-elhető az exact-SHA zöld CI után.
