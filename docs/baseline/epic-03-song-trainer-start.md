# Epic 3 — Song Trainer baseline — a legacy Songs/Setlists kiinduló állapota

**Felvéve:** 2026-08-02 (E03-R01, round 224)<br>
**Production-kód alapja:** `main@6a45486`; a pre-flight commit
`6c75bca` (ADR 0089–0092 + PLANNING brief).<br>
**Cél:** a működő `Song`/`Setlist` modell és a `SharedPreferences`-alapú
repository mérhető kiindulópontja az Epic 3 (SongDocument V2 +
file/asset storage + importer + Practice Engine integráció) számára, nem
új domain-specifikáció.

Az E03-R01 a legacy production kódot nem módosítja. A viselkedési baseline a
hét ön-készítésű, jogtiszta JSON snapshot
(`test/fixtures/song_trainer/legacy/*.json`), a determinisztikus mérőszámokat
pedig a `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`
rögzíti. Eltérés csak az ADR 0089–0092 (pre-flight, a §0.0-ban részletezett
sorszámokon) és a későbbi SongDocument V2 körök (E03-R02+) szerint fogadható
el.

## Scope és nem-scope (E03-R01)

- **Benne:** a jelenlegi `Song`/`Setlist` perzisztencia, JSON séma, támogatott
  meterek, Song Builder, Learn integráció, Setlist combine, hét ön-készítésű
  legacy fixture, üres `lib/features/song_trainer/public.dart` boundary, és a
  `songTrainerV2Enabled` default-off feature flag.
- **Kívül — ebben a körben TILOS:** SongDocument implementáció, legacy adat
  írása vagy migrációja, navigáció/UI, bármely flag rollout, a Practice
  public contract belső importtal történő bővítése.

## Szerepek és rollout-guard (E03-R01 §5.1)

A hetedik availability flag csatlakozott a `FeatureFlags` típushoz
(`lib/app/config/feature_flags.dart`):

| Flag | development | lab | production |
|---|---:|---:|---:|
| `accountEnabled` | `false`¹ | `false`¹ | `false`¹ |
| `diagnosticsEnabled` | `true` | `true` | `false` |
| `labModeAvailable` | `true` | `true` | `false` |
| `practiceEngineV2Enabled` | `true` | `true` | `false` |
| `migratedLearnEnabled` | `false` | `false` | `false` |
| `practiceDetailedHistoryEnabled` | `true` | `true` | `false` |
| **`songTrainerV2Enabled`** | **`false`** | **`false`** | **`false`** |

¹ Az `accountEnabled` értéke a `STRUMSIGHT_ACCOUNT` dart-define-tól függ;
alapértelmezetten `false`, mert nincs hosztolt backend.

Az új flag egyetlen környezetben sem `true` (még a development és a lab
buildben sem) — a `nonProd` származtatás nem terjed ki rá. A flag
`forEnvironment` és a direkt `const FeatureFlags(...)` konstruktor
egyaránt `false`-szal inicializálja, és a konstruktor
`[this.songTrainerV2Enabled = false]` alapértelmezettje is `false`. A
`lib/features/song_trainer/public.dart` boundary mindaddig üres, amíg egy
későbbi kör (E03-R02+) nem exportál rajta konkrét típust.

A hálózati kapcsoló (`usesNetwork`) változatlanul
`accountEnabled || diagnosticsEnabled` — az új flag nem hálózati kapcsoló,
és a `practiceEngineV2Enabled`/`migratedLearnEnabled`/
`practiceDetailedHistoryEnabled` függőségi szabályok (E02-R19 §A4) sem
változnak.

## Jelenlegi Song és Setlist fájlok

| Fájl | Méret | Felelősség |
|---|---:|---|
| `lib/features/songs/model/song.dart` | 165 sor | `Song` immutable modell, `toLesson`/`toAnalyzeResult`/`toJson`/`fromJson`/`copyWith`/`_fitToMeter` |
| `lib/features/songs/model/setlist.dart` | 105 sor | `Setlist` immutable modell, `resolve`/`combine`/`toJson`/`fromJson` |
| `lib/features/songs/data/songs_repository.dart` | 50 sor | `SongsRepository` interface, `KeyValueSongsRepository`, `songsRepositoryProvider` |
| `lib/features/songs/data/setlists_repository.dart` | 50 sor | `SetlistsRepository` interface, `KeyValueSetlistsRepository`, `setlistsRepositoryProvider` |
| `lib/features/songs/providers/songs_provider.dart` | 110+ sor | `SongsController` Notifier; CRUD (`add`/`update`/`remove`); max 200 dal, newest-first evict |
| `lib/features/songs/providers/setlists_provider.dart` | (hasonló) | `SetlistsController`; max 100 setlist, newest-first evict |
| `lib/features/songs/screens/*` | több fájl | Song List / Song Editor / Setlist List / Setlist Detail |
| `lib/features/songs/widgets/*` | több fájl | Song card, strum pattern editor, chord editor |
| `lib/features/songs/theory/strum_patterns.dart` | (egy fájl) | 6 preset 4/4 minta, 1 preset 3/4 minta |
| `lib/features/songs/public.dart` | 7 sor | A legacy cross-feature boundary: kizárólag `Song`-t exportál |

A feature-nek **nincs** saját alábbi sajátossága, és a Chapter 2
`Architecture` rétegszabálya (`lib/features/songs/` más feature-öket nem
importál) tiszteletben marad: a `Song.toLesson` a Learn típusait
használja (`Lesson`, `LessonEvent`), és a `toAnalyzeResult` az Analyze
`AnalyzeResult`/`TimelineChord`/`TimelineStrum` típusait — ezek a
`lib/features/songs/public.dart` boundary-n keresztül érhetők el, nem
belső importtal.

## Perzisztencia kulcsok

A `KeyValueStore` absztrakció alatt `SharedPreferences`-re épülő
`JsonDocumentStore` tartja a dal- és setlist-dokumentumot
(`lib/core/storage/json_document_store.dart`):

| Kulcs | JSON envelope | Limit | Migráció |
|---|---|---:|---|
| `ss.songs.songs` | `{"schemaVersion": 1, "items": [...]}` | `SongsRepository.maxSongs` = 200 | legacy kulcs: `songs` (pre-envelope) |
| `ss.songs.setlists` | `{"schemaVersion": 1, "items": [...]}` | `SetlistsRepository.maxSetlists` = 100 | legacy kulcs: `setlists` (pre-envelope) |
| `ss.storage.schema_version` | `int` | n/a | nincs; a migrátor írja ([`docs/adr/0010-storage-migrator.md`](../adr/0010-storage-migrator.md)) |

A kulcsok forrása a `lib/core/storage/storage_keys.dart` `StorageKeys` és
`LegacyStorageKeys` absztrakt osztályok. A Song/Setlist dokumentumok a
`documentSchemaVersion` (1) envelope sémát írják; a song- és setlist-szintű
`fromJson` a `core/foundation/json_validation.dart` `requireString` /
`requireInt` / `requireStringList` / `optionalInt` segédjeivel validál.

## JSON séma

### Song

| Mező | JSON kulcs | Típus | Kötelező | Default | Megjegyzés |
|---|---|---|:---:|---|---|
| `id` | `id` | `String` | igen | — | A provider a `DateTime.now().microsecondsSinceEpoch` + sequence alapján generálja |
| `name` | `name` | `String` | igen | — | `allowEmpty: true`; üres név is megengedett |
| `chords` | `chords` | `List<String>` | igen | — | `maxLength: 512`; üres string elutasítva |
| `pattern` | `pat` | `String` | igen | — | `d`/`u`/`-` karakterek sorozata; `_fitToMeter` vág/padló a `bpb * 2` hosszra |
| `bpm` | `bpm` | `int` | igen | — | `[1, 400]`; BPM |
| `beatsPerBar` | `bpb` | `int` | nem | `4` | `[1, 16]`; a `fromJson` `optionalInt(..., fallback: 4)` |

A `pat` karakterenként dekódolódik:
`d` → `StrumDirection.down`, `u` → `StrumDirection.up`, bármi más →
`null` (rest). A `pattern` hossza a konstruktorban
`beatsPerBar * 2` (4/4 → 8, 3/4 → 6), és a `_fitToMeter`
statikus korrigálja a hossz-eltérést
(`lib/features/songs/model/song.dart:142-154`).

### Setlist

| Mező | JSON kulcs | Típus | Kötelező | Default | Megjegyzés |
|---|---|---|:---:|---|---|
| `id` | `id` | `String` | igen | — | |
| `name` | `name` | `String` | igen | — | `allowEmpty: true` |
| `songs` | `songs` | `List<String>` | igen | — | `maxLength: 500`; song id-k, play-order; hiányzó id `resolve`-ban kimarad |

A setlist csak song id-ket tárol; a tényleges song-ok a `resolve`
segítségével a songbookból kerülnek feloldásra lejátszáskor.

## Támogatott meterek

A `beatsPerBar` mező opcionális; a `fromJson` `4` alapértékkel tölti
fel. A `Lesson._expand` a `beatsPerBar * 2` hosszúságú pattern-t vár, és
a `Song._fitToMeter` garantálja ezt a hosszt
(`lib/features/learn/model/lesson.dart:74-100`,
`lib/features/songs/model/song.dart:142-154`). A Song Builder a
`StrumPattern` preset készletből 4/4 és 3/4 mintát is felkínál
(`lib/features/songs/theory/strum_patterns.dart`), és a `SongMeterTest`
védi a 3/4 szerializáció/deszerializáció kört
(`test/features/songs/song_meter_test.dart`).

A jelenlegi támogatott értékek a gyakorlatban: **4** és **3**. A
modell-oldali korlát `[1, 16]`, de a Song Builder UI és a Learn
highway ismétlődési számítása 3/4 és 4/4 mellett van ellenőrizve.

## Song Builder funkciók

- **CRUD** a `SongsController` Notifier-en: `add`, `update`, `remove`
  (`lib/features/songs/providers/songs_provider.dart`).
- **Azonosító** generálás: `DateTime.now().microsecondsSinceEpoch + _seq`
  (microsecond-ütközés védett). A tesztek ezt seed-elt
  `SharedPreferences.setMockInitialValues({})` felülírással
  izolálják.
- **Perzisztencia**: `_repo.save(state)` minden mutáció után. A
  r149/r150 race javítása óta a `SongsRepository.load()` szinkron,
  így nincs async gap a `build()` és az első mutáció között.
- **Cap**: 200 dal (`SongsRepository.maxSongs`); túlcsorduláskor a
  legrégebbi (lista végi) dal esik ki — **newest-first** eviction
  (`songs_repository.dart:36-40`).
- **Pattern Editor** widget (`StrumPatternEditor`,
  `lib/features/songs/widgets/strum_pattern_editor.dart`) 4/4 és 3/4
  mintákhoz.
- **Tap tempo** (round 142) a Song Editorban
  (`test/features/songs/song_tap_tempo_test.dart`).

## Learn integráció

A `Song.toLesson()` egy `Lesson` példányt épít, amely a Learn pipeline
play-along útján játszódik:

- `id`: `song_$songId`; ez különbözteti meg a song-ot a 16 tantervi
  leckétől a progress/streak riportokban
  (`lib/features/songs/model/song.dart:62-69`).
- `bpm`: a dal BPM-je.
- `chordSequence` és `pattern` ugyanaz, mint a dalban.
- A `Lesson.beatsPerBar` a dal `beatsPerBar` értékét kapja; a
  `Lesson._expand` ebből számítja a `beatsPerBar * 2` hosszú pattern-t.
- A `LearnScreen` nem tesz különbséget tantervi és user-dal között,
  kivéve a `firstWin` speciális esetét
  (`lib/features/learn/screens/learn_screen.dart`).
- A `LessonTiming` 4/4 és 3/4 leckéket egyaránt lejátszik
  (`lib/features/learn/lesson_timing.dart`); a 3/4 dalok
  `Lesson._expand`-je a hattagú pattern-t hat eventté bontja (3 le +
  3 fel, ha minden slot aktív).

A Learn integráció meglétének legacy baseline-bizonyítéka a
`test/features/learn/setlist_expected_hint_test.dart` — a
kombinált setlist-lesson hintje a dal-határt követi, a tempo-warp
ellenére.

## Setlist combine viselkedés

A `Setlist.combine(List<Song>)` egyetlen `Lesson`-t épít, amely
visszafelé lejátszva a song-okat a setlist sorrendjében, az első dal
BPM-jét referenciaként használva:

- **Referencia BPM** az első song BPM-je (`songs.first.bpm`).
- **Beat warp**: minden song saját BPM-jét megtartja. Az adott song
  minden eventjének beat-koordinátája megszorozódik `refBpm /
  song.bpm`-mel, és hozzáadódik a futó `beatOffset`-hoz.
- **Összesített hossz**: `beatOffset` a kombinált lesson `totalBeats`
  mezője.
- **Megfelelő metronóm/grid**: a `beatsPerBar` a nyitó dal metrumára
  áll (`songs.first.beatsPerBar`). Őszinte korlát: egy későbbi dal
  más metrumban a saját valós idejét tartja, de a rajzolt
  grid/metronóm akcentus a nyitó dal metrumát követi.
- **`resolve`**: a setlist `songIds` listáját a songbookra vetíti; a
  nem létező id-k kimaradnak, a sorrend megmarad
  (`lib/features/songs/model/setlist.dart:36-46`).

A kombinált lesson `id` értéke `setlist_$setlistId`, hogy a
progress/streak riportokban a setlistek külön entitásként
szerepeljenek.

A `combine` üres setlistre (`songIds: []`) üres leckét ad — a védő
ág biztosítja, hogy ne legyen 0 hosszú, de nem-üres lesson
(`setlist_test.dart:54-59`).

## Hét ön-készítésű legacy fixture

A `test/fixtures/song_trainer/legacy/` könyvtár hét JSON fájlt
tartalmaz. Minden fájl `provenance` mezője rögzíti, hogy a tartalom
ön-készítésű, technikai jellegű, és nincs benne jogvédett
anyag.

| Fixture | Dal / Setlist | Megkülönböztető |
|---|---|---|
| `song_44.json` | 2 bar, 4/4, 96 BPM, `[C, G]`, `d-du-ud-` | 4/4 timeline zárolása |
| `song_34.json` | 2 bar, 3/4, 76 BPM, `[Am, Em]`, `d-u-u-` | 3/4 timeline zárolása (egy 4/4-re hardcode-olt implementáció elbukik) |
| `song_rests.json` | 2 bar, 4/4, 90 BPM, `[F, C]`, `d---u---` (2 stroke/bar) | rest-megőrzés; rest-et eldobó implementáció elbukik |
| `song_multiple_chords.json` | 4 bar, 4/4, 100 BPM, `[C, G, Am, F]`, `d-du-ud-` | 4-különböző akkordú haladás; per-chord beat csoportok zárolva |
| `setlist_duplicate.json` | 1 dal (`song_a`, 100 BPM, 2 bar), setlist `[song_a, song_a]` | duplikáció megőrzése; dedupe implementáció elbukik |
| `setlist_missing_song.json` | 1 dal (`song_a`), setlist `[song_a, ghost, song_a]` | hiányzó id átugrása; throw/drop-egyéb implementáció elbukik |
| `setlist_mixed_bpm.json` | 2 dal (`song_a` 100 BPM + `song_b` 120 BPM), setlist `[song_a, song_b]` | per-song tempo megőrzése warp-pal; közös BPM-re lapító implementáció elbukik |

Minden fixture tartalmazza a `schemaVersion`, `fixture`, `provenance`,
`description`, `song` (vagy `songbook` + `setlist`), és `expected`
mezőket. Az `expected` blokk az alábbi invariánsokat zárolja:

- `events` (lesson event count, rest nélkül)
- `totalBeats` (1e-9 epsilon)
- `durationSec` (1e-9 epsilon, share-timeline hossz)
- `meter` (`beatsPerBar`)
- `chordSequence` (Learn-specifikus collapse)
- `directionSequence` (a legmélyebb invariáns — rest-szűrés + sorrend
  + le/fel)
- `downCount` / `upCount` (share timeline számlálók)
- `chordSummary` (Strum Card szöveg)
- setlisteknél ezen felül: `resolvedOrder`, `unresolvedIds`,
  `beatSequence` (warp-pontosság), és `perSongDurationSec`
  (mixed-bpm esetén)

A fixture-ök `expected` blokkjai a 2026-08-02-es `main@6a45486`
`Song.toLesson` / `Song.toAnalyzeResult` / `Setlist.resolve` /
`Setlist.combine` tényleges kimenetéből készültek
(`tool/_dev_dump.dart` / `flutter test` nyomtatással); a
`legacy_fixture_parity_test.dart` RED → GREEN ciklusában lettek
ellenőrizve, és három mutáció-teszttel (durationSec, warp, rest-szám)
igazolva, hogy a hibás implementációt elkapják.

## Megkülönböztető mátrix (E03-R01 §6, A4)

| Fixture | Kötelező mérés | Hibás implementáció, amit elkap |
|---|---|---|
| `song_44`, `song_34` | totalBeats, durationSec, meter | 4/4-re hardcode-olt timeline |
| `song_rests`, `song_multiple_chords` | event count + sorrend | rest eldobás / első chordra szűkítés |
| `setlist_duplicate`, `setlist_missing_song` | item order + unresolved ID | dedupe / néma elemvesztés |
| `setlist_mixed_bpm` | dalonkénti duration | közös BPM-re lapítás |

A reviewer a fenti mutációk bármelyikével pirosra tudja váltani a
tesztet; a `legacy_fixture_parity_test.dart` mind a hét forgatókönyvhöz
explicit, nem generált, függetlenül ellenőrizhető értékeket tartalmaz
(ld. `_expectSongParity` és `_expectSetlistParity`).

## Jelenlegi tesztek (legacy baseline)

| Könyvtár | Fájlszám | Lefedett terület |
|---|---:|---|
| `test/features/songs/` | 9 | Song modell, Setlist modell, Song Builder widget, Setlist flow, song provider, setlist provider, strum pattern-ek, tap tempo, meter |
| `test/features/learn/setlist_expected_hint_test.dart` | 1 | A kombinált setlist-lesson `expected-chord` hintje a dal-határt követi a tempo-warp ellenére |

Ezek a tesztek E03-R01 nélkül is zöldek, és a kör nem módosítja
őket. Az E03-R01 csak az új
`test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`
fájlt adja a tesztkészlethez.

## Ismert korlátok és öröklött technikai adósságok

1. **Nincs section/measure fogalom.** A legacy modell lapos
   (chord-per-bar), nincs section, measure ismétlés vagy szakasz-jelölő.
   Ezt orvosolja a SongDocument V2 (ADR 0089 §Döntés 1).
2. **Nincs revision / optimistic concurrency.** Két egyidejű
   szerkesztés némán felülírhatja egymást
   (`lib/features/songs/providers/songs_provider.dart`). A
   SongDocument V2 `revision` mezőt és a repository
   `expectedRevision` ellenőrzést vezet be (ADR 0089 §Döntés 3,
   ADR 0090).
3. **Nincs forrás/proveniencia.** A `Song` nem tárolja, hogy a dal
   kézzel lett-e írva vagy importálva. A SongDocument V2
   `SongSource` mezője orvosolja (ADR 0089 §Döntés 4).
4. **Nincs multi-track.** Egy dal = egy chord-per-bar szekvencia. A
   SongDocument V2 `tracks` mezőt vezet be (ADR 0089 §Döntés 1).
5. **Nincs bináris asset.** A `SharedPreferences` nem alkalmas
   bináris (backing audio, artwork) tárolására. A fájlrendszeres
   asset store (ADR 0090) `assets/<sha256>.<ext>` mintát vezet be.
6. **Nincs import határ.** A legacy modellbe nincs beépített módja
   annak, hogy egy MusicXML/MIDI/Guitar Pro fájlból származó dal
   elkülönítse a saját és az import forrást. Az import security
   boundary (ADR 0091) és a `SongSource` (ADR 0089 §Döntés 4)
   együttesen orvosolja.
7. **Nincs SongDocument ↔ Practice Engine mapping.** A Practice
   Engine V2 `SongEventReference.songRevision` mezőt vár, de a
   legacy `Song` nem ad ilyet. A Practice Engine integráció (ADR
   0092) definiálja a V2-irányú adaptert, és kijelöli az E03-R06
   legacy-adapter kört.
8. **A `lib/features/practice/public.dart` nem exportálja a
   compiler/result-mapping teljes contractját.** A
   `PracticeScoreAggregator`/`PracticeVerdict`/`TimingGrade`/
   `ChordOutcome` típusok egyike sincs a public boundary-n
   (`lib/features/practice/public.dart:25-49`). A SongDocument V2
   integráció nem használhat belső Practice importot — a public
   contract bővítése külön kör (E03-R+) feladata. Ez hard
   pre-flight gate.
9. **A `practiceEngineV2Enabled`/`migratedLearnEnabled`/
   `practiceDetailedHistoryEnabled` függőségi szabályok
   ([`docs/adr/0084-history-v2.md`](../adr/0084-history-v2.md))
   nem terjednek ki az új `songTrainerV2Enabled` flagre.** Az
   új flag önálló, nem függ a Practice Engine-től, és a
   Practice Engine-től sem függ. A függőségi irány csak a
   jövőben, a Practice Engine integrációs körben (E03-R+)
   dől el.

## Nem módosítható elemek a körben (E03-R01 §3 "Kívül")

- SongDocument V2 implementáció (`lib/features/song_trainer/`)
- Legacy dal- vagy setlist-rekord migrációja a tárolóban
- UI/navigáció (a Song/Setlist képernyők érintetlenek maradnak)
- A `songTrainerV2Enabled` flag bármilyen bekapcsolása (debug, lab,
  production — egyik sem)
- A `lib/features/practice/public.dart` bármely bővítése belső
  Practice típus importjával

## Hivatkozott ADR-ek (pre-flight, 2026-08-02)

- [ADR 0089](../adr/0089-song-document-v2.md) — SongDocument V2
  domain modell.
- [ADR 0090](../adr/0090-song-storage-files-and-assets.md) —
  Fájlrendszeres Song repository és content-hash asset store.
- [ADR 0091](../adr/0091-song-import-security-boundary.md) — Import
  biztonsági határ (méret, formátum, sandbox, drift).
- [ADR 0092](../adr/0092-song-trainer-practice-engine-integration.md) —
  Practice Engine integráció és `SongEventReference` mapping.
- [ADR 0084](../adr/0084-history-v2.md) — Practice History V2
  (legacy V1-et érintetlenül hagyó párhuzamos tároló); a
  SongDocument V2 storage policy-jának előzménye.
- [ADR 0052](../adr/0052-ci-apk-automerge-session-per-round.md) —
  A körönkénti session + CI zöld-kapu szabály.

A négy új ADR (0089–0092) a pre-flight commitban
(`6c75bca`) jött létre, és a `docs/adr/0089-…0092-…` fájlok
**nem** tartoznak az implementer engedélyezett listájához — a
kör scope-ját kizárólag a feature public boundary, a feature flag és
a baseline dokumentáció jelenti.
