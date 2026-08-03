# E03-R15 — Song Library V2 és import UI

- **Státusz:** **PLANNING — H3 pre-flight scope conflict** (2026-08-03, measured `origin/main` @ `6957702`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 15; §27.1–27.3, §28
- **Branch:** `codex/e03-r15-song-library-import-ui`
- **Előfeltétel:** E03-R14 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/song_trainer/application/library/song_library_controller.dart",
  "lib/features/song_trainer/application/library/song_library_state.dart",
  "lib/features/song_trainer/application/library/song_query.dart",
  "lib/features/song_trainer/presentation/screens/song_library_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart",
  "lib/features/song_trainer/presentation/widgets/song_summary_tile.dart",
  "lib/features/song_trainer/presentation/widgets/song_capability_badges.dart",
  "lib/features/song_trainer/presentation/widgets/import_warning_list.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "lib/features/song_trainer/public.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/app/config/feature_flags.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/song_trainer/application/library/song_library_controller_test.dart",
  "test/features/song_trainer/presentation/song_library_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/app/routing/app_router_test.dart",
  "docs/rounds/e03-r15-song-library-import-ui.md",
]
gate_tests = [
  "test/features/song_trainer/application/library/song_library_controller_test.dart",
  "test/features/song_trainer/presentation/song_library_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/app/routing",
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

- R07 index/repository, R09 export és R10 import controller kész.
- R08 migrated legacy rekordokat ad; ugyanaz a logikai dal nem jelenhet meg legacy és V2 formában kétszer.
- A jelenlegi routing és l10n contractot pre-flightban exact symbolokra auditálni kell.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

### 2026-08-03 — measured H3

- `origin/main` és a helyi HEAD egyaránt `6957702`; E03-R14 merge commitja a
  historyban jelen van (`6957702 chore(pipeline): E03-R14 done`). Nincs korábbi
  R15 branch, review vagy implementer diff.
- A mai `SongImportScreen` kizárólag az R14 `GuitarProConversionGuidance`
  statikus widgetet rendereli
  (`lib/features/song_trainer/presentation/screens/song_import_screen.dart:1-22`).
  A SDD szerinti picker → probe → preview → confirm UI ezért nem valósítható
  meg csupán a screen módosításával.
- Az import valódi inputját a `FilePickerAdapter.pickSongFile()` absztrakció
  definiálja (`lib/features/song_trainer/data/importers/file_picker_adapter.dart:7-10`),
  de a repóban nincs concrete adapter vagy `file_picker` dependency (`rg -n
  'FilePickerAdapter|file_picker|pickSongFile' pubspec.yaml pubspec.lock lib test`).
  Ennek production megvalósítása nem kerülhet widgetbe, és ez a data-boundary
  fájl nincs a §4 listán.
- A `SongImportController` a `songRepositoryProvider`-t olvassa
  (`application/song_trainer_providers.dart:166-175`), amely jelenleg
  szándékosan `StateError`-t dob bootstrap override nélkül
  (`application/song_trainer_providers.dart:87-93`). A tényleges app
  `ProviderScope`-ja csak config, key-value store, diagnostics és onboarding
  override-ot ad (`lib/main.dart:31-42`); a V2 route flagelt bekötése tehát
  productionben elérhetetlen repositoryt aktiválna. `lib/main.dart` és a
  bootstrap ownership nincs a §4 listán.
- A kötelező, merge előtti review artefaktum pontos útvonala
  `docs/reviews/e03-r15-song-library-import-ui-review.md`, de sem §4, sem az
  `ai-router.allowed_paths` nem engedi — ez ugyanaz a mért metadata-hiba,
  amelyet L88 az R14-nél rögzített.

**Feloldás:** ADR 0123 rögzíti, hogy interaktív V2 library/import route csak
production repository- és picker-boundary-val aktiválható; fake nem válhat
production fallbackké. A szükséges `data/importers` picker owner, app/bootstrap
wiring, a kötelező review-útvonal és a hozzájuk tartozó tesztek listán kívüliek.
Az AGENTS.md §15 autonómia H3 szabálya szerint ez a round nem tágíthatja a
scope-ot: router dispatch, implementáció, CI és merge nem indul. A következő
self-heal/pre-flight feladata egy jóváhagyott, tételes scope-revízió és annak
metadata-regressziója.

## 1. Cél

Indexalapú, lazy V2 Library és a biztonságos R10 importfolyamat teljes, capability-őszinte, lokalizált felhasználói felülete trainer nélkül.

## 2. Jelenlegi állapot

- R07 index/repository, R09 export és R10 import controller kész.
- R08 migrated legacy rekordokat ad; ugyanaz a logikai dal nem jelenhet meg legacy és V2 formában kétszer.
- A jelenlegi routing és l10n contractot pre-flightban exact symbolokra auditálni kell.

## 3. Scope

**Benne:**

- SongLibraryController/State/Query
- V2 Library, import és preview screens
- source/capability/warning/missing-asset badge
- search/filter/favorite, trash+undo, native export, flagelt route

**Kívül — ebben a körben TILOS:**

- Song Editor, Overview és Trainer
- documentenkénti eager decode listázáskor
- fatal preview commit
- feature flag production default bekapcsolása

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/features/song_trainer/application/library/song_library_controller.dart` | ÚJ | query/actions |
| `lib/features/song_trainer/application/library/song_library_state.dart` | ÚJ | immutable UI state |
| `lib/features/song_trainer/application/library/song_query.dart` | ÚJ | index query |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | ÚJ | V2 library |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | ÚJ | import states |
| `lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart` | ÚJ | preview |
| `lib/features/song_trainer/presentation/widgets/song_summary_tile.dart` | ÚJ | lazy summary |
| `lib/features/song_trainer/presentation/widgets/song_capability_badges.dart` | ÚJ | capability/source |
| `lib/features/song_trainer/presentation/widgets/import_warning_list.dart` | ÚJ | warning UI |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | R10-ből | controller wiring |
| `lib/features/song_trainer/public.dart` | R01-ből | route/public exports |
| `lib/app/routing/app_route.dart` | meglévő | typed routes |
| `lib/app/routing/app_router.dart` | meglévő | flagelt navigation |
| `lib/app/config/feature_flags.dart` | R01-ből | rollout guard |
| `lib/l10n/app_en.arb` | meglévő | EN copy |
| `lib/l10n/app_hu.arb` | meglévő | HU copy |
| `test/features/song_trainer/application/library/song_library_controller_test.dart` | ÚJ | query/dedupe/action |
| `test/features/song_trainer/presentation/song_library_screen_test.dart` | ÚJ | library states |
| `test/features/song_trainer/presentation/song_import_screen_test.dart` | ÚJ | import state UI |
| `test/features/song_trainer/presentation/song_import_preview_screen_test.dart` | ÚJ | warning/fatal |
| `test/app/routing/app_router_test.dart` | meglévő | flag routes |
| `docs/rounds/e03-r15-song-library-import-ui.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, más kör briefje
és nem felsorolt CI/docs artefaktum. Új fixture/helper is fájl; listán kívül
→ `stopped`. Cross-feature fájl csak a táblában jelzett publikus boundary
additív exportjára módosítható, a pre-flight exact symbol auditja után.

## 5. Kötött architekturális döntések

1. Listázás kizárólag index summaryt olvas; document decode csak detail/action igényre.
2. Legacy/V2 dedupe stabil mapping alapján történik, nem title string alapján.
3. Warning és fatal vizuálisan/semantikailag külön; unsupported capability aktívnak nem látszhat.
4. Picker fake adapterrel tesztelhető; platform object nem kerül widget/controller state-be.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Empty/loading/error és nagy lazy lista érthető, index-only olvasás mérhető.
- [ ] Search/filter/favorite és migrated legacy dedupe determinisztikus.
- [ ] Cancel/probe error/warning/fatal/success/duplicate/delete-undo/missing-asset minden state+effect kombinációja tesztelt.
- [ ] Natív export action R09 privacy contractot használ; fatal previewn nincs confirm.
- [ ] HU/EN, 200% text scale, semantics/fókuszsorrend és route re-entry zöld.

### Kötelező megkülönböztető mátrix

| Data state | Import state | Badge/action | Várt UI |
|---|---|---|---|
| empty | idle | nincs | empty CTA |
| list | warning preview | partial capability | warning + confirm policy |
| list | fatal preview | unsupported | fatal + confirm disabled |
| migrated duplicate | success | export | egy tile, stabil ID |
| missing asset | idle | repair | badge + elérhető repair belépés |
| delete pending | idle | undo | tile eltűnik, snackbar semantics |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/application/library/song_library_controller_test.dart test/features/song_trainer/presentation/song_library_screen_test.dart test/features/song_trainer/presentation/song_import_screen_test.dart test/features/song_trainer/presentation/song_import_preview_screen_test.dart test/app/routing
```

Ez az egyetlen lokális záró gate: format → analyze → célzott test →
architecture külön processzekben; nincs `&&`, pipe, `tail` vagy csonkítás.
A full suite + randomizált property + APK CI-t az orchestrátor exact branch
`headSha`-ra indítja. Valódi audio/device mércét CI nem helyettesít.

## 8. Implementációs sorrend

1. Írd meg controller query/dedupe és route flag RED teszteket.
2. Írd meg a kombinált widget state, re-entry, l10n és a11y RED teszteket.
3. Implementáld a controller/state/query réteget index-only contracttal.
4. Implementáld a három screen/widgeteket és route/flag bekötést.
5. Generáld az l10n outputot friss klónban, majd futtasd a gate-et.

Javasolt commit: `feat(song-ui): add V2 library and secure import experience`.

## 9. Kockázatok

- R14 C ág előre létrehozhatta az import screent; pre-flight merge/driftet mér és fájltulajdont rendez.
- UI teszt fake repositoryval nem bizonyít index-only viselkedést; call-count mérce kell.
- L10n generated fájl policy az aktuális repó szerint követendő, nem kézzel találgatandó.

**STOP:** listán kívüli javítás, bizonyítatlan fallback, belső cross-feature
import vagy gyengített mérce helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r15-song-library-import-ui-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
