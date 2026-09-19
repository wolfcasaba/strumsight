# ADR 0522 — A setlist-session EGY indítóval indul, a mód paraméter, a legacy setlist memóriában vetül V2-re

**Státusz:** elfogadva (2026-09-15, E17-R03 — Chapter 17 „Teljes bekötés", Kör 3)

**Kör:** `E17-R03` · **Brief:** [`docs/rounds/e17-r03-setlist-session-wiring.md`](../rounds/e17-r03-setlist-session-wiring.md)
· **A szállító commit:** `25b518457` — *„feat(song_trainer): the setlist session
is reachable from the setlist detail — one launcher, mode as a parameter (E17-R03)"*

Kapcsolódik: [ADR 0130](0130-setlist-v2-song-progress-and-epic-3-closure-boundary.md)
(a V2 setlist-dokumentum és a legacy adapter határa),
[ADR 0125](0125-song-trainer-setup-configuration-boundary.md) (a setup → compile →
Stage lánc), [ADR 0087](0087-round-brief-scope-authority.md) §2 (a kör-brief
scope-hatásköre), [ADR 0112](0112-self-healing-pipeline.md) §2 (a kör
pre-flight-revíziója).

## Kontextus

Ez az ADR **utólag rögzít egy már szállított döntést**, mint az
[ADR 0584](0584-analysis-capture-flow-guard-and-open-contract.md): a kör
tartalma nem a pipeline dispatch-én keresztül landolt, hanem a `25b518457`
commitban (2026-09-15), és a négy-vonalas integrációval került a `main`-re. A
kód öt helyen hivatkozik „ADR 0522"-re, de a fájl maga sosem született meg — a
hivatkozások a `docs/execution/pipeline-queue.tsv` ELŐZETES ADR-slotjára
mutattak, a brief saját §5-ének szakasz-számaival.

**Mért kiindulópont.** A `SetlistSessionScreen` injektált varratokkal
(`availability`, `performanceRunner`, `createPracticeRunner`) készült, és
**egyetlen produkciós hívó sem töltötte ki** őket. Emellett két diszjunkt
setlist-világ van a fán:

| | legacy (`songs`) | V2 (`song_trainer`) |
|---|---|---|
| típus | `Setlist{id, name, songIds}` | `SongSetlist{id, name, items}` |
| azonosító | időbélyeg-id | `SongId` |
| tár | kulcs-érték store | fájl-repository |
| szerkesztő | az elérhető `SetlistDetailScreen` | `SetlistListScreenV2` |

A session `SongSetlist`-et futtat, a gitáros viszont a **legacy** részletképernyőn
áll. A két id-tér nem metszi egymást — ezt a kör pre-flightja mérte
(`tools/tests/test_e17_r03_setlist_session_scope.py` őrzi), és ez a brief eredeti
„a részletképernyő a természetes belépési pont" premisszájának cáfolata volt.

## Döntés

1. **A belépés a legacy `SetlistDetailScreen`-ről megy, és a legacy setlist
   MEMÓRIÁBAN vetül V2-re — nem perzisztálva.** Minden belépéskor a
   `SetlistSessionComposer.compose` képezi le a `LegacySetlistRecord`-ot
   `SongSetlist`-re (ugyanaz a leképezés, mint a migrációs adapteré). A legacy
   `setlistsProvider` marad az EGYETLEN igazságforrás, amit ez a képernyő
   szerkeszt: a session nem ír a V2 tárba, tehát nem keletkezik két, egymástól
   elsodródó setlist-dokumentum ugyanarra a listára. Ez a válasz a diszjunkt
   id-terek problémájára — a V2 lista (`SetlistListScreenV2`) önálló
   szerkesztőként megmarad, saját, már bekötött útvonalán.

2. **EGY indító van, és a mód a PARAMÉTERE — soha nem második kód-út.** A
   `_chooseSessionMode` bottom sheet a `SetlistSessionMode`-ot választja ki
   (`practice` / `performance`), és mindkét csempe ugyanabba a `_startSession`
   hívásba fut. Két külön belépési pont két kód-utat teremtene ugyanarra az
   állapotgépre; a `SetlistSessionScreen` amúgy is paraméterként veszi a módot.

3. **Az availability és mindkét runner a VALÓS dal-tárakból jön, ugyanazon a
   kompozíción át.** A `SetlistSessionComposer` a `songRepositoryProvider`-ből
   dönt — konstans `ready` tilos —, és a per-tétel runnereket ugyanarra a
   setup → compile → Stage láncra építi, amit az egy-dalos Trainer-útvonal
   használ (`SongTrainerSetupController`, `SongPracticeCompiler`,
   `SongTrainerControllerInputs`). Feloldhatatlan tétel `missingSong` okkal
   `skipped` lesz.

4. **Az application-réteg nem navigál (AGENTS.md §7).** A kompozícióban nincs
   Flutter-navigáció, `BuildContext` és router. Egy dal Stage-ének
   megmutatása a prezentációs réteg dolga, ezért `SetlistItemStagePresenter`
   callbackként van injektálva, és tételenként `await`-elve — a runner akkor
   oldódik fel, amikor a gitáros elhagyja azt a Stage-et.

5. **A session kimenete MÉRT, és a befejezés a részletképernyőre tér vissza.** A
   `SetlistItemResult` státusza abból jön, amit a session ténylegesen
   visszaad; `completed`/`partial` szintetizálása (pl. fal-óra alapján) tilos. A
   befejezés a hívó `SetlistDetailScreen`-re popol vissza — nem a gyökérre —, és
   snack barban jelenti, hány tétel készült el a teljes számból.

## Következmények

- A bekötést a `test/features/song_trainer/setlist_session_wiring_test.dart`
  cellái mérik (A3: egy indító, paraméteres mód; A2/A4: mindkét mód a VALÓS
  `SetlistSessionController`-en fut és visszatér; a composer-csoport: valós
  repository fölötti feloldás és a `missingSong` ok).
- A `song_trainer/public.dart` additívan exportálja a belépési felületet
  (`SetlistSessionScreen`, `SetlistSessionMode`, `SongSetlist`,
  `SetlistResult`/`SetlistItemResultStatus`, `LegacySetlistRecord`, a composer és
  a `SongTrainerScreen`) — ez tette a `SongSetlist`/`SongSetlistItem` párost
  publikussá, ami az `E04-R21` brief halasztott setlist-felét feloldotta
  (lásd annak §0.1-ét és `tools/tests/test_r21_brief_public_boundary.py`).
- **Tudatosan nyitva marad:** a legacy → V2 vetítés belépésenként újra fut, és
  semmit nem perzisztál. Amíg a legacy tár él, ez a helyes viselkedés; a két
  világ tényleges egyesítése (ADR 0130 migrációs útja) külön kör tárgya.

## A visszavonás feltétele

Ha a legacy setlist-tár megszűnik, az 1. pont vetítése fölöslegessé válik, és a
belépés a V2 listára költözik — a 2–5. pont változatlanul érvényes marad, mert
egyikük sem a belépési pontról szól. A 2. pont visszavonása (mód szerinti külön
belépési pontok) az A3 cellát pirosra váltja, tehát csak saját körben, ADR-rel
indokolva lehetséges.
