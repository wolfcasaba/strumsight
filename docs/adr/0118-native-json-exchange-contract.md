# ADR 0118 — Natív JSON csereboríték: verziók, privacy és asset-manifest

**Státusz:** elfogadva (E03-R09 pre-flight, 2026-08-02). A
[Song import security boundary](0091-song-import-security-boundary.md) és a
[SongDocument V2](0089-song-document-v2.md) konkrét, natív JSON adapterre
vonatkozó döntése.

## Kontextus

Az E03-R09 az első külső, nem megbízható fájlt parse-oló kör. A meglévő
`SongDocumentCodec` belső tárolási codec: `schemaVersion` a dokumentum
verziója, és nincs formátumfüggetlen importer contract vagy importer registry.
Az SDD §14 viszont külső csereborítékot ír elő `format`, `formatVersion`,
`document` és `assetManifest` mezőkkel. A két verziót és a privacy-határt nem
szabad összemosni.

## Döntés

1. A natív, kezdeti formátum kizárólag UTF-8 JSON a
   `.strumsight-song.json` extensionnel. A root objektum kötelező és pontosan
   a következő contractot hordozza: `format: "strumsight-song"`,
   `formatVersion: 2`, `document` és `assetManifest`. A `format` a natív
   tartalmi felismerőjel; nincs bináris magic byte. A rossz extension warning,
   de az érvényes root felismerhető; rossz vagy hiányzó root fail-closed.
2. `formatVersion` a csereboríték verziója, nem a `document.schemaVersion`.
   E03-R09 pontosan a `formatVersion == 2`-t fogadja el. Újabb vagy régebbi
   csereverzió kontrollált, gépi kódú failure; a beágyazott dokumentumot a
   meglévő `SongDocumentCodec` saját schema-policyje validálja.
3. Az `assetManifest` a `document.assets` kanonikus, byte-tartalom nélküli
   manifestje. Exportkor a két lista értékazonos; importkor eltérésük failure.
   A kezdeti JSON nem csomagol asset-byte-okat, nem old fel fájlrendszerutat,
   és nem ír repositoryba.
4. A maximális natív JSON source méret **1 MiB (1_048_576 byte)**. A contract
   a deklarált `byteLength` alapján parse előtt elutasít, és az olvasott stream
   hosszát is számlálja, tehát hibás metadata sem kerülheti meg. A limit
   pontosan `max-1` és `max` esetén elfogad, `max+1` esetén failure.
5. A `SongImporter` E03-R09-ben data-layer contract: a platform picker nem
   lép be, a source csak `displayName`, `byteLength`, opcionális MIME és
   ismét megnyitható byte-stream. A cancellation token minimális contractja
   ugyanebben a fájlban él; a parser olvasási chunkok között ellenőrzi, és
   `cancelled` eredményt ad. Import eredménye kizárólag in-memory
   `SongDocument` + warning/report: perzisztálást, temp workspace-et,
   registryt és UI-t E03-R10 birtokol.
6. Export a codec kanonikus sorrendjére épül és nem ad export-időt vagy
   véletlen mezőt a tartalmi részhez. Nem jelenhet meg benne abszolút vagy
   temporary path, device/user azonosító, auth token, diagnostics vagy
   practice-history. A `SongSource.originalFileName` csak display-név:
   export előtt fájlnévre normalizálandó; path-like érték nem kerülhet ki.
   Az export-fájlnév külön sanitizált, a `SongId`-t nem módosítja.
7. A duplicate source SHA-256 warning, nem identity-összevonás. A duplicate
   dokumentumazonosító a natív tartalomban kontrollált import failure;
   repository lookup vagy persistent write ebben a körben tilos.

## Következmények

- A R09 tesztek a root/extension mátrixot, a két különböző version-fogalmat,
  a manifest-egyezést, a stream-számlált 1 MiB limitet, cancellationt,
  privacy-scrubot és determinisztikus hash-t közvetlenül mérik.
- A `SongDocumentCodec` csak a kanonikus belső document representationért
  felel; a külső envelope/policy az importers data-layerben marad.
- E03-R10 adhat registryt, temporary workspace-et és repository commitot,
  de nem gyengítheti az ADR 0091 vagy e döntés fail-closed szabályait.
