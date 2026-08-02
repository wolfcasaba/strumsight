# ADR 0117 — Song storage migrator: legacy read path, checkpoint persistence, setlist scope

**Státusz:** elfogadva (E03-R08 pre-flight, 2026-08-02, orchestrátor: Claude
Sonnet 5). Formalizálja a
[`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
Kör 8 tervezetének a briefben implicit hagyott döntéseit.
Előfeltétele [ADR 0090](0090-song-storage-files-and-assets.md),
[ADR 0116](0116-legacy-song-setlist-migration-boundary.md).

## Kontextus

Az E03-R08 brief (`docs/rounds/e03-r08-persistent-v2-migration.md`) egy
`SongStorageMigrator` use case-t ír le, amely a legacy `Song`/`Setlist`
tartalmat (R06 adapterekkel) a V2 file repositoryba (R07) írja, checkpointtal
és read-back parityvel. A pre-flight a TÉNYLEGES hívási láncot és
fájllistát mérte ki (nem a dokumentációt feltételezte) — három pont
bizonyult olyan valódi döntésnek, amit a brief §3–§6 nem, vagy csak
implicit módon rögzít:

1. **Ki szerzi meg ma a legacy JSON-t, és a migrátor honnan érheti el
   ugyanazt fájllista-bővítés nélkül?** `SongsRepository`/`SetlistsRepository`
   (`lib/features/songs/data/`) egy `JsonCollectionStore<Song>`/
   `<Setlist>`-et nyit a `StorageKeys.songs`/`StorageKeys.setlists` kulcsokon,
   és **típusos** `Song`/`Setlist` objektumokat ad vissza (a legacy
   presentation modellt, `fromJson`-on át). A `LegacySongReader.readSong`/
   `readSetlist` viszont explicit **nyers** `Map<String, dynamic>`-et vár
   (ADR 0116: "a reader never imports a presentation layer"). A
   `lib/features/songs/public.dart` csak a `Song` modellt exportálja
   (`Setlist`-et és a repository interfészeket nem) — a `crossFeatureImports
   MustUsePublicApi` architektúra-szabály (`tool/check_architecture.dart`)
   miatt a migrátor NEM importálhatja a `songs` feature belsejét, a
   `public.dart` bővítése pedig nincs a kör §4 engedélyezett listáján (a
   pre-flight ezt listabővítés NÉLKÜL oldja fel, ld. Döntés 1).
2. **Hova írja a migrátor a checkpoint/completion markert?** A brief §4
   egyetlen ÚJ data-layer fájlt enged (`song_migration_version_store.dart`),
   de nem mondja meg a tárolási mechanizmust. A `StorageKeys`
   (`lib/core/storage/storage_keys.dart`) nincs az engedélyezett listán — új
   kulcs felvétele tilos zóna. A R07 HANDOFF-konvenció ("No
   SharedPreferences/key-value path carries `SongDocument`/asset content
   anywhere in the new code") kizárja a `KeyValueStore`-alapú markert is
   elvi okból, nemcsak fájllista-korlát miatt.
3. **Mit jelent "Setlist csak teljes song-ID mapping után indul" ténylegesen,
   ha nincs V2 Setlist repository?** Az Epic 3-ban (E03-R01…R07) **nem
   létezik** V2 setlist domain modell vagy repository — a `lib/features/
   song_trainer/` fában nincs `song_setlist*` fájl, és a kör §4 listája sem
   ad hozzá ilyet. A `LegacySetlistAdapter.adapt()` (R06) egy songbook
   (`Map<legacySongId, SongDocument>`) ellenében **jelentést** (`documents`,
   `report`, `unresolvedIds`) állít elő, nem perzisztál semmit.

## Döntés 1 — A migrátor a legacy JSON-t közvetlenül `JsonDocumentStore`-on át olvassa, cross-feature import nélkül

A migrátor (`song_storage_migrator.dart`) **saját maga példányosít** egy
`JsonDocumentStore`-t a már létező, core-tulajdonú
(`lib/core/storage/json_document_store.dart`) `KeyValueStore` fölött, a
MEGLÉVŐ `StorageKeys.songs`/`StorageKeys.setlists` +
`LegacyStorageKeys.songs`/`LegacyStorageKeys.setlists` kulcsokkal — pontosan
ugyanazokkal, amiket a `songs`/`setlists` feature repository-jai is
használnak. `readBody()` a nyers, dekódolt `List`-et adja vissza
(`Map<String, dynamic>` elemekkel), amit a migrátor közvetlenül a MEGLÉVŐ
`LegacySongReader.readSong`/`readSetlist`-nek ad át — a `JsonCollectionStore<
Song>`/`<Setlist>` típusos rétegét (és ezzel a `Song`/`Setlist`
presentation modellt és a `songs` feature belsejét) teljesen megkerülve.

Ez **csak core importot** (`lib/core/storage/**`) igényel, nem
feature-importot — a `crossFeatureImportsMustUsePublicApi` szabály nem
vonatkozik rá, és a `songs/public.dart` változatlan marad. A hozzáférés
**csak olvasás**: a migrátor sosem ír a `StorageKeys.songs`/`.setlists`
kulcsokra, és a legacy törlés ebben a körben tilos (§3/§5 kötött döntés 4)
— nincs írási ütközés a `songs`/`setlists` feature-rel, amely a saját
`JsonCollectionStore`-példányán át továbbra is kizárólagosan ír oda.

**Indoklás:** ez a MEGLÉVŐ, sanctioned resource-owner (a `songs`/`setlists`
feature repository-i már ma is pontosan ezt a `JsonDocumentStore`
primitívet nyitják meg ugyanazon a két kulcson) — a migrátor csak egy
második, read-only nyitást ad hozzá, típuskonverzió nélkül. Az alternatíva
(a `songs/public.dart` bővítése `Setlist`+repository exporttal) fájllista-
bővítés lenne, amit a kör-pipeline promptja kifejezetten tilt ("amit nem
találsz meg a kódban... ne lista-tágítással").

## Döntés 2 — A checkpoint/version marker fájl-alapú, a songs-root alatt, `AtomicFileWriter`-rel

A `song_migration_version_store.dart` a checkpointot és a completion
markert egyetlen JSON dokumentumként tárolja a songs-root könyvtár alatt
(pl. `<songsRoot>/migration/state.json`), a MEGLÉVŐ (R07, változatlan)
`AtomicFileWriter`-en át (temp→flush→verify→rename) — ugyanaz az
atomicitás-garancia, mint a `FileSongRepository`/`FileSongAssetRepository`
esetén. A dokumentum két logikai részt hordoz:

- **per-legacy-id checkpoint**: mely legacy song ID-k migrálása fejeződött
  be sikeresen (a legacy ID → V2 `SongId` megfeleltetés maga a legacy ID,
  változatlanul — ezt a MÁR MERGE-ELT R06 `LegacySongAdapter.adapt()`
  rögzíti `id: SongId(record.id)`-ként, ez a kör nem módosíthatja, H2);
- **global completion flag**: csak azután `true`, hogy MINDEN legacy song
  checkpoints és a setlist-mapping lépés (Döntés 3) is sikeresen lezajlott.

**Indoklás:** a `StorageKeys`/`KeyValueStore` bővítése tilos zóna (nincs a
§4 listán) ÉS elvi okból is helytelen lenne (R07 HANDOFF-konvenció: semmi
`SongDocument`-tartalomhoz kötődő állapot nem élhet key-value store-ban). A
file-alapú marker a már bizonyított R07 atomicitás-infrastruktúrát
használja újra, nem vezet be új perzisztencia-mintát.

## Döntés 3 — A setlist-lépés ebben a körben validáció/report, nem persistence

Az Epic 3-ban nincs V2 setlist repository — a `SongStorageMigrator` a
setlist-lépésben a MÁR MERGE-ELT `LegacySetlistAdapter.adapt()`-ot hívja a
songbook felett (a sikeresen migrált song ID-k → adaptált `SongDocument`
leképezéssel), és az eredmény (`LegacySetlistAdaptation` — `documents`
sorrend, `report`, `unresolvedIds`) a migráció completion-summary/state
része lesz, **nem kerül V2 repositoryba írásra**. A "Setlist csak teljes
song-ID mapping után indul" (§5 kötött döntés 3) tehát: a setlist-adapter
hívás csak azután fut le, hogy MINDEN legacy song checkpointja sikeres
(vagy explicit failed/corrupt státuszú, de feldolgozott) — nem egy V2
setlist-perzisztencia előfeltétele, mert ilyen perzisztencia még nem
létezik.

**Indoklás:** ez a §3 "Kívül — V2 Library UI" tilalommal konzisztens (egy
V2 setlist-tároló bevezetése ÚJ domain-felület lenne, ami messze túlmutat
egy migrátor use case-en), és a §4 fájllista sem ad hozzá V2 setlist
modellt/repository-t — a hallgatás itt nem hiányzó specifikáció, hanem
implicit scope-korlát.

## Következmény

- A migrátor egyetlen ÚJ importot vezet be a `song_trainer` fába kívülről:
  `lib/core/storage/**` (core, nem feature) — nulla cross-feature
  architektúra-eltérés, nulla `public.dart` módosítás.
- A checkpoint/version store tesztelhető invariánsa: `completed == true`
  csak akkor, ha minden song checkpoint sikeres ÉS a setlist-report
  legenerálódott (mérhető property, nem csak dokumentáció).
- A setlist-migráció kimenete (jelentés) evidencia a jövőbeli V2 setlist-
  kör számára, de ez a kör nem hoz létre V2 setlist perzisztenciát.
- A legacy ID → `SongId` azonosság (R06, változatlan) az idempotencia
  kulcsa: restart után `create()` `alreadyExists`-et ad ugyanarra a legacy
  ID-ra, amit a migrátor "már kész" jelként értelmez (read-back
  újraellenőrzéssel, nem újraírással).

Ezen döntések feloldása „zöldre javításként" nem elfogadható; valódi
ellentmondás esetén ez az ADR egy módosítási blokkal bővítendő, nem
csendben felülírandó.
