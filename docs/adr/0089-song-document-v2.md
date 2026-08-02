# ADR 0089 — SongDocument V2 domain model

**Státusz:** elfogadva (Epic 3 baseline round, E03-R01, pre-flight, 2026-08-02).
Formalizálja a [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
§9 (SongDocument V2), §9.2 (SongId/revision), §9.5 (Sectionök) és §9.6
(Measure) tervezetét kötelező érvényű döntéssé. A tényleges implementáció
külön kör (E03-R02 — SongDocument V2 azonosítók és metaadatok, E03-R03 —
Section/measure/tempo/meter/SongTimeMap); ez a kör (E03-R01) csak a döntést
rögzíti, kódot nem ír.

## Kontextus

A jelenlegi legacy `Song`/`Setlist` modell (`lib/features/songs/model/`) egy
lapos, `SharedPreferences`-be szerializált struktúra: nincs stabil section-,
measure- vagy multi-track fogalma, a revision-kezelés hiányzik (két egyidejű
szerkesztés némán felülírhatja egymást), és a forrás (kézzel írt vs.
importált) nem különül el a dokumentumban. Az Epic 3 célja strukturált
importot (MusicXML/MXL, MIDI, opcionális Guitar Pro), többsávos lejátszást és
szakasz/measure-alapú gyakorlást hoz — ez a legacy modellben nem
reprezentálható inkrementálisan, mert nincs hova felvenni a track-, section-
és tempo/meter-map fogalmakat konfliktus nélkül a meglévő mezőkkel.

A döntés nem érinti a legacy `Song`/`Setlist` production útvonalát — az
E03-R01 scope-ja kifejezetten kizárja a SongDocument implementációt és a
legacy adatok írását/migrációját (lásd a kör briefje §3).

## Döntés

1. **Új, párhuzamos domain modell.** A `SongDocument` a
   `lib/features/song_trainer/domain/model/` alá kerül (E03-R02+), a legacy
   `Song`/`Setlist` melletti, azoktól független típusként — nem azok
   kiterjesztéseként vagy alosztályaként. A mezőkészlet a §9.1 szerint:
   `schemaVersion`, `id`, `revision`, `metadata`, `source`, `sections`,
   `measures`, `tracks`, `tempoMap`, `meterMap`, `keyMap`, `assets`,
   `markers`, `createdAt`, `updatedAt`.
2. **Stabil, lokálisan generált `SongId`.** Fájlnévben biztonságosan
   használható, nem függ kizárólag `DateTime.now()`-tól, és újraimportáláskor
   nem keveredik automatikusan a forrás-hash-sel — az egyezés felismerése
   explicit felhasználói döntés, nem hallgatólagos dedup.
3. **Monoton `revision` optimistic concurrency-hez.** Minden sikeres írás
   növeli; a repository (ADR 0090) az elvárt revisiont ellenőrzi íráskor, hogy
   két versengő editor-mentés ne írja felül némán egymást.
4. **`SongSource` őrzi a proveniencia-láncot.** Típus (`legacyLocal`,
   `createdInApp`, `strumSightJson`, `musicXml`, `compressedMusicXml`, `midi`,
   `guitarPro`), eredeti fájlnév, SHA-256, import időpont, importer verzió,
   opcionális formátumverzió és warning-összegzés — ez teszi lehetővé az
   importer-specifikus fidelity-jelentést (ADR 0091) és a legacy-parity
   auditot (E03-R06) anélkül, hogy a domain modellbe formátum-specifikus
   mezők szivárognának.
5. **Section és measure explicit, nem levezetett.** A section
   measure-határokhoz igazodik, nem lehet üres vagy dalon kívüli; hiányzó
   section esetén a rendszer egy automatikus `Full song` sectiont biztosít —
   a Trainer setup és a range-választás (§23) sosem szembesül
   section nélküli dallal. A measure repeat-jelöléseit az importer véges,
   lineáris playback-sequence-szé bontja; végtelen vagy ciklikus repeat
   szerkezet a normalizált timeline-ban tilos.
6. **Determinisztikus equality/copy/serialization az elsődleges
   követelmény**, nem egy konkrét codegen-eszköz. Immutable code generation
   használható, ha az Epic 1 coding standard (AGENTS.md §10) engedi, de az
   ADR nem írja elő.

## Alternatívák

- **A legacy `Song` modell bővítése section/track mezőkkel:** elvetve — a
  meglévő ~200+ hívási hely (Learn, Builder, Setlist combine) viselkedése a
  jelenlegi lapos alakra épül; a bővítés vagy törné a parity-t, vagy egy
  nem-normalizált, két célra optimalizált hibrid modellt eredményezne.
- **Egyetlen egyesített modell azonnali migrációval:** elvetve — az Epic 3
  scope-ja kifejezetten kizárja az azonnali legacy-adatírást (E03-R01 §3);
  az egyesítés a rollout-döntés (feature flag ON) utáni külön kör feladata
  (E03-R08 — perzisztens V2 migráció).

## Következmények

- A `lib/features/song_trainer/domain/` réteg framework-independent marad
  (`tool/check_architecture.dart` őrzi, mint a Practice V2-nél, ADR 0068).
- A legacy és V2 modell egy ideig párhuzamosan él; az adapterek (ADR-számot
  nem igénylő E03-R06 kör) végzik az egyirányú, veszteségmentes vagy
  dokumentáltan veszteséges leképezést.
- A `SongId`/`revision` szerződés előfeltétele a §18 repository atomikus
  írásának (ADR 0090) és a §21 Practice Engine integráció forrás-mappingjének
  (ADR 0092, `SongEventReference.songRevision`).
