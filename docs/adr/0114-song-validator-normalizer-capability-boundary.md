# ADR 0114 — Validator/normalizer/capability resolver: chord-support boundary and severity→capability contract

**Státusz:** elfogadva (E03-R05 pre-flight, 2026-08-02, orchestrátor: Claude
Sonnet 5). Formalizálja a
[`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
Kör 5 tervezetének két, a pre-flight során mért döntését.
Előfeltétele [ADR 0089](0089-song-document-v2.md),
[ADR 0093](0093-song-trainer-local-time-primitives.md) és
[ADR 0113](0113-song-track-event-model.md).

## Kontextus

Az E03-R05 brief (`docs/rounds/e03-r05-validator-normalizer-capabilities.md`)
§9 két kockázatot nevez meg: a normalizer szemantikai túlterjeszkedése, és a
warning/fatal severity összemosása a capabilityvel. A pre-flight megmérte az
érintett meglévő kódot:

1. **Nincs megosztott „ismert akkord" halmaz.** `lib/core/music/chord.dart`
   `Chord` egy validálatlan `label`-wrapper — bármely string érvényes érték,
   csak a `transposeLabel` gyökér-parsolása feltételez egy root+opcionális
   accidental szerkezetet. Az EGYETLEN ma létező maj/min szótár
   (`lib/features/practice/data/adapters/legacy_chord_label.dart`,
   `legacyPracticeChordLabel`) a `practice` feature-ben él. A
   `test/features/song_trainer/domain/song_document_test.dart` domain-purity
   scannere (`_forbiddenPatterns['cross-feature import']`) a
   `package:strumsight/features/practice/…` importot **explicit tiltja** —
   ez az import ezen kívül nincs is a kör `allowed_paths` listáján (H3).
   Tehát a capability resolver „támogatott akkord" fogalma **nem
   származtatható** a practice-dictionary-ból.
2. **A `NoteTrackAnalyzer` (E03-R04) csak strukturális tényt jelent, nem
   capabilityt.** `note_track_analyzer.dart` saját doksija szerint: „the
   capability resolver (a future round) translates these facts into 'this
   track supports pitch scoring yes/no' statements" — az `isMonophonic`
   bool már ma is mért, valódi input állítja elő (két különböző pitch-ű,
   időben átfedő `SongNoteEvent`), de a capability-döntést eddig semmi nem
   hozta meg.
3. **A dokumentum-szintű „fatal range/map" állapot valódi, elérhető input
   eredménye, nem csak elméleti él.** `SongSection` (E03-R03) önmagában
   validál (`startMeasure`/`endMeasureExclusive` önkonzisztencia), de **nem**
   veti össze a `SongDocument.measures` tényleges hosszával — egy
   szekció-lista, amely a dokumentum saját `measures` listáján túli indexre
   mutat, ma semmilyen konstruktorban nem bukik el. Ugyanez igaz a
   track-eseményekre (pl. `SongStrumEvent.targetChordId` egy nem létező
   `SongChordEvent.id`-re mutathat) — egyik modell sem látja a testvér
   kollekciókat saját konstruálásakor.

## Döntés

1. **A „támogatott akkord" osztályozás önálló, domain-lokális, zárt
   grammatika** (gyökérhang + opcionális kis/nagy minőség-jelölés, a
   `Chord.transposeLabel` már meglévő gyökér-parsolásához hasonló alakban),
   **NEM** a practice feature szótárának importja vagy másolata. A két
   osztályozó (`song_trainer` capability resolver vs. `legacyPracticeChordLabel`)
   szándékosan **függetlenül divergálhat** — a scoring-parity a practice
   adapter réteg felelőssége lesz egy jövőbeli, ehhez az ADR-hez képest
   külön kör-scope-ban, ha a Song Trainer valaha a Practice Engine-t hívja.
2. **A validation severity (`fatal`/`warning`, bővíthető taxonómia) az
   EGYETLEN forrás a persist-jogosultsághoz**: bármely `fatal` lelet →
   `persist capability = false`. A capability (display/scoring, track- és
   dimenziónkénti) **külön, önállóan számított tengely** — lehet `false`
   akkor is, ha `persist = true` (pl. ismeretlen akkord: persistálható, de
   a chord-scoring capability hamis). A két tengelyt összevonni tilos — ezt
   a kör `Kötelező megkülönböztető mátrix`-a (§6) explicit megköveteli.
3. **A dokumentum-szintű validáció additív a már önmagukat validáló
   modellek felett**: a validator a modellek KÖZÖTTI konzisztenciát nézi
   (pl. szekció measure-tartomány a dokumentum tényleges `measures.length`-e
   ellen, `targetChordId` a track eseményhalmaza ellen) — ezt egyetlen
   egyedi konstruktor sem tudja ellenőrizni, mert nem látja a testvér
   kollekciókat.

## Alternatívák

- **A practice `legacyPracticeChordLabel` szótár megosztása egy
  `core/music` exporton át:** elvetve — ma nem létezik ilyen export, a
  létrehozása `core/music` módosítás lenne, ami kívül esik ennek a körnek
  az `allowed_paths`/scope-ján; a két osztályozó szándékos szétválasztása
  olcsóbb, mint egy új megosztott core-kontraktus bevezetése egy nem-
  architekturális körben.
- **Severity és capability egy közös enumba olvasztása:** elvetve —
  ellentmond a brief §6 mátrixának (ismeretlen akkord persistálható ÉS
  scoring-tiltott egyszerre; polyphonic note persistálható ÉS
  pitch-scoring-tiltott egyszerre) — egy összevont flag nem tudná
  kódolni ezt a négy kombinációt.

## Következmények

- A `song_validator.dart`/`song_normalizer.dart`/`song_capability_resolver.dart`
  egyike sem importálhat semmit a `practice` (vagy bármely más feature)
  alól — a domain-purity scanner ezt már ma is tiltja, nincs teszt-oldali
  módosítás.
- A capability resolver „támogatott akkord" grammatikáját ennek a körnek
  KELL bevezetnie és tesztelnie (nincs rá előzetes, megosztott igazságforrás)
  — ez a kör explicit feladata, nem egy másik kör tartozéka.
- Egy jövőbeli kör, ha a Song Trainer chord-track-eket a Practice Engine
  scoring útjára köti be, saját döntést igényel arról, hogyan viszonyul a
  két (song-trainer-lokális vs. legacy-practice) osztályozó egymáshoz —
  ez az ADR nem dönt erről előre.
