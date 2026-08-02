# ADR 0113 — Song track/event model: core-type reuse and unknown-subtype codec policy

**Státusz:** elfogadva (E03-R04 pre-flight, 2026-08-02, orchestrátor: Claude
Sonnet 5). Formalizálja a
[`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) §11
(Track- és eventmodell) tervezetének két mért implementációs döntését.
Előfeltétele [ADR 0089](0089-song-document-v2.md) (SongDocument V2) és
[ADR 0093](0093-song-trainer-local-time-primitives.md) (Song Trainer lokális
idő-primitívek).

## Kontextus

Az E03-R04 brief §9 két kockázatot nevez meg, mindkettőt a pre-flight
hatáskörébe utalva:

1. „Core és Song Trainer tuning típus duplikálódhat; pre-flightban egyetlen
   canonical public contractot válassz."
2. „Sealed codec unknown subtype kezelése forward-compatibility döntést
   igényel; néma eldobás tilos."

A pre-flight megmérte az érintett meglévő kódot:

- `lib/features/song_trainer/domain/models/song_metadata.dart` és
  `data/local/song_document_codec.dart` **már ma** a `core/music/tuning.dart`
  `Tuning`/`Tunings` típusát használja `defaultTuning` mezőként — nincs
  song-trainer-lokális tuning típus, tehát a duplikáció-kockázat egy MÉG NEM
  létező, ebben a körben bevezetendő `SongInstrument` modellre vonatkozik,
  nem a meglévő kódra.
- `test/features/song_trainer/domain/song_document_test.dart` „Domain
  purity" scannere (`_forbiddenPatterns`) a `core/` importot **nem** tiltja —
  csak Flutter/Riverpod/Dio/SharedPreferences/l10n és a felsorolt
  cross-feature importokat. A `core/music/{chord,strum,tuning}.dart` import
  tehát auditáltan elérhető ebben a körben is (brief §2 „Jelenlegi állapot"
  megerősítve).
- `lib/core/music/strum.dart` `StrumDirection` enum ma pontosan két értéket
  hordoz: `down`, `up`. A kör brief-alapja (SDD §11.3) egy harmadik,
  `unknown` állapotot is előír a `SongStrumEvent.direction`-höz, „megjeleníthető
  és rhythm-scoringra használható, de direction scoringra nem" jelentéssel.
  `lib/core/music/strum.dart` **nincs** az E03-R04 `allowed_paths` listáján —
  bővítése ebben a körben tilos zóna (H3).
- `lib/features/song_trainer/data/local/song_document_codec.dart` már ma
  fail-loud mintát követ ismeretlen `SongSource.type` kódra
  (`SongDocumentCodecErrorCode.sourceTypeUnknown` — kivétel, nem néma
  eldobás); a track/event codec-bővítésnek ugyanezt a mintát kell követnie.

## Döntés

1. **`SongChordEvent.symbol` a core `Chord` (`core/music/chord.dart`)
   típusát viseli**, nem egy song-trainer-lokális chord wrappert. A `Chord`
   validálatlan `label`-wrapper — egy nem-támogatott, de megjeleníthető
   szimbólum (pl. egzotikus jazz-akkord) is tárolható benne veszteség
   nélkül; a §11.2 „unsupported chord megőrizheti az eredeti display
   textet" követelményt a különálló `displayText` mező fedi, nem a `Chord`
   validációja.
2. **`SongInstrument` a core `Tuning`-ot (`core/music/tuning.dart`) hordozza
   opcionális mezőként** (pengetős hangszereknél), nem definiál saját
   tuning típust. Ez az EGYETLEN canonical tuning contract a Song Trainer
   domainben — ugyanaz, amit a `SongMetadata.defaultTuning` már használ.
3. **`SongStrumEvent.direction` típusa `StrumDirection?`** (core enum,
   nullable) — a `null` érték kódolja az SDD §11.3 `unknown` állapotát. A
   mezőt a konstruktor kötelezően átveszi (`required this.direction`),
   csak az ÉRTÉKE lehet `null`; ez elkerüli egy párhuzamos
   `SongStrumDirection{down,up,unknown}` enum bevezetését, és nem igényel
   írási hozzáférést a tilos-zóna `core/music/strum.dart`-hoz. A
   direction-scoring réteg (jövőbeli kör, kívül a scope-on) `null` esetén
   nem ajánlhat fel irány-pontozást; a rhythm-scoring `null` esetén is
   használhatja az eseményt onsetként.
4. **Ismeretlen sealed track/event subtype dekódolásakor a codec kivételt
   dob, stabil, géppel olvasható kóddal** — pontosan a meglévő
   `sourceTypeUnknown` minta szerint (pl.
   `SongDocumentCodecErrorCode.trackTypeUnknown` /
   `eventTypeUnknown`), SOHA nem ejti csendben az ismeretlen bejegyzést és
   SOHA nem esik vissza alapértelmezett altípusra. A repository felelőssége
   marad az így elkapott hiba felhasználó felé történő, nem-destruktív
   jelzése (ugyanaz a réteg-felelősség, mint a séma-verzió-túllépésnél).

## Alternatívák

- **Song-trainer-lokális `Chord`/`Tuning` wrapper típus:** elvetve — a
  brief §2 kifejezetten „csak auditált core importtal használható" korlátot
  ír elő, és a meglévő kód (metadata, codec) már a core típust használja;
  egy párhuzamos típus pontosan az elkerülni kívánt duplikációt hozná
  létre.
- **`core/music/strum.dart` `StrumDirection` enum bővítése `unknown`
  értékkel:** elvetve — a fájl nincs az `allowed_paths` listán, a bővítés
  tilos zónát nyitna (H3), és a `Strum`/`ChordEvent` (Live feature) más
  fogyasztóinak viselkedését is érintené egy ehhez a körhöz nem tartozó
  auditon kívül.
- **Külön `SongStrumDirection{down,up,unknown}` enum:** elvetve — a nullable
  `StrumDirection?` ugyanazt az információt hordozza egyetlen új típus
  nélkül, és a meglévő `Strum`/`ChordEvent` mintával (ahol a direction már
  ma is opcionális `StrumDirection?` a `ChordEvent`-ben) konzisztens marad.
- **Ismeretlen subtype csendes kihagyása dekódoláskor:** elvetve — a brief
  §9 explicit tiltja („néma eldobás tilos"), és ez a minta már ma sem így
  működik a `source.type`-ra.

## Következmények

- A Song Trainer domain három core importot fogyaszt auditáltan:
  `core/music/chord.dart`, `core/music/tuning.dart` és
  `core/music/strum.dart` (csak az enum, nem a `Strum`/`ChordEvent`
  osztály). A `song_document_test.dart` purity scannere ezt már ma átengedi
  — nem igényel tesztváltoztatást.
- A `StrumDirection?` nullable mintát a codec-bővítésnek és minden jövőbeli
  fogyasztónak (capability resolver, scorer — kívül e kör scope-ján)
  tiszteletben kell tartania: `null` ≠ hiányzó adat, hanem explicit
  „ismert, hogy irány nem volt megállapítható" állapot.
- Egy jövőbeli kör, ha a `core/music/strum.dart` enumot mégis bővíteni
  akarja `unknown` értékkel, ehhez az ADR-hez képest külön döntést és saját
  `allowed_paths`-ot igényel (a Live feature egyidejű auditjával).
