# ADR 0215 — Analysis document versioning

- **Státusz:** Elfogadva (E06-R01 pre-flight, 2026-08-11)
- **Kör:** E06-R01 — Analyze V1 baseline, mérés és ADR-ek
- **Implementer motor:** Terra (Codex CLI, `~/.codex-terra`, `gpt-5.6-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Sonnet 5) írta a
  pre-flightban (ADR 0055, pipeline-prompt §0 — a hat ADR mindegyikét az
  orchesztrátor írja, brief §0.0).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 1; §9.1 (`AnalysisDocument`), §9.7 (Időábrázolás), §10.5 (Migráció)
- **Kontext-ADR-ek:** [0089](0089-song-document-v2.md)
  (a `SongDocument.schemaVersion` + fail-closed elutasítás precedense,
  E03-R02), [0198](0198-learn-migration-rollout-boundary.md) (a legutóbbi
  párhuzamos-V2 rollout mintázat)
- **Sorszám-jegyzet:** a brief 2026-08-07-i fejléce „0200"-at írt elő; a
  `tools/round-slots.py reserve-adr` 2026-08-11-i futása **0215**-öt adott —
  lásd a brief §0.0 R1 revízióját a hat ADR teljes átszámozásáról.

## Kontextus

**Mért 2026-08-11-én** (pipeline-prompt §1 mérési szabálya — a hivatkozott
mezőket a kódból, nem a leírásból):

1. A jelenlegi `AnalyzeResult` (`lib/features/analyze/model/analyze_result.dart:113-121`)
   mezői: `durationSec` (`double`), `bpm` (`double`), `chords`, `strums`,
   `beatsPerBar` (int, default 4), `diagnostics?`. **Nincs** `schemaVersion`,
   provenance, per-metrika confidence vagy availability mező. Az idő
   **lebegőpontos másodpercben** van, nem egész mikroszekundumban vagy
   `Duration`-ben.
2. A `SongDocument` (E03-R02, [ADR 0089](0089-song-document-v2.md))
   már megoldotta ugyanezt a problémát a Song Trainer V2 alatt:
   `songDocumentSchemaVersion = 1` konstans,
   `schemaVersion < songDocumentSchemaVersion` esetén
   `SongDocumentValidationException` (`schemaVersionOutOfRange` kód) —
   **kontrollált hiba a konstruktorban, nem best-effort olvasás**
   (`lib/features/song_trainer/domain/models/song_document.dart:55-99`).
3. Ugyanez a feature már bevezette az **egész mikroszekundum** Duration-
   szerializációt: `song_document_codec.dart` `event.start.inMicroseconds` /
   `event.duration.inMicroseconds` (`startMicros`/`durationMicros` JSON-mezők,
   `_requireDurationMicros` a visszaolvasásnál) és a `SongTimeMap`
   (`domain/services/song_time_map.dart:21-49`) `Duration(microseconds: total)`
   — egyetlen kerekítési pont, nem szegmensenkénti lebegőpontos összegzés.
4. Az SDD Ch7 §9.1 az `AnalysisDocument`-et `schemaVersion` (int) mezővel
   írja elő; §9.7 kimondja: „Domainben előnyben részesítendő: `Duration`;
   vagy egész mikroszekundum / samples index. A lebegőpontos másodperc csak
   serializációs és UI boundaryn használható." §10.5 „Migráció" a régi
   store nem-destruktív, validáció-utáni törlését írja elő (a §24.6 elv).
5. A jelenlegi Library-rétegben (`AnalyzedSession`/`KeyValueLibraryRepository`)
   **nincs** verziómező; a `JsonCollectionStore` a `ss.library.sessions`
   kulcson egyetlen listát tart, verzió-jelzés nélkül.

## Döntés

1. **`AnalysisDocument.schemaVersion` kötelező, egész (`int`) mező** —
   ugyanaz a minta, mint `SongDocument.schemaVersion`: egy dokumentum-szintű
   konstans (`analysisDocumentSchemaVersion`) rögzíti a legalacsonyabb
   olvasható verziót.
2. **Ismeretlen vagy alacsonyabb `schemaVersion` kontrollált hiba, nem
   best-effort olvasás.** A codec/repository egy stabil, névtérrel ellátott
   hibakóddal (`analysisDocument.schemaVersion.unsupported` mintájára, a
   `SongDocumentValidationCode` precedense) utasítja el a dokumentumot;
   a hívó karanténba teszi (a `SongRepositoryRecovery`/`FileSongRepository`
   mintája), a felhasználó többi sessionje nem sérül.
3. **Minden domain `Duration`-érték egész mikroszekundumban szerializálódik**
   (`inMicroseconds`/`Duration(microseconds: …)`), a `song_document_codec.dart`
   `startMicros`/`durationMicros` mintáját követve. Lebegőpontos másodperc
   **kizárólag** a UI-rétegben (megjelenítéshez) vagy egy külső formátumba
   exportáláskor jelenhet meg, sosem a domain/serializáció boundaryn belül.
4. **A `schemaVersion` bump szabálya:** csak akkor emelkedik, ha a wire-alak
   inkompatibilisen változik (mező törlése/átnevezése, típusváltás,
   időbázis-váltás) — additív, hátrafelé kompatibilis mező **nem** igényel
   verzióemelést (a `SongDocument` migrációs elvének átvétele).

**NEM elfogadható:** lebegőpontos másodperc a domain-modellben vagy a
JSON-boundaryn; verzió nélküli (vagy string-verziójú, pl. `"v2"`) JSON;
ismeretlen `schemaVersion` csendes legjobb-erőfeszítéses beolvasása
(mező-alapértékek kitalálása); a régi V1 `AnalyzeResult`/`AnalyzedSession`
séma módosítása ennek a döntésnek a jegyében (az V1 a teljes Epic alatt
változatlan marad, [ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)).

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; az Epic 6 implementation evidence rögzítve, a rollout shadow szinten marad.

- A V2 `AnalysisDocument` domainmodellje (E06-R02) a `schemaVersion`
  mezővel és a fail-closed konstruktor-validációval indul — ez a kör csak a
  szerződést rögzíti dokumentumban, kódot nem ír.
- A codec (E06-R03) a mikroszekundum-szerializációt a `song_document_codec.dart`
  meglévő mintája szerint írja meg — nem kell új konvenciót kitalálni.
- A Library-réteg V2 storage-ja (E06-R21) örökli a karantén-mintát
  (`SongRepositoryRecovery` analógja) sérült/ismeretlen verziójú
  dokumentumokra.
- A V1 `AnalyzeResult` (lebegőpontos `durationSec`/`bpm`) **érintetlen
  marad** — ez a döntés kizárólag a V2 útra vonatkozik.

## Elutasított alternatívák

- **String-verzió (`"v1"`, `"v2"`) egész helyett.** Elvetve: az egész
  verziószám egyszerű `<`/`>=` összehasonlítást tesz lehetővé migrációs és
  kompatibilitási döntésekhez; a string-verzió lexikografikus csapdákat rejt
  (`"v10" < "v2"`).
- **Best-effort olvasás ismeretlen verzióra** (hiányzó mezők alapértékkel
  pótolva). Elvetve: egy csendesen félreértelmezett régi/új dokumentum
  hibás metrikát mutatna a felhasználónak — ez pontosan az a hiba-osztály,
  amit az [ADR 0204](0219-analysis-capability-aware-publication.md)
  „unavailable, magyarázattal" elve tilt.
- **Lebegőpontos másodperc megtartása a domainben** (csak a séma
  verziózása). Elvetve: az SDD §9.7 kifejezetten kizárja, és a
  `SongTimeMap` már bizonyította, hogy az egész-mikroszekundum
  reprezentáció determinisztikus, kerekítés-mentes összeadást tesz
  lehetővé, amit a lebegőpontos alak nem garantál.

## A visszavonás feltétele

Ez a döntés akkor vizsgálandó felül, ha (a) a mikroszekundum-felbontás
bizonyítottan elégtelennek bizonyul egy jövőbeli nagy-pontosságú metrikához
(pl. szub-mikroszekundumos fázis-elemzés) — ekkor nanosecond-alapú
váltás egy ÚJ major `schemaVersion`-nel, nem a meglévő csendes bővítésével;
vagy (b) a Song Trainer V2 saját, később mért gyakorlata (E03 follow-up)
egy jobb karantén- vagy verzió-jelzési mintát alakít ki, amit ez a feature
is átvehet — ADR-hivatkozással, nem hallgatólagos eltéréssel.
