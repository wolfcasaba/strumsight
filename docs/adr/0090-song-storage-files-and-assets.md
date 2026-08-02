# ADR 0090 — Fájlrendszeres Song repository és content-hash asset store

**Státusz:** elfogadva (Epic 3 baseline round, E03-R01, pre-flight, 2026-08-02).
Formalizálja a [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
§18 (Song repository és asset store) tervezetét kötelező érvényű döntéssé. A
tényleges implementáció külön kör (E03-R07 — Fájlrendszeres Song repository
és asset store); ez a kör (E03-R01) csak a döntést rögzíti, kódot nem ír.
Előfeltétele [ADR 0089](0089-song-document-v2.md) (`SongId`/`revision`).

## Kontextus

A Chapter 2 core storage (`lib/core/storage/`, ADR-ok az Epic 1-ből) a
`KeyValueStore` interfészen keresztül `SharedPreferences`-re épül — ez a
legacy `Song`/`Setlist` (`StorageKeys.songs`/`StorageKeys.setlists`) jelenlegi
backendje, és a Practice V2 history-jáé is (`ss.practice.history_v2`, ADR
0084). A `SongDocument V2` (ADR 0089) viszont strukturált, potenciálisan nagy
dokumentumokat (több track, sok event) ÉS bináris asseteket (backing audio,
artwork, megőrzött eredeti import-fájl) hordoz — ezek `SharedPreferences`-ben
tárolása a platform gyakorlati méret- és teljesítménykorlátaiba ütközik, és
nincs natív binary/asset támogatása.

## Döntés

1. **`SongDocument` és asset SOSEM kerül `SharedPreferences`-be.** A tárolás
   az app support könyvtárban, saját fájlrendszeres struktúrában történik:

   ```text
   app_support/songs/
   ├── index.json
   ├── documents/<song-id>.json
   ├── assets/<sha256>.<ext>
   ├── originals/<sha256>.<ext>
   ├── trash/
   └── temp/
   ```

2. **`SongRepository` a domain felé `AppResult`-alapú async kontraktus**
   (`list`/`get`/`create`/`update`/`moveToTrash`/`restore`/
   `permanentlyDelete`), a Chapter 2 `AppResult`/`AppFailure` mintát követve
   (nem dob, hibát típusos eredményként ad vissza — AGENTS.md §6). Az
   `update` kötelezően `expectedRevision`-t kér (ADR 0089 optimistic
   concurrency).
3. **Íráskor kötött, sorrendezett atomikus lépéssor**: validáció →
   temp-fájlba szerializálás → flush → visszaolvasás+decode ellenőrzés →
   atomikus rename → index temp-frissítés → index atomikus rename → csak
   ezután success. Hiba esetén az előző jó dokumentum marad olvasható — nincs
   olyan köztes állapot, ahol egy sikertelen írás a korábbi verziót is
   elveszejti.
4. **Az index csak listázási metaadat**, a teljes dokumentum nem
   duplikálódik benne (ID, title, artist, tags, `updatedAt`,
   `lastPracticedAt`, capability summary, source type, favorite, archived,
   revision, document hash) — a Song Library (§27.1) listanézete így a teljes
   dokumentumok betöltése nélkül szolgálható ki.
5. **Az asset store content-hash (SHA-256) alapú, nem elérési út alapú.**
   Ez ad duplikációcsökkentést, integritás-ellenőrzést, stabil (immutable)
   hivatkozást és corrupt-asset felismerést. Az asset metaadat: asset ID,
   SHA-256, extension, MIME, byte length, opcionális duration, `createdAt`,
   reference count vagy repository-szintű reverse lookup.
6. **Törlés kétlépcsős.** A dal törlése elsőként `trash` művelet
   (visszaállítható); asset csak akkor törölhető véglegesen, ha nincs másik
   `SongDocument`, `Setlist` vagy draft referencia, nincs aktív export/import
   művelet, és a grace period lejárt vagy explicit permanent delete történt.
7. **Induláskori recovery check, soha nem destruktív alapértelmezésben.**
   Orphan temp fájl, félbehagyott index-update, hiányzó document/asset,
   hash-mismatch, orphan asset és duplicate index entry felismerése kötelező;
   a recovery bizonyíték nélkül nem törölhet felhasználói tartalmat.

## Alternatívák

- **`SharedPreferences` egyetlen nagy JSON-blobbal (mint a legacy Song):**
  elvetve — nincs részleges/lazy betöltés, nincs bináris asset támogatás, és
  egy sérült blob az ÖSSZES dalt elveszejtené egyetlen íráskor.
- **SQLite/Drift relációs séma:** elvetve ebben a körben — új natív
  dependency-t és migrációs gépezetet vezetne be az Epic 1 storage-rétege
  mellé; a fájlrendszeres index+dokumentum minta a Chapter 2 meglévő
  atomikus-írás mintáját (verziózott dokumentum, karantén) követi kiterjesztve,
  nem helyettesíti. Relációs storage-ra váltás egy jövőbeli, külön ADR-t
  igénylő döntés, ha az index mérete/lekérdezési igénye indokolja.

## Következmények

- A `lib/features/song_trainer/data/` réteg új fájlrendszer-I/O felületet
  vezet be — ez az egyetlen hely, ahol a feature natív fájlrendszerhez nyúl
  (a §8.2 domain-independence-t nem sérti, mert a domain csak a
  `SongRepository` interfészt látja).
- Export/backup/könyvtárváltás jövőbeli köre erre az immutable,
  content-hash-alapú struktúrára épülhet módosítás nélkül.
- A recovery-logika teszthez kötelező hibaforgatókönyv-mátrixot igényel
  (orphan temp, hash mismatch, stb.) az implementáló körben (E03-R07).

## Módosítás (ADR 0112 önjavító kör, 2026-08-02)

Az E03-R08/H4 független read-back vizsgálata kimérte, hogy a
`SongDocumentCodec` a R06 adapter által létrehozott `sections`, `measures`,
`tempoMap`, `meterMap` és `keyMap` mezőket nem írta a fájldokumentumba. Ez
nem elfogadható repository-normalizáció, hanem adatvesztés: a sikeres írás
után visszaolvasott dokumentum nem egyenlő az eredetivel. A 3. döntés
„visszaolvasás+decode ellenőrzés” lépése ezért ezentúl a teljes strukturális
timeline megőrzését is jelenti. A jelenlegi sémaverzióban a hiányzó mezők
továbbra is a korábbi üres/alapértelmezett értékeket jelentik, de minden új
írás explicit, típusos szerkezeti mezőket tárol; hibásan formált, jelen lévő
szerkezeti adat fail-closed codec hibát ad. A H4 tényleges `song_alpha`
legacy rekordjából készített V2 dokumentum és egy többváltozásos timeline
round-trip regressziós teszt védi ezt a szerződést.
