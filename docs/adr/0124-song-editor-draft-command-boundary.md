# ADR 0124 — Song Editor draft- és command-határ

**Státusz:** elfogadva (E03-R16 pre-flight, 2026-08-04).
**Kapcsolódó:** [ADR 0089](0089-song-document-v2.md),
[ADR 0090](0090-song-storage-files-and-assets.md),
[ADR 0114](0114-song-validator-normalizer-capability-boundary.md),
[ADR 0123](0123-song-trainer-presentation-activation-boundary.md).

## Kontextus

A Song Trainer V2 könyvtár és import út már flagelt, fájl-alapú
`SongRepository`-t kap. A `SongDocument` immutable domain érték, a repository
írásai validálnak, atomikusak és `expectedRevision`-nel optimistic concurrencyt
alkalmaznak. A szerkesztőnek ezekre építve kell többféle módosítást és
visszavonást támogatnia anélkül, hogy félkész állapot vagy néma felülírás a
perzisztált dokumentumba kerülne.

## Döntés

1. A szerkesztő application state-je immutable draft snapshotot tart, amely a
   legutóbbi sikeresen betöltött vagy mentett persisted snapshothoz képest
   explicit dirty állapotot számít. A widget csak állapotot renderel és
   controller-parancsokat küld.
2. Minden szerkesztés reverzibilis `EditorCommand`: az apply és revert azonos
   bemenetre determinisztikus snapshotot ad. A history korlátos; undo utáni új
   command eldobja a redo ágat. A history és a controller route-dispose-kor
   felszabadul.
3. Mentés előtt a controller a meglévő `SongValidator` reportját értékeli;
   fatal reportnál repository-hívás nem történhet. Sikeres mentés kizárólag a
   `SongRepository.update(draft, expectedRevision: persisted.revision)` útja
   után cseréli a persisted snapshotot. `staleRevision` esetén a draft
   megmarad, a state explicit konfliktust mutat, és nincs automatikus retry,
   merge vagy last-write-wins.
4. Backing attach csak sikeres `SongAssetRepository.put` után építhet typed
   asset-referenciát a draftba. Cancel vagy put-failure változatlan draftot
   hagy; detach nem töröl assetet csendben a shared store-ból.
5. A kanonikus editor URL a Song Trainer V2 flag alatt dokumentum-azonosító
   argumentummal nyílik. Dirty route/browser-back kilépés explicit
   maradás–eldobás–mentés döntést kér; a preview kizárólag az aktuális draft
   snapshotból készül. A legacy Builder változatlan fallback marad.

## Következmények

- A meglévő domain modellek és repository contractok változatlanok; az editor
  application/presentation rétegben áll össze.
- Az R16 nem teljes notation/tablature editor, nem vezet be autosave-et,
  kollaboratív merge-et vagy háttérhálózatot.
- A független review a snapshot immutabilityt, history-invariánst, validációs
  write-gátat, stale-revision viselkedést és dirty route-guardot a brief
  megkülönböztető mátrixával bizonyítja.
