# ADR 0091 — Song import security boundary

**Státusz:** elfogadva (Epic 3 baseline round, E03-R01, pre-flight, 2026-08-02).
Formalizálja a [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
§13 (Importarchitektúra), §13.6 (Méret- és erőforráskorlátok), §15.6 (MXL
biztonság) és §29.1/§29.3/§29.4 (Offline alapelv, File security, Log
redaction) tervezetét kötelező érvényű döntéssé. A tényleges implementáció
importer-onként külön kör (E03-R09 natív JSON, E03-R10 import flow +
biztonsági határ, E03-R11 MusicXML/MXL, E03-R12 MIDI, E03-R13/R14 opcionális
Guitar Pro); ez a kör (E03-R01) csak a határt és a kötött korlátokat rögzíti,
importer-implementációt nem ír.

## Kontextus

Az Epic 3 a felhasználótól tetszőleges, nem megbízható strukturált
fájlokat fogad be (natív StrumSight JSON, MusicXML, tömörített MXL — ZIP —,
MIDI, opcionálisan Guitar Pro). Ezek mindegyike ismert, korábban CVE-ket is
adó támadási felületet hordoz: ZIP bomb / decompression bomb, XML external
entity (XXE) és entity expansion, path traversal kicsomagoláskor, malformed
bináris header crash, és önmagában is a StrumSight nem tárgyalható
termékhatáraiba ütköző hallgatólagos hálózati vagy fájlrendszer-írás
(AGENTS.md §5). A jelenlegi kódbázisban nincs fájlimport-út — ez az első
kör, amely nem megbízható, felhasználó által biztosított bináris/szöveges
tartalmat parse-ol.

## Döntés

1. **A formátum-felismerés nem bízhat kizárólag a fájlkiterjesztésben.**
   Magic byte, MIME type, XML root, ZIP tartalom, MIDI header vagy
   formátumspecifikus header alapján kell azonosítani; az extension és a
   tényleges tartalom eltérése warning vagy failure, sosem néma
   újra-interpretálás.
2. **Kétfázisú import: `probe` majd `import`.** A `probe` kevés adatot olvas,
   nem ír tartós fájlt, és csak becslést ad (formátum, alapmetaadat, track-
   és capability-becslés, "teljes parse szükséges" jelzés) — a felhasználó a
   teljes, drágább parse előtt lát egy előnézetet (§27.3 Import preview).
   Az `import` kizárólag temporary workspace-ben dolgozik; a
   `SongDocument`/asset perzisztálása (ADR 0090) csak sikeres validáció és
   normalizálás UTÁN történhet — sosem közvetlenül a végleges tárolóba
   streamelve.
3. **Kötelező, konfigurálható erőforráskorlát-készlet** (túllépés →
   kontrollált `ImportLimitFailure`, nem crash vagy timeout): source file
   byte size, archive compressed size, archive extracted size, archive entry
   count, XML node/event count, MIDI track count, note count, measure count,
   lyrics character count, artwork size, importer wall time, temporary
   workspace size.
4. **MXL (ZIP) feldolgozás kötött védelmi listája**: extracted-size limit,
   entry-count limit, path traversal tiltás, absolute path tiltás, symlink
   entry tiltás, duplicate entry kezelése, `META-INF/container.xml`
   validálása, XML entity expansion tiltása, external entity tiltása. Ez a
   lista minimum, nem cél — az importer implementáló körének (E03-R11)
   tesztfixture-öznie kell mindegyik esetet eldobható, valódi malformed
   inputtal (nem csak boldog úttal).
5. **A platform file-picker objektum nem léphet be a domainbe.** Az
   application réteg egy platform-független `ImportSourceFile`-t kap
   (`displayName`, `byteLength`, `openRead`, opcionális `mimeType`); nagy
   fájl sosem tölthető automatikusan teljes byte arrayként memóriába.
6. **Megszakítható, leak-mentes cancellation.** A parser a következő
   biztonságos ponton áll le; isolate/worker lezárul; temporary fájl törlődik;
   nincs library-rekord és nincs asset-reference leak félbehagyott importból.
7. **Offline-elv az importra is érvényes** (AGENTS.md §5, SDD §29.1): az
   importált score, backing track, lyrics, note sequence, file hash és
   dalcím alapértelmezetten nem hagyja el az eszközt; feltöltés csak
   kifejezett, külön dokumentált felhasználói művelet (pl. jövőbeli explicit
   export/share) esetén történhet.
8. **Log redaction kötött listája.** Nem logolható: teljes lyrics, teljes
   note sequence, teljes forrás-fájlútvonal, audio byte-tartalom, importált
   fájl teljes XML-je, token/user identity. Logolható: formátum, importer
   verzió, byte-size bucket, warning code, parse duration, track count,
   error type, redaktált fájlnév/extension — ugyanaz a redakciós minta, mint
   a Chapter 2 `AppFailure` logolásnál (AGENTS.md §6).
9. **Unsupported vagy sérült formátum fail-closed.** Nincs "próbáljuk meg
   mégis parse-olni" best-effort mód éles buildben; a hiba típusos
   `AppResult.failure`-ként jut vissza, sosem csendes részleges import.

## Alternatívák

- **Natív (platform-csatorna) XML/ZIP/MIDI parser library közvetlen
  használata bármilyen korlát nélkül:** elvetve — a fenti limitek és a
  cancellation/leak-mentesség enélkül nem garantálható, és a nem tárgyalható
  offline-elv (§29.1) sem auditálható egy fekete doboz library mögött
  korlátok nélkül.
- **Import minden validáció nélkül, "a felhasználó tudja mit importál":**
  elvetve — a ZIP bomb és XXE osztályú hibák nem a felhasználói szándéktól,
  hanem a fájl tartalmától függenek; egy rosszindulatú vagy sérült fájl a
  felhasználó tudta/szándéka ellenére okozhat erőforrás-kimerülést vagy
  crash-t.

## Következmények

- Minden importer (natív JSON, MusicXML/MXL, MIDI, opcionális Guitar Pro)
  ugyanazt a `SongImporter`/`ImporterRegistry` kontraktust és ugyanazt a
  korlát- és redakciós listát örökli — a biztonsági határ importer-onként
  nem újratárgyalható, csak a konkrét limit-értékek finomíthatók
  formátumspecifikusan.
- Az import-flow biztonsági határ (E03-R10) építhet erre a döntésre anélkül,
  hogy újra kellene igazolnia az alapelveket; a kör feladata a
  konfigurálható limit-értékek és a policy-egységteszt, nem az elv
  újratárgyalása.
- A Guitar Pro feasibility gate (§17, E03-R13) döntése (Dart parser vs.
  natív parser adapter vs. konverziós workflow) ennek a határnak keretein
  belül marad — natív parser adapter esetén a crash-isolation (§29.3) külön
  kötelező elem.
