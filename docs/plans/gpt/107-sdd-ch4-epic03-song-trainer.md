---
id: 107
topic: SDD Ch4 / Epic 3 — Song Trainer: 22 kör (SongDocument V2, tempo/meter map, MusicXML/MIDI import, GP feasibility gate, transport, setlist V2)
tags: [sdd, epic3, song-trainer, import, musicxml, midi, transport, migration]
status: active
depends_on: [105, 106]
canonical_target: docs/sdd/04-epic-03-song-trainer.md
verify: legacy Song migráció veszteségmentes + parser fixture-ök zöldek
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# StrumSight Software Design Document

## Chapter 4 — Epic 3: Song Trainer

**Dokumentumverzió:** 1.0  
**Implementációs állapot:** fejlesztésre kész  
**Repository:** `wolfcasaba/strumsight`  
**Előfeltétel:** Chapter 2 — Epic 1 Core Platform & Infrastructure  
**Előfeltétel:** Chapter 3 — Epic 2 Practice Engine  
**Célplatform:** Flutter, Android-first, később iOS  
**Fő képesség:** strukturált dalok importálása, szerkesztése, lejátszása és szakaszonkénti gyakorlása  
**Végrehajtó:** Codex  
**Végrehajtási mód:** körönként, külön branchben, teljes regressziós ellenőrzéssel

---

# 1. Az Epic célja

Az Epic 3 célja egy teljes Song Trainer létrehozása, amely a StrumSight jelenlegi egyszerű Song és Setlist funkcióját professzionális, offline dalgyakorló rendszerré fejleszti.

A felhasználó legyen képes:

- saját dalt létrehozni vagy meglévőt szerkeszteni;
- strukturált dalfájlt importálni;
- a dal hangszer- és sávstruktúráját megtekinteni;
- kiválasztani, hogy akkordot, pengetési mintát vagy egyhangú gitárszólamot gyakorol;
- szakaszt, ütemet vagy egyéni A–B tartományt kijelölni;
- count-innal, metronómmal és opcionális backing trackkel gyakorolni;
- a dalt lassítani vagy gyorsítani;
- a kijelölt részt automatikusan ismételni;
- a Chapter 3 Practice Engine segítségével valós időben pontozást kapni;
- megtekinteni a dalon belüli nehéz részeket és fejlődését;
- setlistet összeállítani és egymás után több dalt lejátszani;
- mindezt alapfunkcióként internetkapcsolat nélkül használni.

A Song Trainer nem egyszerű médialejátszó. A rendszernek a zenei időt, a dalstruktúrát, a célhangokat, az akkordokat, a pengetéseket, a felhasználói teljesítményt és az audiolejátszást egyetlen determinisztikus sessionben kell összehangolnia.

Az Epic végére a StrumSight két szinten tudjon dalokat tanítani:

1. **Chord & Rhythm Trainer:** akkordok, akkordváltások, ritmus és pengetési irány értékelése.
2. **Monophonic Note Trainer:** egyhangú riffek és dallamok hangmagasság-, időzítés- és kitartásértékelése.

A polifonikus tabulatúra teljes, húronkénti automatikus értékelése nem része ennek az Epicnek. A rendszer ilyen szólamot megjeleníthet és lejátszhat, de csak a támogatott mérési képességekről adhat pontszámot.

---

# 2. Termékvízió

A Song Trainer termékígérete:

> Hozd a saját dalodat, válaszd ki a nehéz részt, lassítsd le, ismételd, és a StrumSight megmutatja, hogy ritmusban, akkordban és hangmagasságban hol kell javulnod.

A terméknek a gyakorlás valós problémáit kell megoldania:

- a felhasználó nem akar minden alkalommal manuálisan visszatekerni;
- nem tudja pontosan, melyik ütemnél hibázik rendszeresen;
- lassítva szeretne gyakorolni, de meg akarja tartani a zenei struktúrát;
- egy rövid problémás részt szeretne tízszer egymás után eljátszani;
- szeretné tudni a legmagasabb stabil tempóját;
- külön szeretné gyakorolni a ritmust, az akkordokat vagy a hangokat;
- importált fájlnál érteni szeretné, mit tud és mit nem tud értékelni az alkalmazás;
- nem akarja elveszíteni a saját dalait, fájljait és haladását.

A rendszernek minden importált vagy saját dalhoz egyértelműen meg kell jelenítenie a támogatási szintet:

- **Teljes értékelés:** timing + direction + chord vagy monophonic pitch.
- **Részleges értékelés:** csak a rendelkezésre álló dimenziók értékelhetők.
- **Lejátszás és követés:** a tartalom megjeleníthető, de automatikusan nem értékelhető megbízhatóan.

A felhasználónak soha nem szabad olyan pontszámot kapnia, amelyet az alkalmazás mérési képessége nem támaszt alá.

---

# 3. Kapcsolat a jelenlegi kódbázissal

A repository már rendelkezik működő Songs és Setlists feature-rel. Az Epic 3 ezekre épít, de nem terjeszti tovább a jelenlegi, egyetlen osztályba sűrített Song modellt.

## 3.1 Meglévő, újrahasználandó képességek

A jelenlegi kódbázisban elérhető:

- `Song` modell;
- akkordonként egy bar szerkezet;
- baronként ismétlődő nyolcad-alapú strumming pattern;
- 4/4 és 3/4 meter;
- BPM;
- lokális JSON-perzisztencia;
- Song Builder képernyő;
- akkordmenet-javaslatok;
- strumming pattern presetek;
- `Song.toLesson()` adapter;
- `Song.toAnalyzeResult()` adapter a share pipeline-hoz;
- `Setlist` modell és sorrendezés;
- több dal egy Lesson objektummá kombinálása;
- eltérő daltempók időbeli warpja a jelenlegi Setlist kombinációban;
- Learn képernyős lejátszás és pontozás;
- 3/4 regressziós tesztek;
- perzisztencia race condition tesztek;
- setlist flow tesztek;
- progress és streak integráció a Learn pipeline-on keresztül.

A jelenlegi modell előnye, hogy egyszerű, offline és jól tesztelt. Ezeket a tulajdonságokat a V2 rendszernek meg kell őriznie.

## 3.2 A jelenlegi Song modell korlátai

A jelenlegi `Song` az alábbi adatokat tárolja:

```dart
Song(
  id: String,
  name: String,
  chords: List<String>,
  pattern: List<StrumDirection?>,
  bpm: int,
  beatsPerBar: int,
)
```

Ez az egyszerű gyakorló dalokhoz megfelelő, de teljes Song Trainerhez nem elegendő.

A fő korlátok:

1. Egy barhoz pontosan egy akkord tartozik.
2. A teljes dalban ugyanaz a strumming pattern ismétlődik.
3. A teljes dalban egyetlen BPM használható.
4. A teljes dalban egyetlen meter használható.
5. Nincsenek intro, verse, chorus, bridge vagy solo szakaszok.
6. Nincsenek ismétlési jelek vagy alternatív befejezések.
7. Nincs hangnem-, capo- vagy tuningmetaadat a dal szintjén.
8. Nincsenek note-, fret- vagy string-események.
9. Nincs lyrics vagy rehearsal marker.
10. Nincs backing audio asset.
11. Nincs importforrás és importwarning.
12. Nincs fájlverzió és schema migration a modellen belül.
13. Nincs per-section vagy per-measure progress.
14. Nincs A–B loop vagy bookmark.
15. A Setlist kombináció a nyitó dal meterét használja a teljes vizuális gridhez.
16. A Setlist egyetlen Lesson objektummá lapítja a dalokat, ezért elvesznek a dalhatárok és átmenetek.
17. A Songs és Setlists közvetlenül SharedPreferencesben tárolódik.
18. A provider több storage és state felelősséget kezel egyszerre.
19. A `Song` közvetlenül importál Analyze, Learn és Live belső modelleket.
20. Nincs formátumfüggetlen import- és exportarchitektúra.

## 3.3 A jelenlegi Setlist korlátai

A jelenlegi Setlist csak rendezett song ID-listát tárol.

Nem támogatja:

- a dalonkénti kezdőtempó-felülírást;
- a kiválasztott szakaszt;
- a dalok közötti szünetet;
- külön count-int;
- hangolási emlékeztetőt;
- capo beállítást;
- teljesítmény- vagy gyakorlási módot;
- eltérő track kiválasztást;
- session folytatását;
- dalonkénti eredményt;
- hibás vagy hiányzó assetek részletes kezelését.

## 3.4 Migrációs alapelv

A régi Song és Setlist adatok nem veszhetnek el.

Kötelező migrációs út:

```text
Legacy Song V1
      |
      | deterministic adapter
      v
SongDocument V2
      |
      | optional persisted migration
      v
Song Repository V2
```

A migráció első verziójában:

- minden régi chord egy teljes measure-t tölt ki;
- a régi pattern minden measure-ben ismétlődik;
- a BPM egyetlen tempo map eseménnyé válik a dal elején;
- a beatsPerBar egyetlen meter map eseménnyé válik a dal elején;
- a dal egyetlen, automatikusan létrehozott sectiont kap;
- a source típusa `legacyLocal`;
- a migráció megőrzi az eredeti legacy ID-t;
- a migráció idempotens;
- a régi rekord csak sikeres V2 írás és visszaolvasási ellenőrzés után törölhető;
- feature flag alatt a V1 és V2 olvasás ideiglenesen együtt működhet.

A régi Song képernyő addig nem távolítható el, amíg:

- minden legacy fixture migrációs tesztje zöld;
- a dalok száma és ID-ja egyezik;
- a `toLesson()` viselkedéshez parity teszt készült;
- a 3/4 viselkedés megmaradt;
- a visszaállítási terv dokumentált.

---

# 4. Az Epic hatóköre

## 4.1 Az Epic része

- SongDocument V2 domain;
- verziózott dalmetaadat;
- section- és measure-struktúra;
- tempo map;
- meter map;
- key signature és transposition metaadat;
- track- és eventmodell;
- chord track;
- strum track;
- monophonic note/tab track;
- lyrics és marker track megjelenítési alapszinten;
- backing audio asset referencia;
- legacy Song és Setlist migráció;
- fájlalapú lokális Song repository;
- atomikus asset store;
- natív StrumSight JSON import és export;
- MusicXML és tömörített MXL import;
- Standard MIDI File import;
- Guitar Pro importálhatósági és licencelési feasibility gate;
- jóváhagyott megoldás esetén Guitar Pro adapter;
- importpreview és warning rendszer;
- Song Library V2;
- keresés, szűrés és rendezés;
- Song Editor V2;
- track kiválasztás;
- Song Trainer setup;
- determinisztikus transport state machine;
- count-in, metronóm, seek, pause és resume;
- measure-, section- és A–B loop;
- speed control;
- opcionális backing track playback;
- backing track driftkorrekció;
- capo, transposition és tuning kezelés;
- Chapter 3 Practice Engine adapter;
- chord/rhythm song scoring;
- monophonic pitch scoring;
- section- és measure-szintű eredmények;
- resume point és bookmark;
- Setlist V2;
- performance és practice setlist mode;
- progress, streak és daily goal integráció;
- offline működés;
- accessibility és localization;
- unit, property, parser fixture, widget, integration és eszköztesztek.

## 4.2 Az Epic nem tartalmazza

- licencelt kereskedelmi dalkatalógust;
- zenei streaming szolgáltatás integrációját;
- YouTube-, Spotify- vagy más szolgáltatásból történő hangletöltést;
- DRM megkerülését;
- automatikus, felhőalapú dalbeszerzést;
- nyers hangból teljes tabulatúra automatikus generálását;
- polifonikus, húronkénti note scoringot;
- akkordon belüli minden húr külön értékelését;
- stem separationt;
- énekértékelést;
- teljes DAW-szerkesztést;
- professzionális kotta- és tabulatúra-tördelő motort;
- digitális jogkezelést vagy marketplace-et;
- dalok automatikus nyilvános megosztását;
- szerzői joggal védett importált fájlok felhőbe feltöltését;
- AI Guitar Teacher magyarázatait;
- computer vision kéztartás-elemzést.

Az architektúra készítsen tiszta bővítési pontot a későbbi funkciókhoz, de ne hozzon létre használaton kívüli absztrakciókat.

---

# 5. Felhasználói utak

## 5.1 Régi saját dal megnyitása

1. Az alkalmazás felismeri a legacy Song rekordot.
2. A rendszer memóriában V2 SongDocumentté alakítja.
3. A felhasználó ugyanazt a nevet, akkordokat, pattern-t, BPM-et és metert látja.
4. A dal lejátszható a Song Trainerben.
5. Első sikeres szerkesztés vagy explicit migráció után V2 formátumban tárolódik.
6. Hiba esetén az eredeti legacy rekord megmarad.

## 5.2 Strukturált dal importálása

1. A felhasználó megnyomja az `Import song` gombot.
2. A rendszer fájlválasztót nyit.
3. A kiválasztott fájlt először probe-olja, de még nem írja a librarybe.
4. Megjelenik az importpreview:
   - formátum;
   - cím;
   - szerző, ha elérhető;
   - sávok;
   - tuning;
   - tempo- és meterinformáció;
   - támogatott trainer módok;
   - warningok;
   - nem támogatott elemek.
5. A felhasználó kiválasztja a gitársávot és az importbeállításokat.
6. A rendszer izolált temporary könyvtárban parse-ol és validál.
7. Sikeres validáció után atomikusan menti a dalt és asseteket.
8. A Song Overview képernyő nyílik meg.

## 5.3 Egy chorus gyakorlása

1. A felhasználó megnyit egy dalt.
2. A section listából kiválasztja a Chorus részt.
3. Beállítja a 80%-os sebességet.
4. Bekapcsolja a két ütem count-int.
5. Beállítja, hogy a section ötször ismétlődjön.
6. A Song Trainer elindítja a Practice Engine sessiont.
7. Minden loop végén rövid, nem blokkoló eredmény jelenik meg.
8. A rendszer csak akkor emel tempót, ha a Speed Builder policy teljesül.
9. A session végén a felhasználó measure-szintű heatmapet kap.

## 5.4 Monophonic riff gyakorlása

1. A felhasználó egy importált tab- vagy MIDI-sávot választ.
2. A rendszer jelzi, hogy a szólam monophonic note scoringra alkalmas-e.
3. A count-in után a célhangok a playhead felé haladnak.
4. A pitch gateway YIN-alapú hangmagasság-megfigyeléseket ad.
5. A matcher külön méri:
   - pitch pontosság;
   - onset timing;
   - kitartás;
   - extra hang;
   - kihagyott hang.
6. Akkord vagy többhangú esemény esetén az app nem ad hamis note score-t, hanem playback-only állapotot jelez.

## 5.5 Backing trackkel gyakorlás

1. A felhasználó helyi audiofájlt kapcsol a dalhoz.
2. Beállítja a zenei grid és az audio közötti kezdeti offsetet.
3. A rendszer preview clickkel vagy markerrel segíti a kalibrációt.
4. Lejátszáskor a backing audio és a SongTransport közös időalapra szinkronizál.
5. Kisebb driftet fokozatos korrekció kezel.
6. Nagy drift vagy seek hiba esetén kontrollált resync történik.
7. Ha az audio backend nem biztosít pitch-preserving rate controlt, a UI ezt egyértelműen jelzi, és nem ígér minőségromlás nélküli lassítást.

## 5.6 Setlist gyakorlása

1. A felhasználó létrehoz egy Setlist V2-t.
2. Minden elemhez megadhat:
   - teljes dal vagy section;
   - tempófelülírás;
   - loop count;
   - count-in;
   - capo;
   - tuning reminder;
   - trainer mode.
3. Practice módban minden dal után eredmény és újrapróbálási lehetőség jelenik meg.
4. Performance módban a dalok megszakítás nélkül, minimális kezelőfelülettel követik egymást.
5. Minden dal külön progress rekordot kap.

---

# 6. Funkcionális követelmények

## 6.1 Dal létrehozása és szerkesztése

A felhasználó tudjon:

- címet megadni;
- előadót és albumot opcionálisan megadni;
- hangnemet megadni;
- default tuningot megadni;
- capo pozíciót megadni;
- sectionöket létrehozni és rendezni;
- measure-öket hozzáadni, másolni és törölni;
- measure-en belül több akkordot elhelyezni;
- measure-enként eltérő strumming pattern-t használni;
- tempo- és meter változást felvenni;
- rehearsal markert hozzáadni;
- tracket létrehozni és kiválasztani;
- note/tab eseményt szerkeszteni az első verzióban legalább alapértékekkel;
- backing audiofájlt kapcsolni;
- a változtatásokat validáció előtt preview-zni;
- unsaved change figyelmeztetést kapni.

## 6.2 Import

Az importfolyamatnak:

- offline kell működnie;
- nem szabad a fájlt hálózatra küldenie;
- a forrásfájlt limitált mérettel kell kezelnie;
- az archívumokat zip bomb ellen védenie kell;
- a parse hibákat felhasználóbarát warninggá kell alakítania;
- meg kell őriznie a forrásfájl hashét;
- duplikált importot fel kell ismernie;
- részleges támogatás esetén capability reportot kell adnia;
- hibás import után nem hagyhat félkész library rekordot;
- import közben megszakíthatónak kell lennie;
- nagyobb parse munkát isolate-ban vagy natív workerben kell végeznie.

## 6.3 Song Library

A library támogassa:

- dalok listázását;
- keresést cím, előadó és tag alapján;
- rendezést név, módosítás, utolsó gyakorlás és nehézség szerint;
- szűrést source type, capability és tuning alapján;
- favorite jelölést;
- archiválást;
- duplikálást;
- exportot;
- törlést undo lehetőséggel;
- hiányzó asset jelzését;
- importwarning megtekintését;
- legutóbbi practice resume-ot.

## 6.4 Song Overview

A képernyő mutassa:

- cím;
- előadó;
- duration;
- base tempo vagy tempo range;
- meter vagy meter changes;
- key;
- tuning;
- capo;
- source;
- trackek;
- sectionök;
- támogatott trainer módok;
- importwarningok;
- utolsó gyakorlás;
- best score;
- highest stable speed;
- Start, Edit, Export és Setlist műveletek.

## 6.5 Trainer setup

Indítás előtt beállítható:

- track;
- full song, section, measure range vagy A–B loop;
- trainer mode;
- speed;
- count-in;
- metronóm;
- backing track hangerő;
- click hangerő;
- loop count;
- automatic retry;
- Speed Builder;
- transposition;
- capo;
- scoring dimensions;
- left-handed visual mode;
- feedback intensity.

## 6.6 Lejátszás és navigáció

A trainer támogassa:

- prepare;
- count-in;
- play;
- pause;
- resume;
- restart;
- seek measure-re;
- seek sectionre;
- next és previous marker;
- loop range;
- loop count;
- speed change csak biztonságos állapotban;
- metronome on/off;
- backing track mute;
- finish;
- cancel;
- app lifecycle interruption;
- audio route change kezelését.

## 6.7 Pontozás

A Song Trainer nem készít saját, párhuzamos scoring rendszert a Chapter 3 mellé.

A következő dimenziókat a Practice Engineből használja:

- timing;
- rhythm;
- strum direction;
- chord correctness;
- combo;
- section result;
- loop result;
- coaching insight.

Az Epic 3 új, monophonic note scoring adaptert ad:

- note pitch;
- cents deviation;
- note onset;
- note duration coverage;
- missed note;
- extra note;
- unstable pitch;
- unsupported polyphony.

## 6.8 Eredmények

A session után jelenjen meg:

- overall score;
- trainer mode szerinti dimenziók;
- section score;
- measure heatmap;
- problem measures;
- early/late bias;
- chord confusion;
- wrong direction helyek;
- pitch error helyek;
- highest stable speed;
- completed loops;
- practice duration;
- Retry problem section;
- Slow down;
- Add to practice set;
- Continue next section;
- Finish.

---

# 7. Támogatási és capability modell

A Song Trainernek explicit módon kell kezelnie, hogy egy dal vagy track milyen funkciókra alkalmas.

## 7.1 SongCapability

```dart
abstract final class SongCapability {
  static const chordDisplay = 'chord_display';
  static const strumDisplay = 'strum_display';
  static const noteDisplay = 'note_display';
  static const tabDisplay = 'tab_display';
  static const lyricsDisplay = 'lyrics_display';
  static const chordScoring = 'chord_scoring';
  static const directionScoring = 'direction_scoring';
  static const rhythmScoring = 'rhythm_scoring';
  static const monophonicPitchScoring = 'monophonic_pitch_scoring';
  static const backingPlayback = 'backing_playback';
  static const speedControl = 'speed_control';
}
```

A tényleges implementáció használhat enumot vagy value objectet, de a capability azonosítóknak stabilnak kell maradniuk a perzisztenciában.

## 7.2 Capability report

Minden SongDocumenthez és trackhez készüljön:

```dart
final class CapabilityReport {
  const CapabilityReport({
    required this.supported,
    required this.partiallySupported,
    required this.unsupported,
    required this.warnings,
  });

  final Set<SongCapabilityId> supported;
  final Set<SongCapabilityId> partiallySupported;
  final Set<SongCapabilityId> unsupported;
  final List<SongImportWarning> warnings;
}
```

## 7.3 Trainer mód elérhetősége

- Chord Trainer csak chord esemény esetén engedélyezhető.
- Strum Direction Trainer csak direction target esetén engedélyezhető.
- Rhythm Trainer note onsetből vagy strum targetből is készülhet.
- Monophonic Note Trainer csak ellenőrzött monophonic track esetén engedélyezhető.
- Polyphonic track megjeleníthető, de pitch score nem engedélyezhető.
- Backing playback csak érvényes lokális asset esetén engedélyezhető.
- Speed control csak akkor jelenjen meg backing audio mellett, ha a playback adapter támogatja a kért működést.

## 7.4 Őszinte korlátozás

A UI-ban egyértelműen különüljön el:

```text
Can display
Can play
Can score
```

Az alkalmazás nem használhat általános `Supported` címkét olyan tartalomra, amely csak megjeleníthető, de nem pontozható.

---

# 8. Célarchitektúra

## 8.1 Feature struktúra

```text
lib/features/song_trainer/
├── domain/
│   ├── models/
│   │   ├── song_document.dart
│   │   ├── song_metadata.dart
│   │   ├── song_source.dart
│   │   ├── song_section.dart
│   │   ├── song_measure.dart
│   │   ├── song_track.dart
│   │   ├── song_event.dart
│   │   ├── tempo_map.dart
│   │   ├── meter_map.dart
│   │   ├── key_map.dart
│   │   ├── tuning.dart
│   │   ├── asset_reference.dart
│   │   ├── song_capability.dart
│   │   ├── import_warning.dart
│   │   ├── trainer_range.dart
│   │   └── trainer_config.dart
│   ├── repositories/
│   │   ├── song_repository.dart
│   │   ├── song_asset_repository.dart
│   │   ├── song_progress_repository.dart
│   │   └── setlist_repository.dart
│   ├── services/
│   │   ├── song_validator.dart
│   │   ├── song_normalizer.dart
│   │   ├── song_capability_resolver.dart
│   │   ├── song_time_map.dart
│   │   ├── song_practice_compiler.dart
│   │   └── note_track_analyzer.dart
│   └── public.dart
│
├── application/
│   ├── library/
│   │   ├── song_library_controller.dart
│   │   ├── song_library_state.dart
│   │   └── song_query.dart
│   ├── import/
│   │   ├── song_import_controller.dart
│   │   ├── song_import_state.dart
│   │   ├── import_song_use_case.dart
│   │   └── import_preview.dart
│   ├── editor/
│   │   ├── song_editor_controller.dart
│   │   ├── song_editor_state.dart
│   │   └── editor_command.dart
│   ├── trainer/
│   │   ├── song_trainer_controller.dart
│   │   ├── song_trainer_state.dart
│   │   ├── song_transport.dart
│   │   ├── song_transport_clock.dart
│   │   └── transport_effect.dart
│   ├── setlists/
│   │   ├── setlist_controller.dart
│   │   └── setlist_session_controller.dart
│   └── providers/
│
├── data/
│   ├── local/
│   │   ├── file_song_repository.dart
│   │   ├── file_song_asset_repository.dart
│   │   ├── song_index_codec.dart
│   │   ├── song_document_codec.dart
│   │   └── atomic_file_writer.dart
│   ├── importers/
│   │   ├── song_importer.dart
│   │   ├── importer_registry.dart
│   │   ├── native_json_importer.dart
│   │   ├── musicxml_importer.dart
│   │   ├── mxl_importer.dart
│   │   ├── midi_importer.dart
│   │   └── guitar_pro_importer.dart
│   ├── playback/
│   │   ├── backing_audio_player.dart
│   │   ├── local_backing_audio_player.dart
│   │   └── playback_capabilities.dart
│   └── migration/
│       ├── legacy_song_reader.dart
│       ├── legacy_song_adapter.dart
│       └── legacy_setlist_adapter.dart
│
├── presentation/
│   ├── screens/
│   │   ├── song_library_screen.dart
│   │   ├── song_overview_screen.dart
│   │   ├── song_import_screen.dart
│   │   ├── song_import_preview_screen.dart
│   │   ├── song_editor_screen.dart
│   │   ├── trainer_setup_screen.dart
│   │   ├── song_trainer_screen.dart
│   │   ├── song_result_screen.dart
│   │   ├── setlist_list_screen_v2.dart
│   │   └── setlist_session_screen.dart
│   └── widgets/
│       ├── song_section_list.dart
│       ├── song_track_picker.dart
│       ├── measure_grid.dart
│       ├── chord_lane.dart
│       ├── strum_lane.dart
│       ├── note_lane.dart
│       ├── tablature_lane.dart
│       ├── transport_controls.dart
│       ├── loop_controls.dart
│       ├── measure_heatmap.dart
│       └── import_warning_list.dart
│
└── public.dart
```

## 8.2 Függőségi irány

```text
Presentation
     ↓
Application
     ↓
Domain
     ↑
Data implementations
```

A Song Trainer domain nem importálhat:

- Flutter widgetet;
- Riverpodot;
- SharedPreferences-t;
- platform file pickert;
- konkrét audio playback package-et;
- XML vagy MIDI parser package-et;
- Practice Engine presentation fájlt.

A Practice Engine integráció domain- vagy application-szintű publikus kontraktuson keresztül történjen.

## 8.3 Kereszt-feature szabály

A Song Trainer használhatja:

- Chapter 2 core storage, logging, failure, audio lifecycle és clock API-kat;
- Chapter 3 Practice Engine `public.dart` API-ját;
- közös music és audio modelleket;
- Tunerből kiemelt, core audio alá migrált pitch observation API-t.

Nem importálhat közvetlenül:

- `features/learn/screens`;
- `features/live/providers`;
- `features/tuner/providers`;
- `features/analyze/screens`;
- más feature belső data vagy presentation fájljait.

## 8.4 Feature flag

A migráció alatt használható:

```dart
featureFlags.songTrainerV2Enabled
```

A flag kizárólag rollout célra szolgál. Nem hozhat létre tartósan két külön domain modellt vagy két külön progress rendszert.

---

# 9. SongDocument V2

## 9.1 Alapmodell

```dart
final class SongDocument {
  const SongDocument({
    required this.schemaVersion,
    required this.id,
    required this.revision,
    required this.metadata,
    required this.source,
    required this.sections,
    required this.measures,
    required this.tracks,
    required this.tempoMap,
    required this.meterMap,
    required this.keyMap,
    required this.assets,
    required this.markers,
    required this.createdAt,
    required this.updatedAt,
  });

  final int schemaVersion;
  final SongId id;
  final int revision;
  final SongMetadata metadata;
  final SongSource source;
  final List<SongSection> sections;
  final List<SongMeasure> measures;
  final List<SongTrack> tracks;
  final TempoMap tempoMap;
  final MeterMap meterMap;
  final KeyMap keyMap;
  final List<SongAssetReference> assets;
  final List<SongMarker> markers;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

A konkrét implementáció használhat immutable code generationt, ha az Epic 1 coding standard ezt engedélyezi. Az elsődleges követelmény a determinisztikus equality, copy és serialization.

## 9.2 SongId és revision

A Song ID:

- stabil;
- lokálisan generálható;
- fájlnévben biztonságosan használható;
- nem függhet `DateTime.now()` önmagában történő használatától;
- importált fájl újraimportálásakor nem keverendő össze automatikusan a forráshashsel.

A revision minden sikeres módosításkor növekszik.

A repository optimistic write esetén ellenőrizheti a várt revisiont, hogy két egymással versenyző editor save ne írja felül némán egymást.

## 9.3 SongMetadata

Legalább:

```dart
final class SongMetadata {
  const SongMetadata({
    required this.title,
    this.artist,
    this.album,
    this.composer,
    this.copyright,
    this.tags = const {},
    this.notes,
    this.defaultTuning,
    this.defaultCapo = 0,
    this.originalKey,
    this.artworkAssetId,
  });
}
```

Validáció:

- title nem lehet üres;
- title normalizált hossza limitált;
- capo 0 és a támogatott maximum között legyen;
- tuning húrszáma pozitív;
- tag trimelt, case-normalizált és limitált számú legyen;
- copyright mező nem használható a fájl jogállásának automatikus igazolására.

## 9.4 SongSource

```dart
enum SongSourceType {
  legacyLocal,
  createdInApp,
  strumSightJson,
  musicXml,
  compressedMusicXml,
  midi,
  guitarPro,
}
```

A source tárolja:

- típust;
- eredeti fájlnevet;
- SHA-256 hash-t;
- import időpontját;
- importer verzióját;
- opcionális formátumverziót;
- warningok összegzését;
- eredeti fájl asset referenciáját, ha a felhasználó a megőrzést választotta.

## 9.5 Sectionök

```dart
final class SongSection {
  const SongSection({
    required this.id,
    required this.name,
    required this.startMeasure,
    required this.endMeasureExclusive,
    this.kind = SongSectionKind.custom,
    this.colorKey,
  });
}
```

Támogatott kind:

- intro;
- verse;
- preChorus;
- chorus;
- bridge;
- solo;
- breakdown;
- outro;
- custom.

Szabályok:

- section measure-határokhoz igazodik;
- range nem lehet üres;
- range nem léphet ki a dalból;
- sectionök átfedhetnek, de az editor alapértelmezésben nem hoz létre átfedést;
- az importált rehearsal markerekből section készülhet;
- hiányzó section esetén a rendszer automatikus `Full song` sectiont biztosít.

## 9.6 Measure

```dart
final class SongMeasure {
  const SongMeasure({
    required this.index,
    required this.durationBeats,
    this.displayNumber,
    this.pickup = false,
    this.repeatStart = false,
    this.repeatEndCount,
    this.alternateEnding,
  });
}
```

A measure duration a meter mapből származhat, de pickup vagy csonka measure esetén explicit rövidebb lehet.

A normalizált SongDocument lejátszási timeline-ja ne tartalmazzon végtelen vagy ciklikus repeat szerkezetet. Az importer a repeat jelöléseket limitált, lineáris playback sequence-szé bontsa, vagy warninggal playback-only állapotot adjon.

---

# 10. Zenei időmodell

Az Epic 3 a Chapter 3 `BeatPosition`, `Tempo` és `Meter` értékobjektumaira épít.

## 10.1 Alapelv

Minden strukturált esemény zenei beat positionben tárolódik.

A másodpercérték származtatott adat:

```text
BeatPosition + TempoMap → SongTime
```

Nem megengedett a teljes dal eseményeinek végleges, lebegőpontos másodpercértékben történő tárolása.

## 10.2 Tempo map

```dart
final class TempoChange {
  const TempoChange({
    required this.at,
    required this.bpm,
  });

  final BeatPosition at;
  final Tempo bpm;
}
```

Szabályok:

- az első tempo change kötelezően beat 0-n van;
- BPM pozitív és konfigurált tartományon belüli;
- azonos positionben legfeljebb egy normalizált tempo event maradhat;
- a map position szerint rendezett;
- importer warningot ad irreális vagy hibás tempóra;
- gradual tempo change az első verzióban diszkrét pontokra mintavételezhető dokumentált felbontással.

## 10.3 Meter map

```dart
final class MeterChange {
  const MeterChange({
    required this.atMeasure,
    required this.meter,
  });
}
```

A meter change measure-határon történik.

Első támogatott meterek legalább:

- 2/4;
- 3/4;
- 4/4;
- 6/8.

Más meter importálható, ha a Chapter 3 Meter value object validálni tudja. A UI-nak nem szabad 4/4-re kényszerítenie a tartalmat.

## 10.4 SongTimeMap

```dart
abstract interface class SongTimeMap {
  Duration timeAt(BeatPosition position);
  BeatPosition positionAt(Duration time);
  Duration durationBetween(BeatPosition start, BeatPosition end);
}
```

Követelmények:

- determinisztikus;
- monoton;
- tempo change környezetében invertálható;
- a round-trip tolerancia tesztelt;
- nem allokál nagy objektumlistát frame-enként;
- cache-elhető;
- speed multiplier külön paraméter, nem írja át a SongDocumentet.

## 10.5 Playback speed

A trainer speed:

```text
playback BPM = score BPM × speed multiplier
```

A SongDocument eredeti tempo mapje változatlan marad.

A session config tárolja a speed multipliert. A progress rekord tárolja a tényleges, skálázott BPM-et vagy tempótartományt.

## 10.6 Seek és loop határok

Seek és loop alapértelmezésben a következő pontokra snapelhet:

- measure boundary;
- beat boundary;
- section boundary;
- marker;
- note vagy strum target.

A pontos A–B loop fractional beat positiont is használhat.

A loop start nem lehet kisebb 0-nál, az endnek pedig nagyobbnak kell lennie a startnál.

---

# 11. Track- és eventmodell

## 11.1 SongTrack

```dart
sealed class SongTrack {
  const SongTrack({
    required this.id,
    required this.name,
    required this.instrument,
    required this.enabled,
  });

  final SongTrackId id;
  final String name;
  final SongInstrument instrument;
  final bool enabled;
}
```

Típusok:

- ChordTrack;
- StrumTrack;
- NoteTrack;
- LyricsTrack;
- MarkerTrack;
- BackingAudioTrack.

A chord és strum track lehet külön vagy egy import adapterből származó kapcsolt track.

## 11.2 ChordEvent

```dart
final class SongChordEvent {
  const SongChordEvent({
    required this.id,
    required this.start,
    required this.duration,
    required this.symbol,
    this.displayText,
  });
}
```

Követelmények:

- start nem negatív;
- duration pozitív;
- chord symbol normalizált;
- unsupported chord megőrizheti az eredeti display textet;
- az értékeléshez a chord symbolt a közös chord dictionary támogatott alakjára kell mapelni;
- ha a megjelenítés lehetséges, de scoring mapping nincs, capability warning szükséges.

## 11.3 StrumEvent

```dart
final class SongStrumEvent {
  const SongStrumEvent({
    required this.id,
    required this.at,
    required this.direction,
    this.accent = false,
    this.muted = false,
    this.targetChordId,
  });
}
```

A direction lehet:

- down;
- up;
- unknown.

Az `unknown` megjeleníthető és rhythm-scoringra használható, de direction scoringra nem.

## 11.4 NoteEvent

```dart
final class SongNoteEvent {
  const SongNoteEvent({
    required this.id,
    required this.start,
    required this.duration,
    required this.midiPitch,
    this.velocity,
    this.stringIndex,
    this.fret,
    this.tieGroupId,
    this.techniques = const {},
  });
}
```

Validáció:

- MIDI pitch 0–127;
- duration pozitív;
- stringIndex és fret vagy együtt érvényes, vagy mindkettő null;
- fret nem negatív;
- tie csoport konzisztens;
- technique adat nem befolyásolja automatikusan a scoringot, ha nincs hozzá mérési képesség.

## 11.5 Monophonic track

Egy track akkor minősül monophonic scoringra alkalmasnak, ha a normalizált playback timeline-on nincs egymást átfedő, külön pitchű aktív note event a scoring tartományban.

A `NoteTrackAnalyzer` adja vissza:

```dart
final class NoteTrackAnalysis {
  const NoteTrackAnalysis({
    required this.isMonophonic,
    required this.overlapCount,
    required this.lowestPitch,
    required this.highestPitch,
    required this.noteCount,
    required this.warnings,
  });
}
```

Azonos pitchű tie vagy legato szakasz normalizálható egy hosszabb célhanggá.

## 11.6 Lyrics és markers

Lyrics és marker események az első verzióban megjelenítési és navigációs célúak.

A lyrics:

- nem pontozható;
- nem kerülhet automatikusan publikus share artifactba;
- importált szövege szerzői jogi tartalom lehet;
- export csak explicit felhasználói művelettel történhet.

## 11.7 BackingAudioTrack

A backing track nem tárol közvetlen fájlútvonalat a domainben.

```dart
final class BackingAudioTrack extends SongTrack {
  const BackingAudioTrack({
    required super.id,
    required super.name,
    required super.instrument,
    required super.enabled,
    required this.assetId,
    required this.gridOffset,
    this.gainDb = 0,
  });

  final SongAssetId assetId;
  final Duration gridOffset;
  final double gainDb;
}
```

A repository oldja fel az assetet platformfájllá.

---

# 12. Validáció és normalizálás

## 12.1 SongValidator

A validator tiszta domain service legyen.

```dart
abstract interface class SongValidator {
  SongValidationReport validate(SongDocument document);
}
```

A report tartalmazzon:

- errorokat;
- warningokat;
- info üzeneteket;
- érintett entity ID-t;
- zenei positiont;
- stabil error code-ot;
- javíthatósági jelzőt.

## 12.2 Kötelező errorok

A dokumentum nem menthető vagy nem indítható trainerben, ha:

- nincs title;
- nincs measure;
- nincs tempo event beat 0-n;
- nincs meter event az első measure-re;
- a tempo map nem rendezett vagy nem validálható;
- measure duration nem pozitív;
- event kilép a dal végéből;
- event ID duplikált;
- track ID duplikált;
- section range hibás;
- asset referencia nem létező kötelező assetre mutat;
- note pitch érvénytelen;
- loop range érvénytelen;
- schema version újabb, mint amit az alkalmazás biztonságosan olvasni tud.

## 12.3 Warningok

Warning példák:

- unsupported chord symbol;
- chord megjeleníthető, de nem pontozható;
- polyphonic note track;
- túl sűrű note események;
- ismeretlen technique;
- túl magas vagy alacsony gitárhang;
- hiányzó fret/string információ;
- backing audio offset nincs kalibrálva;
- importált repeat egyszerűsítve lett;
- alternate ending nem teljesen támogatott;
- lyrics elérhető, de nem pontozható;
- source asset nincs megőrizve;
- tempo map túl sok eseményt tartalmaz;
- meter ritka vagy a vizuális lane korlátozott.

## 12.4 SongNormalizer

A normalizer feladata:

- rendezni a mapeket és eventeket;
- normalizálni a chord symbolokat;
- generálni a hiányzó stabil entity ID-kat;
- összevonni az egymást követő azonos tempo eventeket;
- összevonni az azonos, folyamatos tied note-okat;
- levágni a dokumentált tolerancián belüli lebegőpontos importhibát;
- létrehozni a Full song sectiont;
- kiszámítani a capability report alapját;
- nem módosítani olyan tartalmat, amelynek zenei jelentése bizonytalan.

A normalizer minden automatikus változtatást reportoljon.

## 12.5 Idempotencia

```text
normalize(normalize(song)) == normalize(song)
```

Ez kötelező property teszt.

## 12.6 Validációs szintek

- `importPreview`: részleges dokumentum is megjeleníthető warningokkal.
- `persist`: minden strukturális error megszüntetendő.
- `trainer`: a kiválasztott trackhez és range-hez szükséges capabilityk ellenőrzendők.
- `export`: a célformátum vesztesége külön reportolandó.

---

# 13. Importarchitektúra

## 13.1 SongImporter kontraktus

```dart
abstract interface class SongImporter {
  Set<String> get supportedExtensions;

  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  );

  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  );
}
```

A `probe`:

- kevés adatot olvas;
- nem ír tartós fájlt;
- megállapítja a formátumot;
- alapmetaadatot ad;
- becsüli a trackeket és capabilityket;
- jelezheti, hogy teljes parse szükséges.

Az `import`:

- temporary workspace-ben dolgozik;
- validál;
- normalizál;
- capability reportot készít;
- csak siker után ad át persistálható dokumentumot.

## 13.2 ImporterRegistry

```dart
abstract interface class ImporterRegistry {
  SongImporter? importerFor(ImportSourceFile source);
  List<SongImporter> get importers;
}
```

A formátum felismerése ne csak extension alapján történjen. Használható:

- magic byte;
- MIME type;
- XML root;
- ZIP tartalom;
- MIDI header;
- formátumspecifikus header.

Az extension és a tartalom eltérése warning vagy failure legyen.

## 13.3 ImportSourceFile

A file picker által visszaadott platformobjektum ne kerüljön a domainbe.

Az application réteg kapjon:

```dart
final class ImportSourceFile {
  const ImportSourceFile({
    required this.displayName,
    required this.byteLength,
    required this.openRead,
    this.mimeType,
  });
}
```

Nagy fájlt nem szabad automatikusan teljes byte arrayként memóriába tölteni.

## 13.4 Cancellation

Import közben a felhasználó megszakíthatja a műveletet.

A cancellation után:

- parser álljon le a következő biztonságos ponton;
- isolate vagy worker záródjon le;
- temporary file törlődjön;
- nincs library rekord;
- nincs asset reference leak;
- a UI visszatérhet az import képernyőre.

## 13.5 Import warning modell

```dart
final class SongImportWarning {
  const SongImportWarning({
    required this.code,
    required this.severity,
    required this.messageKey,
    this.position,
    this.trackId,
    this.sourceDetail,
  });
}
```

A `sourceDetail` debug vagy részletes importreport céljára használható. Nem lehet lokalizált, kész UI mondat a domainben.

## 13.6 Méret- és erőforráskorlátok

Konfigurálható biztonsági limit szükséges legalább:

- source file byte size;
- archive compressed size;
- archive extracted size;
- archive entry count;
- XML node vagy event count;
- MIDI track count;
- note count;
- measure count;
- lyrics character count;
- artwork size;
- importer wall time;
- temporary workspace size.

A limit túllépése kontrollált `ImportLimitFailure` legyen.

---

# 14. Natív StrumSight JSON formátum

## 14.1 Cél

A natív formátum legyen a SongDocument V2 teljes hűségű import- és exportformátuma.

## 14.2 Fájlkiterjesztés

Javasolt:

```text
.strumsight-song.json
```

vagy csomagolt assetekkel:

```text
.strumsight-song
```

A kezdeti implementáció egyszerű JSON-t támogasson. A backing audio külön fájl maradhat. Csomagolt formátum csak akkor kerüljön be, ha az asset manifest és zip-biztonság teljesen elkészült.

## 14.3 Kötelező root mezők

```json
{
  "format": "strumsight-song",
  "formatVersion": 2,
  "document": {},
  "assetManifest": []
}
```

## 14.4 Round-trip

A natív export-import round-tripnek meg kell őriznie:

- minden domain mezőt;
- entity ID-kat;
- source historyt a privacy szabályok figyelembevételével;
- capabilityreleváns adatokat;
- unknown forward-compatible extension adatokat, ha a codec ezt támogatja.

## 14.5 Determinizmus

Az exportált JSON:

- stabil kulcssorrendet használjon, ha a codec támogatja;
- stabil event sorrendet használjon;
- ugyanabból a dokumentumból azonos tartalmi hash-t eredményezzen;
- ne tartalmazzon véletlenszerű, exportidőben generált mezőt a tartalmi részben;
- pretty print csak exportopció legyen.

## 14.6 Export privacy

Alapértelmezésben ne kerüljön exportba:

- belső abszolút fájlútvonal;
- eszközazonosító;
- auth token;
- teljes practice history;
- felhasználói e-mail;
- diagnosztikai adat;
- import temporary path.

---

# 15. MusicXML és MXL import

## 15.1 Támogatási cél

Az első verzió legalább az alábbi elemeket importálja:

- work vagy movement title;
- creator/artist/composer metaadat;
- part lista;
- measures;
- divisions;
- time signature;
- key signature;
- tempo/metronome jelzés;
- harmony/chord symbol;
- pitched note;
- rest;
- duration;
- tie;
- voice;
- staff;
- rehearsal mark;
- lyrics alapmegjelenítés;
- repeat start/end korlátozottan;
- fret és string technical jelzés, ha elérhető.

## 15.2 Nem támogatott vagy részleges elemek

Warninggal kezelendő többek között:

- komplex ornamentika;
- bends részletes görbéje;
- grace note scoring;
- tuplets, ha a Chapter 3 BeatPosition nem tudja pontosan reprezentálni;
- nested repeats;
- D.C., D.S., Coda komplex navigáció;
- ossia;
- cross-staff notation;
- több voice egyetlen monophonic trainer trackké lapítása;
- nem gitárhangszer-specifikus technikák;
- mikrotonális hangok;
- beágyazott audio.

A parser az ismeretlen elemet ne tekintse automatikusan fatal hibának, ha a zenei timeline biztonságosan megőrizhető.

## 15.3 Part és track kiválasztás

Importpreview mutassa:

- part nevét;
- MIDI programot, ha elérhető;
- staff countot;
- note countot;
- pitch range-et;
- monophonic/polyphonic elemzést;
- chord symbol countot;
- tab információ jelenlétét.

A felhasználó kiválaszthatja:

- mely partok kerüljenek importálásra;
- melyik legyen default trainer track;
- melyik legyen csak display track.

## 15.4 Divisions konverzió

A MusicXML divisions értéket determinisztikusan kell BeatPositionre alakítani.

A konverzió:

- kerülje a kumulatív double driftet;
- használjon rational vagy integer-alapú köztes reprezentációt;
- dokumentált max denominator limitet alkalmazzon;
- túl komplex tört esetén warninggal, kontrollált quantizationnel dolgozzon.

## 15.5 Repeat expansion

Az importer készítsen lineáris playback sequence-t.

Biztonsági szabályok:

- maximális expanded measure count;
- maximális repeat nesting;
- infinite loop felismerés;
- alternatív ending csak akkor expandálható, ha egyértelmű;
- bizonytalan repeat esetén importálható a score display, de trainer indítás előtt warning szükséges.

## 15.6 MXL biztonság

Az MXL ZIP feldolgozásakor kötelező:

- extracted size limit;
- entry count limit;
- path traversal tiltás;
- absolute path tiltás;
- symlink entry tiltás;
- duplicate entry kezelése;
- `META-INF/container.xml` validálása;
- XML entity expansion tiltása;
- external entity tiltása.

## 15.7 Parser tesztfixturek

Legalább:

- egyszerű 4/4 chord chart;
- 3/4 waltz;
- 6/8;
- tempo change;
- meter change;
- pickup measure;
- two chords per measure;
- monophonic guitar notes;
- tied note;
- rest;
- multi-part score;
- polyphonic part;
- rehearsal marks;
- lyrics;
- repeat;
- corrupt XML;
- malicious MXL path;
- zip bomb limit fixture.

---

# 16. MIDI import

## 16.1 Támogatott formátum

Standard MIDI File:

- format 0;
- format 1;
- PPQ time division.

SMPTE time division az első verzióban warninggal elutasítható, ha a time map konverzió nincs teljesen tesztelve.

## 16.2 Importált események

- track name;
- instrument/program change;
- tempo meta event;
- time signature meta event;
- key signature meta event;
- marker;
- lyric opcionális;
- note on;
- note off;
- velocity;
- channel;
- sustain pedal megjelenítési célra opcionális.

## 16.3 MIDI track kiválasztás

A preview mutassa:

- track/channel;
- instrument;
- note count;
- pitch range;
- polyphony rate;
- monophonic alkalmasság;
- duration;
- suspected drum track.

A channel 10 dobtrack alapértelmezésben ne legyen note trainer track.

## 16.4 Chord inference

A MIDI import első verziójában a chord inference nem kötelező.

Ha később hozzáadásra kerül:

- külön, determinisztikus post-processor legyen;
- confidence score-t adjon;
- az inferred chord vizuálisan megkülönböztetendő az eredeti chord symboltól;
- a felhasználó kikapcsolhatja;
- alacsony confidence mellett ne legyen chord scoring target.

A Codex ne készítsen egyszerű, ellenőrizetlen pitch-class matchinget automatikus igazságként.

## 16.5 Quantization

A forrás MIDI timing megőrzendő.

A display quantization és scoring tolerance külön fogalom.

A nyers note start ne írható felül automatikusan a legközelebbi nyolcaddal. Az importoptions tartalmazhat opcionális quantization preview-t, de az eredeti timeline maradjon visszaállítható.

## 16.6 Malformed MIDI

Kezelendő:

- hiányzó header;
- invalid chunk length;
- running status hiba;
- note off nélkül maradt note;
- note on velocity 0;
- overlapping azonos pitch;
- negatív vagy overflow tick;
- extrém PPQ;
- túl sok event;
- tempo 0;
- időben rendezetlen event.

---

# 17. Guitar Pro feasibility gate

A Guitar Pro import külön kockázati terület. A Codex nem kezdheti el közvetlenül egy nagy, saját binary parser megírását.

## 17.1 Kötelező döntési kör

A production implementáció előtt dokumentált technical és licensing spike szükséges.

Vizsgálandó:

- támogatandó formátumok: GP3, GP4, GP5, GPX vagy újabb;
- formátumok technikai dokumentáltsága;
- elérhető parser megoldások;
- parser licence;
- kereskedelmi mobilalkalmazásban történő felhasználhatóság;
- Android és iOS támogatás;
- offline működés;
- natív library mérete;
- build complexity;
- crash isolation;
- security history;
- parse fidelity;
- test fixture hozzáférhetőség;
- karbantartási kockázat.

## 17.2 Döntési opciók

### A. Jóváhagyott Dart parser

Akkor választható, ha:

- licence megfelelő;
- aktívan vagy elfogadhatóan karbantartott;
- tesztelhető;
- nem húz be elfogadhatatlan dependencyt;
- a támogatott format subset dokumentálható.

### B. Jóváhagyott natív parser adapter

Akkor választható, ha:

- világos FFI vagy platform channel boundary készül;
- parser worker izolálható;
- memóriabiztonság és crash behavior elfogadható;
- Android és később iOS build reprodukálható;
- licence megfelelő.

### C. Konverziós workflow

Ha nincs elfogadható parser:

- az alkalmazás ne ígérjen közvetlen GP importot;
- adjon dokumentált MusicXML vagy MIDI konverziós útvonalat;
- az import képernyő egyértelműen jelezze a támogatott formátumokat;
- a capability későbbi fejlesztésként maradjon.

## 17.3 Kötelező ADR

```text
docs/adr/00xx-guitar-pro-import-strategy.md
```

Az ADR tartalmazza:

- vizsgált megoldások;
- licencek;
- technikai eredmények;
- mintafájl fidelity;
- döntés;
- elutasított alternatívák;
- rollback és maintenance terv.

## 17.4 Import fidelity

Jóváhagyott GP adapter esetén legalább az alábbiak vizsgálandók:

- trackek;
- tuning;
- capo;
- measure;
- tempo;
- meter;
- repeat;
- string/fret;
- note duration;
- tie;
- chord diagram vagy chord text;
- section marker;
- bend, slide, hammer-on és pull-off jelölés;
- palm mute;
- let ring;
- dead note;
- accent.

A technikák megjeleníthetők akkor is, ha automatikusan nem pontozhatók.

---

# 18. Song repository és asset store

## 18.1 Tárolási alapelv

A SongDocument V2 és nagy assetek nem tárolhatók SharedPreferencesben.

Javasolt lokális struktúra:

```text
app_support/
└── songs/
    ├── index.json
    ├── documents/
    │   ├── <song-id>.json
    │   └── ...
    ├── assets/
    │   ├── <sha256>.<ext>
    │   └── ...
    ├── originals/
    │   └── <sha256>.<ext>
    ├── trash/
    └── temp/
```

## 18.2 SongRepository

```dart
abstract interface class SongRepository {
  Future<AppResult<List<SongSummary>>> list(SongQuery query);
  Future<AppResult<SongDocument?>> get(SongId id);
  Future<AppResult<void>> create(SongDocument document);
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  });
  Future<AppResult<void>> moveToTrash(SongId id);
  Future<AppResult<void>> restore(SongId id);
  Future<AppResult<void>> permanentlyDelete(SongId id);
}
```

## 18.3 Atomikus írás

Save folyamat:

1. dokumentum validáció;
2. serialization temporary fájlba;
3. flush;
4. visszaolvasás és decode ellenőrzés;
5. atomikus rename;
6. index update temporary fájlba;
7. index atomikus rename;
8. csak ezután success.

Hiba esetén az előző jó dokumentum maradjon olvasható.

## 18.4 Index

Az index csak gyors listázási adatot tartalmazzon:

- ID;
- title;
- artist;
- tags;
- updatedAt;
- lastPracticedAt;
- capability summary;
- source type;
- favorite;
- archived;
- revision;
- document hash.

A teljes dokumentum ne legyen duplikálva az indexben.

## 18.5 Asset store

A fájlokat content hash alapján tárolja.

Előnyök:

- duplikációcsökkentés;
- integritás-ellenőrzés;
- stabil hivatkozás;
- könnyebb export;
- corrupt asset felismerés.

Az asset metadata:

- asset ID;
- SHA-256;
- extension;
- MIME;
- byte length;
- duration, ha audio;
- createdAt;
- reference count vagy repository-szintű reverse lookup.

## 18.6 Törlés

A dal törlése elsőként trash művelet legyen.

Asset csak akkor törölhető véglegesen, ha:

- nincs másik SongDocument referencia;
- nincs Setlist vagy draft referencia;
- nincs aktív export/import művelet;
- grace period lejárt vagy explicit permanent delete történik.

## 18.7 Recovery

App induláskor recovery check:

- orphan temp file;
- félbehagyott index update;
- hiányzó document;
- hiányzó asset;
- hash mismatch;
- orphan asset;
- duplicate index entry.

A recovery ne töröljön automatikusan felhasználói tartalmat bizonyíték nélkül.

---

# 19. Song transport

## 19.1 Feladat

A SongTransport a dal zenei pozícióját, a trainer sessiont, a metronómot és az opcionális backing playbacket összehangoló application service.

Nem tartalmaz UI-t és nem végez scoringot.

## 19.2 Állapotok

```dart
enum SongTransportPhase {
  idle,
  preparing,
  ready,
  countIn,
  playing,
  paused,
  seeking,
  completed,
  stopping,
  error,
}
```

## 19.3 Engedélyezett átmenetek

```text
idle → preparing
preparing → ready | error
ready → countIn | playing | stopping
countIn → playing | paused | stopping | error
playing → paused | seeking | completed | stopping | error
paused → playing | seeking | stopping
seeking → playing | paused | error
completed → ready | stopping
stopping → idle
error → preparing | idle
```

Tiltott transition kontrollált failure legyen, ne silent no-op, kivéve az idempotens stopot.

## 19.4 SongTransportState

Tartalmazza:

- phase;
- song ID és revision;
- selected track;
- trainer range;
- musical position;
- elapsed active time;
- wall time;
- current measure;
- current section;
- loop index;
- loop count;
- speed;
- backing playback status;
- metronome status;
- count-in beat;
- last error;
- lifecycle interruption reason.

## 19.5 Commandok

- prepare;
- start;
- pause;
- resume;
- seekToPosition;
- seekToMeasure;
- seekToSection;
- setLoop;
- clearLoop;
- setSpeed;
- toggleMetronome;
- setBackingGain;
- restart;
- finish;
- stop.

## 19.6 Effectek

A controller tiszta state transition és effect output mintát használhat.

Effect példák:

- acquire microphone lease;
- prepare backing audio;
- start backing audio;
- pause backing audio;
- seek backing audio;
- start metronome;
- haptic;
- persist resume point;
- navigate to result;
- show recoverable error.

## 19.7 Monotonic clock

A transport nem használhat wall clockot aktív position forrásként.

Kötelező monotonic time source:

- Stopwatch;
- Chapter 2 Clocktól elkülönített monotonic clock interface;
- tesztben fake clock.

A `DateTime.now()` csak metadata timestampre használható.

## 19.8 Position update

UI position update lehet 30–60 Hz, de:

- scorer event matching nem függhet render frame-től;
- audio position korrekció nem történhet minden UI frame-ben;
- transport state ne rebuildelje a teljes képernyőt fölöslegesen;
- külön selectelt providerek szükségesek.

---

# 20. Backing audio és szinkronizáció

## 20.1 BackingAudioPlayer kontraktus

```dart
abstract interface class BackingAudioPlayer {
  Stream<BackingPlaybackEvent> get events;
  PlaybackCapabilities get capabilities;

  Future<AppResult<void>> prepare(SongAssetReference asset);
  Future<AppResult<void>> play();
  Future<AppResult<void>> pause();
  Future<AppResult<void>> seek(Duration position);
  Future<AppResult<void>> setRate(double rate);
  Future<AppResult<void>> setVolume(double volume);
  Future<AppResult<void>> stop();
  Future<void> dispose();
}
```

A domain és application kód ne függjön a konkrét playback package-től.

## 20.2 Playback capability

```dart
final class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.canSeek,
    required this.canChangeRate,
    required this.preservesPitchWhenRateChanges,
    required this.positionPrecision,
    required this.supportedFormats,
  });
}
```

A UI csak támogatott műveletet engedélyezhet.

## 20.3 Grid offset

A backing audio és a score beat 0 közötti offset lehet:

- pozitív: audio később kezdődik;
- negatív: audio eleje a score előtt van.

A backing track session position:

```text
backing position = song musical time + grid offset
```

A count-in nem része automatikusan a backing audio pozíciónak.

## 20.4 Driftkorrekció

A playback position stream nem tekinthető tökéletes clocknak.

Javasolt modell:

1. A SongTransport monotonic clockja a fő időalap.
2. A backing player periodikusan position sample-t ad.
3. A rendszer kiszámítja a driftet.
4. Kis driftet tolerál vagy finoman korrigál.
5. Közepes drift esetén egy biztonságos measure boundary-n resyncelhet.
6. Nagy drift esetén kontrollált resync és non-blocking UI jelzés történik.

Kezdeti küszöböket benchmark alapján kell beállítani, nem találomra.

## 20.5 Seek

Seek sequence:

1. transport phase `seeking`;
2. scoring observation ideiglenes felfüggesztése;
3. backing audio pause;
4. target position kiszámítása;
5. backing seek;
6. scorer range reset vagy új attempt létrehozása;
7. clock anchor frissítése;
8. backing és metronóm újraindítása;
9. phase vissza `playing` vagy `paused` állapotba.

## 20.6 Rate change

Lejátszás közbeni rate change csak akkor támogatható, ha:

- a playback adapter megbízhatóan kezeli;
- a transport új anchor pointot vesz;
- a Practice Engine target time map frissül;
- nincs nyitott, félreérthető scoring window.

Az első verzióban elfogadható, hogy speed csak paused vagy ready állapotban változtatható.

## 20.7 Audio route és interruption

Kezelendő:

- headset kihúzás;
- Bluetooth route change;
- telefonhívás vagy audio focus loss;
- app background;
- player decode error;
- asset eltűnése;
- unsupported codec.

Biztonságos alapviselkedés: automatikus pause, nem automatikus hangos resume.

---

# 21. Practice Engine integráció

## 21.1 SongPracticeCompiler

A Song Trainer a kiválasztott tracket és range-et Chapter 3 `PracticeDefinition` objektummá fordítja.

```dart
abstract interface class SongPracticeCompiler {
  AppResult<PracticeDefinition> compile({
    required SongDocument song,
    required SongTrackId trackId,
    required TrainerRange range,
    required SongTrainerMode mode,
    required SongTrainerConfig config,
  });
}
```

## 21.2 Compiler szabályok

A compiler:

- nem módosítja a SongDocumentet;
- csak a kiválasztott range eseményeit használja;
- a range elejét local beat 0-ra transzformálja;
- megőrzi a source position mappinget;
- átadja a tempo- és meterinformációt;
- megőrzi a measure és section ID-kat a result mappinghez;
- figyelembe veszi a speed multipliert;
- figyelembe veszi a capo és transposition beállítást;
- csak támogatott scoring dimenziót kapcsol be;
- warningot ad, ha target elveszne;
- determinisztikus outputot készít.

## 21.3 Source mapping

Minden PracticeEventhez tartozzon opcionális source reference:

```dart
final class SongEventReference {
  const SongEventReference({
    required this.songId,
    required this.songRevision,
    required this.trackId,
    required this.sourceEventId,
    required this.measureIndex,
    this.sectionId,
  });
}
```

Ez szükséges:

- heatmaphez;
- problem measure azonosításhoz;
- retry range generáláshoz;
- progress aggregációhoz;
- editorba történő visszaugráshoz.

## 21.4 Chord & Rhythm mód

A compiler chord és strum eventekből készít targeteket.

Lehetséges trackhelyzetek:

1. Chord + direction target: teljes chord/rhythm/direction scoring.
2. Chord + ismeretlen direction: chord és rhythm scoring.
3. Csak chord: akkordváltás és measure timing.
4. Csak strum: rhythm és direction scoring.
5. Note onset: rhythm-only scoring.

## 21.5 Measure-ek közötti targetek

A target zenei positionből készül, ezért tempo- vagy meter change nem törheti el a sorrendet.

A measure boundary önmagában nem scoring event.

## 21.6 Range pre-roll

Section vagy A–B range előtt opcionális pre-roll:

- count-in;
- egy korábbi measure vizuális preview-ja;
- backing audio korábbi startja;
- nem pontozott bevezető.

A scorer csak a tényleges target range-ben aktív.

## 21.7 Practice result visszamapping

A Practice Session eredményét SongTrainerResulttá kell alakítani:

- measure metrics;
- section metrics;
- source event verdict;
- loop attempt;
- speed;
- selected track;
- selected range;
- unsupported dimension summary.

---

# 22. Monophonic pitch scoring

## 22.1 Cél

A meglévő YIN pitch detector felhasználásával a rendszer egyhangú gitárriffek és dallamok alapvető értékelésére legyen képes.

A tuner UI vagy provider nem használható közvetlenül. A pitch DSP-t közös audio boundary mögé kell helyezni.

## 22.2 PitchObservation

```dart
final class PitchObservation {
  const PitchObservation({
    required this.observedAt,
    required this.frequencyHz,
    required this.midiPitch,
    required this.centsFromNearest,
    required this.clarity,
    required this.rms,
    required this.stable,
  });
}
```

## 22.3 PitchObservationGateway

```dart
abstract interface class PitchObservationGateway {
  Stream<PitchObservation> get observations;
  Future<AppResult<void>> start(PitchObservationConfig config);
  Future<AppResult<void>> stop();
}
```

A gateway ugyanazt az AudioSessionCoordinator lease-t használja, mint más mic feature.

## 22.4 Scoring dimenziók

### Pitch correctness

A target MIDI pitch és megfigyelt frekvencia közötti cent eltérés alapján.

Javasolt kategóriák:

- exact;
- near;
- offPitch;
- wrongNote;
- noStablePitch.

A konkrét centküszöböket gitáraudio fixture és eszközbenchmark alapján kell meghatározni.

### Onset timing

A stabil target pitch első észlelése és a cél note start közötti eltérés.

A TunerAnalyzer stabilitási ablaka késlelteti az outputot, ezért note trainerhez külön, alacsonyabb latencyre optimalizált, de továbbra is confidence-gated adapter szükséges lehet.

A Codex nem használhatja változtatás nélkül a tuner lock viselkedését onset scoringra parity mérés nélkül.

### Duration coverage

A target note időtartamának mekkora részében volt megfelelő pitch megfigyelhető.

Nem szükséges frame-perfect sustain scoring. A cél robusztus coverage arány.

### Extra note

Olyan stabil note onset, amelyhez nincs nyitott target a toleranciaablakban.

Az extra note büntetési policy legyen konfigurálható és enyhe, hogy transition noise ne rontsa aránytalanul a score-t.

## 22.5 Pitch transposition

Scoring target:

```text
sounding target = written MIDI pitch + transposition + capo effect
```

A capo hatása gitárpozíció és hangzó pitch szempontjából külön kezelendő.

- Written pitch: importált score hangja.
- Sounding pitch: amit a mikrofonban várunk.
- Display fret: tuning, string és capo alapján számítható, ha ismert.

## 22.6 Tuning

A note trainer a kiválasztott tuningot használja.

Ha az importált string/fret pozíció nem kompatibilis a felhasználó által választott tuninggal:

- a pitch target továbbra is értékelhető;
- a tab position warningot kap;
- az app ne mutasson biztos fretet, ha az újrafingering nincs implementálva.

## 22.7 Polyphony detection

Ha a kiválasztott range-ben overlap történik:

- a session setup figyelmeztet;
- a monophonic pitch scoring kikapcsol;
- rhythm-only vagy display-only mód ajánlható;
- a rendszer nem választ önkényesen egyetlen hangot az akkordból score targetnek.

## 22.8 Pitch scorer interfész

```dart
abstract interface class MonophonicNoteScorer {
  NoteScoringUpdate observe(PitchObservation observation);
  NoteScoringUpdate advance(Duration activeTime);
  NoteScoringResult finalize();
}
```

A scorer tiszta és determinisztikusan tesztelhető legyen.

## 22.9 Tesztfixturek

- tiszta E2;
- tiszta A2;
- magas E4;
- kromatikus riff;
- korai note;
- késő note;
- félhanggal hibás note;
- oktávhiba;
- rövid note;
- vibrato;
- bend, amelyet az alap scorer nem értékel technique-ként;
- transition noise;
- beszéd;
- csend;
- két egyszerre szóló hang;
- Drop D tuning;
- capo.

---

# 23. Section, measure és A–B loop

## 23.1 TrainerRange

```dart
sealed class TrainerRange {
  const TrainerRange();
}

final class FullSongRange extends TrainerRange {}
final class SectionRange extends TrainerRange {
  const SectionRange(this.sectionId);
  final SongSectionId sectionId;
}
final class MeasureRange extends TrainerRange {
  const MeasureRange(this.start, this.endExclusive);
  final int start;
  final int endExclusive;
}
final class BeatRange extends TrainerRange {
  const BeatRange(this.start, this.end);
  final BeatPosition start;
  final BeatPosition end;
}
```

## 23.2 LoopConfig

```dart
final class LoopConfig {
  const LoopConfig({
    required this.range,
    this.maxRepeats,
    this.pauseBetweenLoops = Duration.zero,
    this.countInEachLoop = false,
    this.autoAdvance = false,
  });
}
```

## 23.3 Loop behavior

Egy loop végekor:

1. scorer attempt finalize;
2. attempt result eltárolódik;
3. progress nem feltétlenül commitálódik minden loopnál;
4. backing audio pause vagy seek;
5. transport seek loop startra;
6. opcionális rövid pause;
7. opcionális count-in;
8. új attempt indul;
9. loop counter nő.

Nem engedélyezett a scorer belső state-jének kontrollálatlan újrahasználata két attempt között.

## 23.4 Problem range generálás

A SongTrainerCoach measure metricsből javasolhat problem ranget.

Szabály:

- legalább egy teljes measure;
- tartalmazzon pre-rollt vagy vizuális előkészítést;
- ne legyen túl rövid a felismeréshez;
- a javaslat legyen determinisztikus;
- azonos gyenge score esetén korábbi measure vagy nagyobb zenei egység prioritása dokumentált legyen.

## 23.5 Loop result

Loop session végén:

- first attempt score;
- best attempt score;
- last attempt score;
- improvement;
- stable speed;
- repeated problem event;
- completed repeat count.

## 23.6 Bookmark

A felhasználó elmenthet:

- measure bookmarkot;
- beat range bookmarkot;
- section favorite-ot;
- saját nevet;
- default speedet;
- default trainer mode-ot.

A bookmark Song ID és revision mellett source positionre hivatkozzon. Document edit után migration vagy invalidation szükséges.

---

# 24. Speed, transposition, capo és tuning

## 24.1 Speed

Támogatott kezdeti tartomány strukturált playbacknél például:

```text
50%–150%
```

A pontos UI tartomány konfigurálható.

Backing audiónál a támogatott tartományt a playback capability határozza meg.

## 24.2 Speed Builder integráció

A Chapter 3 Speed Builder policy használható song range-re.

A state tárolja:

- song ID;
- track ID;
- range;
- start speed;
- target speed;
- step;
- pass requirement;
- attempts per step;
- highest stable speed.

A `stable speed` nem egyetlen sikeres attempt. A policy legalább több próbából vagy erősebb thresholdból vezesse le.

## 24.3 Transposition

A transposition nem módosítja az eredeti importált dokumentumot session közben.

A session config adja meg a semitone offsetet.

Transponálni kell:

- chord displayt;
- chord scoring targetet;
- note pitch targetet;
- key displayt;
- opcionális fret displayt, ha biztonságosan számítható.

Nem transponálandó automatikusan:

- lyrics;
- backing audio, hacsak pitch-shift támogatás nincs;
- eredeti source metadata.

## 24.4 Chord spelling

Transpositionkor a chord neveknél preferálni kell a dal key contextjének megfelelő enharmonikus írásmódot.

Ha ez nem áll rendelkezésre, determinisztikus default policy szükséges.

## 24.5 Capo

A capo két üzemmódot különböztessen meg:

1. **Display capo:** akkordformát mutat, de hangzó akkordot pontoz.
2. **Sounding transpose:** a teljes célhang transzponálódik.

A UI-nak világosan jeleznie kell:

- written chord;
- shape chord;
- sounding chord.

## 24.6 Tuning

A SongDocument default tuningja sessionben felülírható.

Tuningváltozás hatása:

- note pitch scoring target nem változik, ha a written score sounding pitch alapú;
- string/fret display kompatibilitása változhat;
- chord shape availability változhat;
- tuning reminder jelenjen meg indítás előtt;
- a Tuner feature-be deep link adható a szükséges tuninggal.

---

# 25. Setlist V2

## 25.1 Modell

```dart
final class SongSetlist {
  const SongSetlist({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });
}

final class SongSetlistItem {
  const SongSetlistItem({
    required this.id,
    required this.songId,
    this.trackId,
    this.range = const FullSongRange(),
    this.mode = SongTrainerMode.auto,
    this.speedMultiplier = 1,
    this.loopCount = 1,
    this.countInBars = 1,
    this.pauseAfter = Duration.zero,
    this.capoOverride,
    this.tuningOverride,
  });
}
```

## 25.2 Practice mode

- minden item külön attempt/session;
- dal után result megjelenhet;
- Retry és Continue gomb;
- problem range javaslat;
- progress mentés;
- daily goal és streak jogosultság a Chapter 3 policy szerint.

## 25.3 Performance mode

- minimális kezelőfelület;
- automatikus következő item;
- opcionális pause countdown;
- tuning és capo reminder;
- scoring opcionálisan kikapcsolható;
- eredmény csak a végén;
- képernyő ne aludjon el, ha a user engedélyezi;
- mic használat csak szükséges trainer mode esetén.

## 25.4 Hiányzó dal vagy asset

A setlist ne omoljon össze.

Az item állapota lehet:

- ready;
- missingSong;
- missingAsset;
- unsupportedTrack;
- requiresMigration;
- invalidConfig.

Practice módban javítási lehetőség, performance módban skip policy szükséges.

## 25.5 Legacy Setlist migráció

A régi song ID lista minden eleme V2 itemmé válik default beállításokkal.

Duplikált song ID megmarad külön itemként.

Hiányzó song ID megmaradhat unresolved itemként a recovery érdekében, nem kötelező némán eldobni.

## 25.6 Setlist result

- total active practice time;
- dalonként score;
- completed/skipped item;
- tuning transition;
- highest stable speed;
- problem song;
- next recommended practice.

---

# 26. Progress és analytics

## 26.1 SongPracticeRecord

```dart
final class SongPracticeRecord {
  const SongPracticeRecord({
    required this.id,
    required this.songId,
    required this.songRevision,
    required this.trackId,
    required this.range,
    required this.mode,
    required this.startedAt,
    required this.activeDuration,
    required this.speedMultiplier,
    required this.completed,
    required this.metrics,
    required this.measureMetrics,
    required this.loopAttempts,
  });
}
```

## 26.2 Per-measure metrics

Legalább:

- attempts;
- timing score;
- rhythm score;
- direction score;
- chord score;
- pitch score;
- missed target count;
- wrong target count;
- last practiced;
- best speed;
- stable speed;
- confidence vagy supported dimension mask.

Nem minden mód tölti ki minden dimenziót. A null vagy unavailable különbözzön a 0 ponttól.

## 26.3 Aggregáció

A SongProgressService számolja:

- full song completion;
- section mastery;
- measure mastery;
- best score;
- recent trend;
- highest stable speed;
- most practiced section;
- least stable measure;
- last resume position.

## 26.4 Revision kezelés

Ha a dal szerkezete módosul:

- régi progress nem írható vakon az új measure indexekre;
- event és measure stable ID segíthet a mappingben;
- kompatibilis edit esetén mapping történhet;
- nagy szerkezeti változásnál a régi record historyként megmarad, de current heatmapbe nem keverhető;
- a felhasználó láthatja, hogy az eredmény egy korábbi revisionhöz tartozik.

## 26.5 Practice eligibility

Daily goal és streak csak akkor frissül, ha:

- volt tényleges aktív practice idő;
- a session nem kizárólag preview playback volt;
- a minimum duration vagy minimum target policy teljesült;
- a session nem debug fixture;
- ugyanaz a session nem kerül kétszer commitálásra.

## 26.6 Privacy analytics

Alapértelmezetten lokális.

Felhőanalytics vagy diagnosztika esetén:

- importált dalcím ne kerüljön automatikusan feltöltésre;
- lyrics ne kerüljön feltöltésre;
- raw note sequence ne kerüljön feltöltésre;
- file hash személyes tartalomazonosítóként kezelendő;
- csak explicit, dokumentált és opt-in adat gyűjthető.

---

# 27. UI specifikáció

## 27.1 Song Library V2

Fő elemek:

- keresőmező;
- filter gomb;
- sort gomb;
- Import;
- New song;
- Setlists;
- recent section;
- favorites;
- song cards.

Song card:

- title;
- artist;
- source icon;
- capability badge;
- tempo;
- meter;
- tuning;
- last practice;
- progress indicator;
- overflow menu.

## 27.2 Import screen

Állapotok:

- idle;
- file selecting;
- probing;
- preview;
- importing;
- validating;
- committing;
- completed;
- cancelled;
- failed.

A progress ne legyen hamis százalék, ha a parser nem tud valós progresset. Használható lépésalapú állapot.

## 27.3 Import preview

Mutassa:

- file name és size;
- detected format;
- title és artist;
- duration;
- tempo/meter summary;
- parts/tracks;
- selected trainer track;
- capability report;
- warningok severity szerint;
- Keep original source file opció;
- Import gomb.

Fatal error esetén Import gomb disabled.

## 27.4 Song Overview

Szakaszok:

- hero metadata;
- primary Start button;
- Resume button, ha van;
- sections;
- tracks;
- trainer capabilities;
- progress heatmap summary;
- import details;
- actions.

## 27.5 Song Editor V2

Az editor első verziója ne próbáljon teljes kottaszerkesztő lenni.

Fókusz:

- metadata;
- sections;
- measure grid;
- chord events;
- strum events;
- basic notes;
- tempo/meter markers;
- backing asset;
- validation panel.

Kötelező:

- undo/redo;
- dirty state;
- explicit save;
- cancel confirmation;
- invalid field focus;
- measure copy/paste;
- bulk pattern apply;
- preview.

## 27.6 Trainer setup

A setup csak releváns opciót mutasson.

Példák:

- chord-only dalnál ne jelenjen meg note scoring toggle;
- backing nélkül ne jelenjen meg backing volume;
- polyphonic tracknél legyen disabled pitch scoring magyarázattal;
- speed capability hiányában legyen disabled control indoklással.

## 27.7 Song Trainer screen

Fő layout:

```text
Top bar: Back | Song | Section | Measure
Status: Count-in / Playing / Paused / Loop 2 of 5
Main lane: chord / strum / note / tab visualization
Current + next target
Measure progress
Live verdict feedback
Transport controls
Loop + speed controls
```

A fő lane ne próbáljon egyszerre minden tracket megjeleníteni kis képernyőn.

Választható lane:

- chord lane;
- rhythm lane;
- note highway;
- compact tab lane;
- overview timeline.

## 27.8 Note és tab megjelenítés

Monophonic note trainerben legalább:

- note name;
- string/fret, ha ismert;
- timing position;
- duration;
- current target;
- next target;
- observed pitch deviation.

A tab lane ne állítson fretet, ha csak MIDI pitch áll rendelkezésre és nincs fingering megadva.

## 27.9 Loop control

- Set A;
- Set B;
- clear loop;
- current range label;
- repeat count;
- loop result;
- Speed Builder toggle.

A mozgó playhead mellett a loop határ legyen vizuálisan és szemantikailag is érthető.

## 27.10 Result screen

Mutassa:

- overall supported score;
- nem támogatott dimenziók magyarázatát;
- measure heatmapet;
- section resultot;
- trendet;
- speedet;
- loopszámot;
- top insightokat;
- problem range CTA-t;
- next section CTA-t;
- retry;
- library visszatérés.

## 27.11 Hibaállapotok

Külön UI szükséges:

- unsupported file;
- corrupt file;
- import limit;
- password-protected archive;
- missing asset;
- unsupported audio codec;
- mic permission denied;
- mic busy;
- audio route interruption;
- parser cancelled;
- unsupported polyphonic scoring;
- song revision conflict;
- storage full;
- recovery needed.

---

# 28. Accessibility és localization

## 28.1 Accessibility

- minden transport controlnak label és state legyen;
- play/pause ne csak ikon alapján különüljön el;
- measure és section navigáció billentyűzettel és screen readerrel használható legyen;
- CustomPainter lane-ek rendelkezzenek szemantikai összefoglalóval;
- élő verdict ne spammelje a screen readert minden frame-ben;
- fontos változások throttled live region üzenetet kaphatnak;
- color heatmap mellett szám vagy szöveg is legyen;
- wrong direction ne csak piros szín legyen;
- note pitch deviation kapjon verbális leírást;
- minimum touch target betartandó;
- landscape módban se legyen levágott vezérlő;
- reduced motion beállításnál a highway animáció egyszerűsíthető;
- focus order legyen logikus.

## 28.2 Localization

Minden UI szöveg ARB-ból jön.

Kerülendő:

- string concatenation fordítható mondatokban;
- hardcoded `Verse`, `Chorus`, `Measure`, `Track`;
- angol import error a UI-ban;
- chord és note nevek nyelvi összekeverése.

A chord symbol zenei adat, nem fordítandó. A section kind lokalizálható display label.

## 28.3 Zenei jelölés

A locale befolyásolhatja:

- B/H note naminget;
- decimal formázást;
- dátumot;
- durationt.

A perzisztált zenei pitch és chord representation locale-független legyen.

## 28.4 Nagy szöveg

Legalább 200%-os text scale mellett:

- setup screen scrollozható;
- transport controls nem fedik egymást;
- result card nem clipel;
- importwarning olvasható;
- song card metadata törhet vagy elrejthető prioritás szerint.

---

# 29. Adatvédelem, szerzői jog és biztonság

## 29.1 Offline alapelv

A dalimport, parser, library, playback és scoring alapértelmezetten helyi.

Az alkalmazás nem küldi fel:

- importált score fájlt;
- backing tracket;
- lyrics tartalmat;
- note sequence-t;
- file hash-t;
- dalcímet

kifejezett, külön dokumentált felhasználói művelet nélkül.

## 29.2 Szerzői jog

A StrumSight ebben az Epicben felhasználó által biztosított vagy saját készítésű tartalmat kezel.

Nem része:

- szerzői joggal védett dalok automatikus letöltése;
- publikus dalkatalógus jogosultság nélkül;
- importált teljes dal továbbosztása;
- backing track automatikus feltöltése;
- lyrics automatikus publikálása.

Export előtt a felhasználó kapjon rövid figyelmeztetést, hogy csak olyan tartalmat osszon meg, amelyhez joga van.

## 29.3 File security

- fájlnév sanitization;
- path traversal tiltás;
- XML external entity tiltás;
- ZIP bomb limit;
- decompression limit;
- temporary file permission;
- asset hash ellenőrzés;
- parser timeout;
- natív parser esetén crash isolation;
- unsupported format fail-closed.

## 29.4 Log redaction

Ne kerüljön logba:

- teljes lyrics;
- teljes note sequence;
- teljes source file path;
- audio fájl byte tartalma;
- importált fájl teljes XML-je;
- token vagy user identity.

Logolható:

- format;
- importer version;
- byte size bucket;
- warning code;
- parse duration;
- track count;
- error type;
- redacted filename vagy extension.

---

# 30. Teljesítménykövetelmények

## 30.1 Library

Cél:

- több száz dal listázása teljes dokumentumok decode-ja nélkül;
- indexalapú keresés;
- lazy document load;
- lazy artwork;
- scrolling közben nincs parser vagy nagy file IO.

## 30.2 Import

- nagy parse munka ne a UI isolate-ban fusson;
- progress state limitált frissítési frekvenciával érkezzen;
- cancellation működjön;
- parser memory limit dokumentált legyen;
- archívumot streamelve vagy kontrollált bufferrel kezelje;
- import után temporary memória felszabaduljon.

## 30.3 Trainer

- 60 FPS cél támogatott készüléken;
- real-time scorer ne várjon file IO-ra;
- backing position polling ne okozzon frame rebuildet;
- target lane windowinget használjon, ne renderelje a teljes hosszú dalt;
- measure heatmap aggregált adatból készüljön;
- pitch DSP isolate-ban vagy optimalizált workerben fusson;
- audio frame-enként ne történjen JSON vagy collection-heavy allokáció.

## 30.4 Hosszú dalok

Tesztelendő legalább:

- 10 perces dal;
- 500 measure;
- 10 000 note event;
- több tempo change;
- több track;
- lyrics;
- backing audio;
- section loops.

A konkrét maximális limiteket baseline mérés után dokumentálni kell.

## 30.5 Startup

A Song Trainer inicializációja ne lassítsa az app cold startot.

Importer registry és nagy parser asset csak szükség esetén inicializálódjon.

---

# 31. Tesztelési stratégia

## 31.1 Domain unit tesztek

- SongDocument equality;
- serialization;
- metadata validation;
- section range;
- measure duration;
- tempo map;
- meter map;
- SongTimeMap conversion;
- capability resolution;
- monophonic analysis;
- chord normalization;
- transposition;
- capo mapping;
- tuning compatibility;
- trainer range;
- setlist config.

## 31.2 Property tesztek

- serialize/deserialize round-trip;
- normalize idempotencia;
- beat → time → beat round-trip;
- tempo map monotonicitás;
- event sorting stability;
- import event order;
- legacy migration idempotencia;
- repository atomic recovery;
- loop range invariáns;
- setlist reorder;
- note overlap analyzer;
- transposition inverse;
- no event outside song duration.

## 31.3 Parser fixture tesztek

Minden importernek versioned fixture könyvtára legyen.

```text
test/fixtures/song_import/
├── native/
├── musicxml/
├── mxl/
├── midi/
└── guitar_pro/
```

Minden fixture mellett legyen:

- source file;
- expected normalized snapshot;
- expected warnings;
- capability report;
- licence vagy fixture origin dokumentáció.

Copyright szempontból a fixture saját készítésű, public domain vagy minimális technikai minta legyen.

## 31.4 Golden snapshot

Parser outputhoz stabil JSON snapshot használható.

Snapshot update csak akkor fogadható el, ha:

- változás indokolt;
- warning különbség megértett;
- event count és zenei timing ellenőrzött;
- review leírásban szerepel.

## 31.5 Repository tesztek

- create;
- read;
- update revision;
- conflict;
- atomic interruption;
- corrupted document;
- corrupted index;
- missing asset;
- hash mismatch;
- trash;
- restore;
- reference-aware delete;
- legacy migration;
- storage full failure.

## 31.6 Transport unit tesztek

Fake monotonic clockkal:

- minden transition;
- invalid transition;
- count-in;
- pause/resume;
- seek;
- loop;
- completed;
- stop idempotencia;
- app background;
- route interruption;
- playback error;
- rate change;
- drift sample.

## 31.7 Pitch scorer tesztek

- exact pitch;
- cent threshold határok;
- wrong semitone;
- octave error;
- early/late onset;
- short sustain;
- unstable pitch;
- extra note;
- silence;
- transition noise;
- polyphonic guard;
- latency compensation;
- capo és transpose.

## 31.8 Widget tesztek

- library empty és populated;
- search/filter;
- import state-ek;
- warning list;
- overview capability badge;
- setup conditional controls;
- transport accessibility;
- loop controls;
- result heatmap;
- large text;
- Hungarian és English localization;
- dark/light theme;
- landscape.

## 31.9 Integration tesztek

- legacy song → V2 → trainer;
- native import → save → reopen → practice;
- MusicXML import → track select → section practice;
- MIDI import → monophonic note practice;
- backing asset attach → play → seek → loop;
- app background → safe pause;
- result → progress → resume;
- Setlist V2 practice flow;
- missing asset recovery;
- importer cancellation.

## 31.10 Valós eszközös tesztek

Legalább két Android teljesítményszinten:

- import file picker;
- MXL parse;
- MIDI parse;
- backing playback;
- Bluetooth és wired route;
- mic scoring;
- pitch scoring alacsony és magas gitárhangon;
- 20 perces session;
- repeated seek;
- 20 loop;
- app background;
- screen lock;
- storage low helyzet, ha reprodukálható.

---

# 32. Codex végrehajtási szabályok

1. Minden kör előtt olvasd el:
   - `AGENTS.md`;
   - Chapter 2;
   - Chapter 3;
   - ezt a fejezetet;
   - az érintett legacy Song és Setlist kódot;
   - az érintett teszteket.

2. Egy körben csak az adott kör scope-ját implementáld.

3. Ne töröld a legacy Song vagy Setlist kódot a migrációs kör előtt.

4. Ne írj saját Guitar Pro binary parsert a feasibility döntés előtt.

5. Ne állíts támogatást olyan formátumra, amelyhez nincs fixture és capability report.

6. Parser dependency hozzáadása előtt dokumentáld:
   - licence;
   - méret;
   - platform support;
   - maintenance;
   - security.

7. Ne tölts teljes nagy fájlt memóriába indoklás nélkül.

8. Ne végezz parser vagy nagy file IO munkát a UI isolate-ban.

9. Ne tárolj SongDocumentet SharedPreferencesben.

10. Ne importálj feature belső presentation vagy provider fájlt.

11. Minden parser warning stabil code-dal rendelkezzen.

12. Minden új persisted modell schema versiont kapjon.

13. Minden save atomikus legyen.

14. Minden lifecycle erőforrás felszabadítása tesztelendő.

15. Minden scoring állítás capabilityvel alátámasztott legyen.

16. Ne változtasd meg a Chapter 3 pontozási küszöbeit ebben az Epicben külön benchmark és ADR nélkül.

17. Pitch scorerhez ne használd vakon a tuner stabil lock pipeline-t.

18. A fixturek ne tartalmazzanak jogosulatlan, teljes kereskedelmi dalt.

19. A kör végén futtasd a célzott teszteket és a teljes releváns regressziót.

20. Frissítsd a `HANDOFF.md` fájlt:
   - elkészült scope;
   - változtatott fájlok;
   - tesztek;
   - warningok;
   - következő kör;
   - ismert kockázat.

---

# 33. Fejlesztési körök

# Kör 1 — Song Trainer baseline, ADR-ek és feature flag

## Cél

A jelenlegi Songs és Setlists viselkedésének rögzítése, valamint az Epic migrációs határainak létrehozása alkalmazáskód-változtatás nélkül vagy minimális rollout scaffolddal.

## Feladatok

1. Készíts baseline dokumentumot:

```text
docs/baseline/epic-03-song-trainer-start.md
```

Tartalmazza:

- jelenlegi Song és Setlist fájlok;
- perzisztenciakulcsok;
- JSON schema;
- támogatott meterek;
- Song Builder funkciók;
- Learn integráció;
- Setlist combine viselkedés;
- jelenlegi tesztek;
- ismert korlátok;
- dal- és setlistrekord minták.

2. Hozd létre az ADR-eket:

```text
docs/adr/00xx-song-document-v2.md
docs/adr/00xx-song-storage-files-and-assets.md
docs/adr/00xx-song-import-security-boundary.md
docs/adr/00xx-song-trainer-practice-engine-integration.md
```

3. Add hozzá a `songTrainerV2Enabled` feature flaget.

4. Hozd létre az üres feature public boundaryt:

```text
lib/features/song_trainer/public.dart
```

5. Készíts legacy fixture snapshotokat legalább:

- 4/4 dal;
- 3/4 dal;
- rests;
- több chord;
- setlist duplikált dallal;
- setlist hiányzó song ID-val;
- eltérő BPM-ű dalok.

6. Dokumentáld a parity mérőszámokat:

- event count;
- total beats;
- chord sequence;
- strum direction sequence;
- duration;
- meter;
- share timeline;
- setlist order.

## Kötelező tesztek

A meglévő Song és Setlist tesztcsomag változtatás nélkül fusson.

```bash
flutter test test/features/songs
flutter test test/features/learn/setlist_expected_hint_test.dart
```

## Elfogadási feltételek

- baseline elkészült;
- ADR-ek elkészültek;
- feature flag alapértelmezetten kikapcsolt;
- nincs legacy viselkedésváltozás;
- fixturek saját vagy technikai tartalmúak;
- minden meglévő teszt zöld.

## Javasolt commit

```text
chore(song-trainer): establish Epic 3 baseline and boundaries
```

---

# Kör 2 — SongDocument V2 azonosítók és metaadatok

## Cél

A Song Trainer legalapvetőbb immutable domain típusainak létrehozása event- és parserlogika nélkül.

## Új fájlok

```text
lib/features/song_trainer/domain/models/song_id.dart
lib/features/song_trainer/domain/models/song_metadata.dart
lib/features/song_trainer/domain/models/song_source.dart
lib/features/song_trainer/domain/models/song_document.dart
lib/features/song_trainer/domain/models/song_asset_reference.dart
lib/features/song_trainer/domain/models/song_marker.dart
```

## Feladatok

1. Implementáld a typed ID-kat:
   - SongId;
   - SongSectionId;
   - SongTrackId;
   - SongEventId;
   - SongAssetId;
   - SongMarkerId.

2. Az ID validáljon:
   - nem üres;
   - maximális hossz;
   - fájlrendszerbiztos karakterkészlet vagy külön safe filename mapping;
   - equality és hash.

3. Implementáld a SongMetadata modellt.

4. Implementáld a SongSource és SongSourceType modellt.

5. Hozd létre a minimális SongDocument skeleton modellt üres listákkal.

6. Vezesd be a `schemaVersion` és `revision` mezőt.

7. Készíts explicit JSON codecet. A domain modell ne függjön platform API-tól.

8. Készíts determinisztikus `copyWith` vagy immutable update megoldást.

9. A DateTime értékek UTC ISO-8601 formátumban legyenek perzisztálva.

## Kötelező tesztek

- ID valid és invalid értékek;
- metadata validáció;
- JSON round-trip;
- UTC timestamp round-trip;
- revision megőrzés;
- equality;
- unknown source type kontrollált codec failure vagy forward-compatible policy;
- title whitespace normalizálás.

## Elfogadási feltételek

- a modellek Flutter-függetlenek;
- nincs más feature import;
- a codec determinisztikus;
- minden persisted root mező dokumentált;
- legalább 90% line coverage az új domain fájlokon.

## Javasolt commit

```text
feat(song-domain): add versioned SongDocument identity and metadata
```

---

# Kör 3 — Section, measure, tempo, meter és SongTimeMap

## Cél

A dal strukturális és zenei időmodelljének létrehozása a Chapter 3 beat value objectjeire építve.

## Új fájlok

```text
lib/features/song_trainer/domain/models/song_section.dart
lib/features/song_trainer/domain/models/song_measure.dart
lib/features/song_trainer/domain/models/tempo_map.dart
lib/features/song_trainer/domain/models/meter_map.dart
lib/features/song_trainer/domain/models/key_map.dart
lib/features/song_trainer/domain/services/song_time_map.dart
```

## Feladatok

1. Implementáld a section modellt és kind enumot.
2. Implementáld a measure modellt pickup támogatással.
3. Implementáld a TempoMapet.
4. Implementáld a MeterMapet.
5. Implementáld a KeyMapet minimális, locale-független reprezentációval.
6. Implementáld a beat → duration és duration → beat konverziót.
7. Kezeld a tempo change boundaryt.
8. Kezeld a pickup measure-t.
9. Biztosítsd, hogy a SongTimeMap monoton legyen.
10. A speed multiplier ne módosítsa a map source adatait.
11. Ne használj kumulatív, kontrollálatlan double összeadást measure-enként.
12. Dokumentáld a rational/integer köztes reprezentációt.

## Property tesztek

- beat → time → beat round-trip;
- monotonicitás;
- azonos tempo map determinisztikus output;
- speed 1.0 parity;
- speed 0.5 kétszeres duration;
- speed 2.0 fele duration;
- tempo change előtt és után continuity;
- invalid map elutasítás;
- pickup duration.

## Elfogadási feltételek

- 3/4 és 4/4 támogatott;
- 6/8 reprezentálható;
- tempo- és meter change tesztelt;
- a map UI- és Flutter-független;
- round-trip hiba dokumentált tolerancián belüli.

## Javasolt commit

```text
feat(song-domain): add song structure and deterministic time maps
```

---

# Kör 4 — Trackek, események és monophonic elemzés

## Cél

A chord, strum, note, lyrics, marker és backing track domain létrehozása.

## Feladatok

1. Implementáld a sealed SongTrack hierarchiát.
2. Implementáld:
   - SongChordEvent;
   - SongStrumEvent;
   - SongNoteEvent;
   - SongLyricEvent;
   - SongMarkerEvent.
3. Hozd létre a SongInstrument value objectet.
4. Hozd létre a guitar tuning domain modellt, vagy használd a Chapter 2 közös tuning API-ját.
5. Implementáld a note technique jelölés stabil, extensible modelljét.
6. Implementáld a NoteTrackAnalyzert.
7. Különböztesd meg a display-only és scoring-releváns adatokat.
8. Implementáld a string/fret validációt.
9. Normalizáld az event sorrendet start, track és stable ID alapján.
10. Biztosítsd az eventek immutable listáját.

## Kötelező tesztek

- minden track JSON round-trip;
- chord event;
- direction unknown;
- note pitch range;
- invalid fret;
- tied note;
- monophonic track;
- overlapping note;
- azonos pitchű tie normalizálás előkészítése;
- lyrics nem scoring capability;
- backing track csak asset ID-t tárol.

## Elfogadási feltételek

- a SongDocument már teljes track listát tud tárolni;
- a domain nem tartalmaz platform fájlútvonalat;
- monophonic alkalmasság determinisztikus;
- az unsupported technique nem okoz adatvesztést.

## Javasolt commit

```text
feat(song-domain): add structured tracks events and note analysis
```

---

# Kör 5 — Validator, normalizer és capability resolver

## Cél

A SongDocument biztonságos persistálhatóságának és őszinte trainer capabilityinek megvalósítása.

## Új fájlok

```text
lib/features/song_trainer/domain/services/song_validator.dart
lib/features/song_trainer/domain/services/song_normalizer.dart
lib/features/song_trainer/domain/services/song_capability_resolver.dart
lib/features/song_trainer/domain/models/song_validation_report.dart
lib/features/song_trainer/domain/models/song_capability.dart
lib/features/song_trainer/domain/models/import_warning.dart
```

## Feladatok

1. Implementáld a validation severity és stabil code rendszert.
2. Implementáld az importPreview, persist, trainer és export validation profile-t.
3. Implementáld a normalizálást:
   - sorting;
   - duplicate tempo collapse;
   - full song section;
   - chord normalization;
   - tied note merge;
   - ID generation csak hiányzó import ID esetén.
4. Implementáld a capability resolver-t track és document szinten.
5. A scoring capability különüljön el a display capabilitytől.
6. Készíts lokalizációs key mapping boundaryt, de domainben ne legyen kész mondat.
7. Minden automatikus javítás kerüljön a reportba.

## Property tesztek

- normalize idempotencia;
- normalizált event sorrend stabil;
- validator soha nem dob ismeretlen inputnál;
- capability nem állít pitch scoringot polyphonic trackre;
- unsupported chord mellett display és scoring különbözik;
- fatal error mellett persist capability false.

## Elfogadási feltételek

- invalid dokumentum nem menthető;
- warningos dokumentum preview-zhető;
- capability report stabil és tesztelt;
- nincs hamis teljes támogatás jelzés;
- a normalizer nem változtat bizonytalan zenei jelentést.

## Javasolt commit

```text
feat(song-domain): validate normalize and classify trainer capabilities
```

---

# Kör 6 — Legacy Song V1 és Setlist migrációs adapter

## Cél

A jelenlegi felhasználói dalok veszteségmentes átalakítása SongDocument V2 formátumba.

## Új fájlok

```text
lib/features/song_trainer/data/migration/legacy_song_reader.dart
lib/features/song_trainer/data/migration/legacy_song_adapter.dart
lib/features/song_trainer/data/migration/legacy_setlist_adapter.dart
lib/features/song_trainer/data/migration/legacy_migration_report.dart
```

## Feladatok

1. A legacy adapter ne importálja a régi Song presentation rétegét.
2. Hozz létre kis, dokumentált legacy DTO-t vagy codec boundaryt.
3. Egy legacy chordból egy teljes measure chord event készüljön.
4. A pattern minden measure-re másolódjon.
5. Az első tempo és meter event beat 0-n legyen.
6. Jöjjön létre Full song section.
7. Legacy ID őrződjön meg.
8. A source type `legacyLocal` legyen.
9. Készíts V2 → legacy parity preview adaptert csak tesztcélra, ha szükséges.
10. A setlist item duplikációk maradjanak meg.
11. Hiányzó song ID unresolved itemként reportolódjon.
12. A migráció még ne törölje a legacy storage-t.

## Parity tesztek

- 4/4 event count;
- 3/4 event positions;
- rests;
- chord sequence;
- direction sequence;
- total beats;
- duration;
- `Song.toAnalyzeResult()` időzítéshez tartalmi parity;
- setlist sorrend;
- duplikált dal;
- eltérő BPM;
- corrupt pattern repair parity.

## Elfogadási feltételek

- minden fixture migrálható;
- migráció determinisztikus;
- migráció idempotens;
- nincs legacy adat törlés;
- parity eltérés nincs vagy ADR-ben jóváhagyott.

## Javasolt commit

```text
feat(song-migration): adapt legacy songs and setlists to V2
```

---

# Kör 7 — Fájlrendszeres Song repository és asset store

## Cél

A V2 dalok és nagy assetek biztonságos, atomikus lokális tárolása.

## Feladatok

1. Implementáld a SongRepository interfészt.
2. Implementáld a file-based repositoryt.
3. Implementáld az index codecet.
4. Implementáld az atomic file writert.
5. Implementáld az asset repositoryt SHA-256 integritással.
6. Implementáld a trash és restore folyamatot.
7. Implementáld a revision conflictot.
8. Implementáld a startup recovery scant.
9. Hozz létre fake in-memory repositoryt tesztekhez.
10. Ne vezess be globális singleton pathot; platform directory provider legyen injektálható.
11. A document file és index write sorrend legyen dokumentált.
12. Az asset import másolás legyen streamelt.

## Kötelező tesztek

- create/read;
- update;
- revision conflict;
- temp write crash szimuláció;
- corrupt document;
- corrupt index;
- missing document;
- asset hash mismatch;
- duplicate asset deduplication;
- trash/restore;
- permanent delete;
- referenced asset megőrzése;
- orphan recovery;
- storage failure.

## Elfogadási feltételek

- SongDocument nem kerül SharedPreferencesbe;
- save atomikus;
- indexből gyors listázás lehetséges;
- asset integritás ellenőrzött;
- hiba nem okoz korábbi jó verzió elvesztését.

## Javasolt commit

```text
feat(song-storage): add atomic document and asset repositories
```

---

# Kör 8 — Legacy adatok tartós V2 migrációja

## Cél

A legacy V1 rekordok egyszeri, biztonságos és visszaállítható migrációja a V2 repositoryba.

## Feladatok

1. Készíts `SongStorageMigrator` use case-t.
2. Migráció előtt olvasd be a teljes legacy listát.
3. Minden dalt külön tranzakciós egységként kezelj.
4. V2 write után olvasd vissza és hasonlítsd parity reporttal.
5. Csak minden rekord sikeres migrációja után jelöld a migration versiont.
6. A legacy storage törlését külön, későbbi cleanup flag vagy release kezelje.
7. Partial failure után a migráció folytatható legyen.
8. Ugyanaz a legacy ID ne jöjjön létre kétszer.
9. Setlist migráció csak a song mapping elkészülése után induljon.
10. Készíts user-visible recovery hibaállapotot.

## Tesztek

- üres legacy storage;
- egy dal;
- több dal;
- partial write failure;
- app restart migráció közben;
- már migrált rekord;
- corrupt rekord;
- setlist missing reference;
- migration version;
- legacy read fallback.

## Elfogadási feltételek

- nincs duplikáció;
- nincs adatvesztés;
- partial failure recoverable;
- a V1 UI feature flaggel visszakapcsolható a rollout alatt;
- migration report diagnosztikailag értelmezhető, érzékeny tartalom nélkül.

## Javasolt commit

```text
feat(song-migration): persist legacy content in the V2 repository
```

---

# Kör 9 — Natív StrumSight JSON import és export

## Cél

A teljes hűségű, offline, verziózott natív dalcsereformátum megvalósítása.

## Feladatok

1. Implementáld a native JSON importert.
2. Implementáld az exportert.
3. Készíts root format és formatVersion ellenőrzést.
4. Implementáld a probe-ot.
5. Validáld a source file size limitet.
6. Hozz létre deterministic JSON outputot.
7. Készíts duplicate source hash warningot.
8. Implementáld az export privacy scrubot.
9. Add hozzá az importer registryhez.
10. Hozz létre export filename sanitizert.
11. Biztosíts cancellation pontokat nagyobb dokumentumnál.
12. Forward-newer schema esetén fail-closed, érthető hiba legyen.

## Kötelező tesztek

- full round-trip;
- empty optional metadata;
- multiple tracks;
- assets manifest;
- invalid root format;
- newer version;
- size limit;
- corrupt JSON;
- duplicate ID;
- privacy mezők hiánya;
- deterministic hash;
- cancellation.

## Elfogadási feltételek

- natív formátum minden V2 domain adatot megőriz;
- export nem tartalmaz abszolút pathot;
- import atomikus;
- format error nem hagy library rekordot;
- fixture snapshot stabil.

## Javasolt commit

```text
feat(song-import): add native StrumSight song import and export
```

---

# Kör 10 — Import application flow és biztonsági keret

## Cél

A parserformátumoktól független import state machine, limitrendszer és preview flow létrehozása.

## Új elemek

```text
lib/features/song_trainer/application/import/
lib/features/song_trainer/data/importers/importer_registry.dart
lib/features/song_trainer/data/importers/import_limits.dart
lib/features/song_trainer/data/importers/import_workspace.dart
```

## Feladatok

1. Implementáld a SongImportControllert explicit state machine-nel.
2. Különítsd el a file pickert adapterbe.
3. Implementáld a probe → preview → import → validate → commit folyamatot.
4. Implementáld a cancellation tokent.
5. Implementáld a temporary workspace lifecycle-t.
6. Implementáld a size és event limiteket.
7. Készíts ImportPreview modellt.
8. Készíts capability és warning mappinget.
9. Parse work isolate-ba tehető legyen.
10. A controller ne tároljon nagy byte arrayt a Riverpod state-ben.
11. Hiba után Retry működjön.
12. App background vagy route leave esetén a policy dokumentált legyen.

## State transition tesztek

- idle → selecting;
- selection cancel;
- selecting → probing;
- probe failure;
- preview;
- import start;
- cancellation;
- validation failure;
- commit failure;
- success;
- retry;
- controller dispose.

## Elfogadási feltételek

- importfolyamat parserfüggetlen;
- nincs félkész repository rekord;
- cancellation takarít;
- nagy byte nincs UI state-ben;
- warning és error elkülönül.

## Javasolt commit

```text
feat(song-import): add secure import orchestration and preview state
```

---

# Kör 11 — MusicXML és MXL importer

## Cél

A támogatott MusicXML subset biztonságos, fixture-alapú importja.

## Feladatok

1. Válassz parser dependencyt licence- és maintenance dokumentációval.
2. Készíts XML parser adaptert data rétegben.
3. Tiltsd az external entityt.
4. Implementáld a MusicXML probe-ot.
5. Parse-old:
   - metadata;
   - parts;
   - measures;
   - divisions;
   - tempo;
   - meter;
   - key;
   - harmony;
   - note/rest;
   - tie;
   - rehearsal marker;
   - lyrics alapadat;
   - string/fret technical adat.
6. Implementáld a part preview-t.
7. Implementáld a rational duration konverziót.
8. Implementáld a korlátozott repeat expansiont.
9. Implementáld az MXL secure extractiont.
10. Készíts warningokat unsupported elemekhez.
11. Parser munka fusson isolate-ban, ha a dependency ezt lehetővé teszi.
12. Készíts normalized snapshot fixtureket.

## Kötelező fixturek

A 15.7 szakaszban felsorolt fixturek mindegyike.

## Security tesztek

- XXE próbálkozás;
- path traversal;
- excessive entries;
- extracted size limit;
- corrupt container.xml;
- invalid root file;
- nested zip vagy unsupported entry.

## Elfogadási feltételek

- egyszerű chord chart importálható;
- monophonic note part importálható;
- 3/4, 4/4 és tempo change megmarad;
- unsupported elem warningot ad;
- malicious MXL nem ír a workspace-en kívül;
- snapshotok stabilak.

## Javasolt commit

```text
feat(song-import): add secure MusicXML and MXL import
```

---

# Kör 12 — Standard MIDI importer

## Cél

Standard MIDI file-ból note-, tempo-, meter- és markertrackek létrehozása.

## Feladatok

1. Válassz MIDI parser megoldást dokumentált licenccel.
2. Implementáld a header és format validációt.
3. Implementáld PPQ timingot.
4. Parse-old a tempo és time signature meta eventeket.
5. Parse-old a track neveket és program change-et.
6. Párosítsd a note on/off eseményeket.
7. Kezeld a velocity 0 note offot.
8. Zárd le warninggal a dangling note-ot.
9. Készíts track preview-t polyphony analízissel.
10. A raw timingot őrizd meg.
11. Quantization csak opcionális importbeállítás legyen.
12. Drum tracket alapértelmezésben ne válassz trainer tracknek.
13. Chord inference ne kerüljön ebbe a körbe.
14. Készíts cancellation és event limitet.

## Kötelező tesztek

- format 0;
- format 1;
- multiple tracks;
- tempo change;
- meter change;
- marker;
- lyric;
- velocity 0;
- running status;
- dangling note;
- overlapping note;
- drum channel;
- extreme PPQ;
- malformed chunk;
- event limit;
- cancellation.

## Elfogadási feltételek

- monophonic track felismerhető;
- polyphonic track warningot kap;
- timing nem kényszerül nyolcadokra;
- note count és duration snapshot tesztelt;
- importer nem omlik össze malformed inputon.

## Javasolt commit

```text
feat(song-import): add Standard MIDI song import
```

---

# Kör 13 — Guitar Pro feasibility és stratégiai döntés

## Cél

Bizonyíték-alapú döntés a közvetlen Guitar Pro támogatásról production kód írása előtt.

## Feladatok

1. Hozd létre a 17.3 szakasz ADR-jét.
2. Vizsgálj legalább három reális megoldást vagy dokumentáld, ha kevesebb létezik.
3. Minden opciónál rögzítsd:
   - licence;
   - supported GP versions;
   - Android/iOS;
   - offline;
   - build size;
   - parser fidelity;
   - security;
   - maintenance;
   - integration effort.
4. Készíts kis technikai spike-ot külön experiment könyvtárban, nem production feature-ben.
5. Tesztelj saját vagy jogtisztán használható technikai fixtureket.
6. Mérd:
   - parse success;
   - track count;
   - tuning;
   - measures;
   - notes;
   - string/fret;
   - tempo;
   - meter.
7. Hozz döntést A, B vagy C opció között.
8. Ha a döntés C, frissítsd a UI copy tervét támogatott konverziós útvonallal.

## Elfogadási feltételek

- nincs production GP parser ADR nélkül;
- licence egyértelmű;
- fixture eredmény dokumentált;
- döntés review-zható;
- elutasított alternatívák indokoltak.

## Javasolt commit

```text
research(song-import): decide Guitar Pro import strategy
```

---

# Kör 14 — Guitar Pro adapter vagy konverziós UX

## Cél

A Kör 13 döntésének végrehajtása.

## A ág — Jóváhagyott parser esetén

1. Készíts izolált GuitarProImporter adaptert.
2. Ne szivárogjon parser package típus a domainbe.
3. Implementáld a támogatott GP verziók probe-ját.
4. Parse-old legalább:
   - metadata;
   - tracks;
   - tuning;
   - capo;
   - tempo;
   - meter;
   - measures;
   - repeats a támogatott subsetben;
   - notes;
   - string/fret;
   - ties;
   - chord text;
   - section markers.
5. A technique jelöléseket őrizd meg display adatként.
6. Unsupported elem warningot adjon.
7. Natív parser esetén worker/crash boundary szükséges.
8. Készíts versioned fixture snapshotokat.

## C ág — Nincs jóváhagyott parser

1. Ne legyen aktív GP file extension a registryben.
2. Import képernyőn jelenjen meg a támogatott MusicXML/MIDI workflow.
3. Készüljön help dokumentáció a felhasználó saját fájljának konvertálásához.
4. Ne linkelj vagy automatizálj jogsértő tartalomforrást.
5. A feature flag és capability maradjon kikapcsolt.
6. Készíts tesztet, hogy GP fájlra érthető unsupported-format válasz érkezik.

## Elfogadási feltételek

- az ADR döntésével egyező működés;
- nincs félkész vagy instabil GP támogatás;
- parseres ágban licence és fixture gate aktív;
- konverziós ágban őszinte UX működik.

## Javasolt commit

```text
feat(song-import): implement approved Guitar Pro import path
```

vagy:

```text
feat(song-import): add safe Guitar Pro conversion guidance
```

---

# Kör 15 — Song Library V2 és import UI

## Cél

A V2 repository és importfolyamat felhasználói felületének elkészítése a trainer nélkül.

## Feladatok

1. Implementáld a SongLibraryControllert.
2. Implementáld a SongQueryt.
3. Készíts indexalapú keresést és szűrést.
4. Implementáld a Song Library V2 képernyőt.
5. Implementáld az import state képernyőt.
6. Implementáld az import preview-t.
7. Implementáld a warning listát.
8. Implementáld a source és capability badge-eket.
9. Implementáld a trash/undo flow-t.
10. Implementáld az export actiont natív formátumra.
11. Feature flag alatt add hozzá az új library navigációt.
12. Legacy és V2 rekord ne jelenjen meg duplán.
13. Hosszú lista lazy legyen.
14. A file picker adapter fake-kel widget tesztelhető legyen.

## Widget tesztek

- empty state;
- legacy migrated song;
- search;
- filters;
- favorites;
- import cancel;
- probe error;
- warning preview;
- fatal preview;
- import success;
- duplicate warning;
- delete/undo;
- missing asset badge;
- large text;
- Hungarian/English.

## Elfogadási feltételek

- library nem decode-ol minden dokumentumot listázáskor;
- import állapot érthető;
- warningok elérhetők;
- nincs duplikált dal;
- accessibility alapok zöldek.

## Javasolt commit

```text
feat(song-ui): add V2 library and secure import experience
```

---

# Kör 16 — Song Editor V2

## Cél

Section-, measure-, chord- és strumközpontú, tiszta állapotkezelésű daleditor létrehozása.

## Feladatok

1. Implementáld a SongEditorControllert.
2. Az editor draft különüljön el a persisted documenttől.
3. Implementáld az EditorCommand modellt.
4. Implementáld az undo/redo stack-et limitált mérettel.
5. Készíts metadata editort.
6. Készíts section editort.
7. Készíts measure gridet.
8. Támogass több chordot measure-en belül.
9. Támogass measure-enként strum pattern-t.
10. Támogass bulk pattern apply műveletet.
11. Támogass tempo és meter marker editort.
12. Készíts basic note event editort.
13. Készíts backing asset attach/detach flow-t.
14. Minden save előtt validáció.
15. Revision conflict esetén ne legyen néma overwrite.
16. Unsaved change route guard.
17. Preview a Song Overview vagy trainer setup felé csak draft snapshotból.
18. A régi Song Builder maradjon feature flag fallbackként.

## Kötelező tesztek

- create new;
- edit existing;
- undo/redo;
- section reorder;
- measure insert/delete;
- two chords per measure;
- meter change;
- pattern apply;
- invalid save;
- revision conflict;
- unsaved back;
- backing asset attach;
- editor dispose;
- legacy song edit → V2 save.

## Elfogadási feltételek

- editor state nem a widgetben él;
- save atomikus;
- invalid dokumentum nem kerül repositoryba;
- undo/redo determinisztikus;
- a scope nem válik teljes kottaszerkesztővé.

## Javasolt commit

```text
feat(song-editor): add structured V2 song editing
```

---

# Kör 17 — Song Overview, track és range kiválasztás

## Cél

A dal megértéséhez és a trainer session konfigurálásához szükséges képernyők létrehozása.

## Feladatok

1. Implementáld a Song Overview képernyőt.
2. Készíts section listát.
3. Készíts track picker komponenst capability információval.
4. Implementáld a TrainerRange választást:
   - full song;
   - section;
   - measure range;
   - bookmark.
5. Implementáld a Trainer Setup képernyőt.
6. A controlok capability szerint jelenjenek meg.
7. Implementáld a speed, count-in, metronome, loop és mode beállításokat.
8. Implementáld a tuning és capo remindert.
9. Implementáld a Resume CTA-t.
10. Implementáld a missing asset javítási flow belépési pontját.
11. Készíts accessibility semanticsot.

## Widget tesztek

- chord-only song;
- strum song;
- monophonic note track;
- polyphonic note track;
- backing asset;
- missing asset;
- section selection;
- measure range validation;
- disabled unsupported mode;
- tuning reminder;
- resume;
- large text.

## Elfogadási feltételek

- a felhasználó érti, mit tud az app pontozni;
- unsupported control nem tűnik aktívnak;
- setup valid konfigurációt ad;
- range nem léphet ki a dalból;
- SongDocument nem módosul setup közben.

## Javasolt commit

```text
feat(song-ui): add song overview and trainer setup
```

---

# Kör 18 — SongTransport és backing playback adapter

## Cél

A determinisztikus transport lifecycle és az opcionális audiolejátszás megvalósítása scoring nélkül.

## Feladatok

1. Implementáld a SongTransport state machine-t.
2. Implementáld a monotonic SongTransportClockot.
3. Implementáld a command és effect feldolgozást.
4. Készíts fake backing player-t.
5. Készíts concrete adaptert a jóváhagyott playback package fölé.
6. Implementáld prepare/play/pause/seek/stop műveleteket.
7. Implementáld a playback capability reportot.
8. Implementáld a grid offsetet.
9. Implementáld a position sample és drift reportot.
10. Implementáld a biztonságos resync policyt.
11. Implementáld app lifecycle pause-t.
12. Implementáld audio route interruptiont.
13. Stop legyen idempotens.
14. Dispose minden streamet felszabadít.
15. Speed változtatás első verzióban csak ready/paused állapotban engedélyezhető.

## Kötelező tesztek

- minden transition;
- invalid transition;
- prepare failure;
- play/pause;
- seek;
- loop boundary alap;
- stop/stop;
- dispose;
- app background;
- route change;
- missing asset;
- unsupported codec;
- rate capability;
- drift threshold;
- fake clock determinism.

## Elfogadási feltételek

- nincs UI vagy scoring a transportban;
- backing adapter cserélhető;
- lifecycle leak nincs;
- drift mérhető;
- unsupported rate őszintén disabled.

## Javasolt commit

```text
feat(song-transport): add deterministic playback and backing sync
```

---

# Kör 19 — SongPracticeCompiler és chord/rhythm trainer

## Cél

A SongDocument targetjeinek Chapter 3 PracticeDefinitionné fordítása és az első teljes Song Trainer session működtetése.

## Feladatok

1. Implementáld a SongPracticeCompilert.
2. Implementáld a source event mappinget.
3. Fordítsd:
   - chord events;
   - strum events;
   - note onset rhythm targeteket.
4. Kezeld a section és range offsetet.
5. Kezeld a tempo mapet.
6. Kezeld a meter mapet.
7. Kezeld a speed multipliert.
8. Kezeld a transpose és capo targeteket.
9. Implementáld a SongTrainerControllert a transport és Practice Engine orchestrációjára.
10. Mikrofon lease csak scoring mode-ban szükséges.
11. Playback-only mód ne kérjen mikrofonengedélyt.
12. Implementáld a count-in és pre-roll sorrendet.
13. Implementáld a PracticeResult → SongTrainerResult mappinget.
14. Készíts measure metrics aggregációt.

## Integration tesztek

- legacy 4/4 song;
- legacy 3/4 song;
- multiple chords per measure;
- section range;
- tempo change;
- meter change;
- direction unknown;
- chord-only;
- rhythm-only;
- playback-only;
- pause/resume;
- seek után új attempt;
- backing + scoring;
- mic denied;
- app background.

## Elfogadási feltételek

- a Song Trainer a Chapter 3 scorert használja;
- nincs duplikált chord/rhythm scorer;
- source event verdict visszakövethető measure-re;
- playback-only mód nem kér micet;
- a legacy dal parity zöld.

## Javasolt commit

```text
feat(song-trainer): compile songs into chord and rhythm practice sessions
```

---

# Kör 20 — Monophonic pitch observation és note scoring

## Cél

Egyhangú note trackek robusztus, őszinte pitch- és onsetértékelése.

## Feladatok

1. Emeld ki a szükséges YIN DSP-t közös core audio API mögé.
2. Ne importáld a Tuner UI/provider fájlokat.
3. Implementáld a PitchObservationGatewayt.
4. Készíts note trainerre hangolt observation configot.
5. Mérd és dokumentáld az observation latencyt.
6. Implementáld a MonophonicNoteScorert.
7. Implementáld:
   - pitch grade;
   - onset timing;
   - duration coverage;
   - missed note;
   - extra note;
   - unstable pitch.
8. Implementáld a latency compensationt.
9. Implementáld a capo és transpose targetet.
10. Polyphonic range esetén tiltsd a scoringot.
11. Integráld a SongTrainerControllerbe külön módon.
12. Készíts note lane live feedbacket minimális UI-val.
13. A thresholdöket fixture benchmark alapján állítsd be.

## Kötelező tesztek

A 22.9 fixturek mellett:

- scorer deterministic replay;
- late observation latency correction;
- no target window;
- rapid repeated note;
- same pitch tie;
- pause/resume;
- seek reset;
- loop new attempt;
- tuning override;
- unsupported polyphony.

## Elfogadási feltételek

- tiszta monophonic riff pontozható;
- beszéd és noise nem válik sorozatos helyes note-tá;
- polyphonic track nem kap hamis pitch score-t;
- threshold és latency dokumentált;
- Tuner regresszió nincs.

## Javasolt commit

```text
feat(song-trainer): add monophonic pitch and note scoring
```

---

# Kör 21 — Song Trainer UI, loop, Speed Builder és eredmény

## Cél

A teljes trainer felület, section loop, A–B loop, heatmap és coaching elkészítése.

## Feladatok

1. Implementáld a Song Trainer screen shellt.
2. Készíts chord lane-t.
3. Készíts strum/rhythm lane-t.
4. Készíts monophonic note lane-t.
5. Készíts kompakt tab lane-t ismert string/fret esetén.
6. Implementáld a transport controlokat.
7. Implementáld a section és measure navigációt.
8. Implementáld A és B loop határ kijelölését.
9. Implementáld loop repeat countot.
10. Integráld a Chapter 3 Speed Builder policyt.
11. Implementáld a non-blocking per-loop feedbacket.
12. Implementáld a Result screent.
13. Készíts measure heatmapet.
14. Implementáld problem range retry-t.
15. Implementáld Continue next sectiont.
16. Implementáld a progress commit idempotenciát.
17. Készíts resume point mentést biztonságos időközönként és pause/stopkor.
18. Performance kritikus lane windowinget használjon.

## Widget és integration tesztek

- count-in;
- playing;
- paused;
- loop 2/5;
- A–B invalid range;
- speed disabled backing capability miatt;
- chord verdict;
- direction verdict;
- note verdict;
- heatmap semantics;
- problem range CTA;
- next section;
- resume;
- repeated commit guard;
- screen reader throttling;
- left-handed visual;
- landscape;
- reduced motion.

## Elfogadási feltételek

- a trainer kis képernyőn használható;
- a lane nem rendereli a teljes dalt egyszerre;
- loop attempt elkülönül;
- heatmap nem csak színnel kommunikál;
- progress egyszer commitálódik;
- pause vagy kilépés után nincs aktív mic/player leak.

## Javasolt commit

```text
feat(song-trainer): add loops speed building results and coaching UI
```

---

# Kör 22 — Setlist V2, progressintegráció és Epic lezárás

## Cél

A Setlist V2, a teljes progress pipeline, CI-gate, dokumentáció és production rollout előkészítése.

## Feladatok

### Setlist V2

1. Implementáld a Setlist repositoryt.
2. Implementáld a V2 modelleket.
3. Migráld a legacy setlisteket.
4. Implementáld a setlist editor UI-t.
5. Implementáld az itemenkénti override-okat.
6. Implementáld a Practice mode sessiont.
7. Implementáld a Performance mode sessiont.
8. Kezeld a missing song/asset itemet.
9. Készíts setlist resultot.

### Progress

10. Implementáld a SongPracticeRecord repositoryt.
11. Implementáld a measure és section aggregációt.
12. Implementáld a revision-aware progress mappinget.
13. Integráld a daily goalt.
14. Integráld a streak eligibility policyt.
15. Integráld a Practice History V2-t.
16. Készíts legacy Learn/Song progress kompatibilitási reportot.

### CI és quality

17. Add hozzá az importer fixture teszteket a CI-hez.
18. Add hozzá a malicious archive/security teszteket.
19. Add hozzá az architecture dependency gate-et.
20. Add hozzá a model schema snapshot gate-et.
21. Add hozzá a repository recovery teszteket.
22. Add hozzá a long-song performance fixture-t.
23. Készíts coverage reportot az új domain/application kódra.
24. Futtass teljes Flutter regressziót.
25. Futtass valós eszközös checklistet.

### Dokumentáció és rollout

26. Frissítsd a README-t.
27. Frissítsd a `docs/sdd/00-index.md` fájlt.
28. Hozd létre:

```text
docs/sdd/epic-03-completion-report.md
```

29. Dokumentáld:
   - támogatott importformátumok;
   - támogatott subset;
   - Guitar Pro döntés;
   - backing codec támogatás;
   - capabilityk;
   - ismert korlátok;
   - security limitek;
   - teljesítménybaseline;
   - migrációs eredmény.
30. A feature flag production bekapcsolása külön release döntés legyen.
31. A legacy kódot csak stabil rollout után, külön cleanup PR-ben töröld.

## Kötelező teljes ellenőrzés

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test
flutter test test/property
dart run tool/check_architecture.dart
```

A parser vagy natív adapter saját ellenőrzéseit külön futtasd.

## Valós eszközös checklist

- legacy migráció;
- natív import;
- MusicXML/MXL import;
- MIDI import;
- GP útvonal az ADR szerint;
- 3/4 és 6/8;
- tempo change;
- section practice;
- A–B loop;
- backing track;
- repeated seek;
- Bluetooth interruption;
- chord/rhythm scoring;
- monophonic pitch scoring;
- Setlist Practice;
- Setlist Performance;
- 20 perces session;
- app background;
- storage recovery.

## Elfogadási feltételek

- minden CI zöld;
- legacy dalok elérhetők;
- nincs SharedPreferences SongDocument tárolás;
- import security gate zöld;
- capabilityk őszinték;
- chord/rhythm trainer működik;
- monophonic note trainer működik;
- polyphonic false scoring nincs;
- setlist dalhatárok megmaradnak;
- progress revision-aware;
- dokumentáció a tényleges implementációt írja le.

## Javasolt commit

```text
docs(song-trainer): close Epic 3 and prepare controlled rollout
```

---

# 34. Epic 3 végső Definition of Done

## Domain és architektúra

- [ ] Létezik SongDocument V2.
- [ ] Minden persisted modell verziózott.
- [ ] A zenei események beat positionben tárolódnak.
- [ ] Tempo map és meter map támogatott.
- [ ] Section, measure és track modell létezik.
- [ ] Chord, strum és note event támogatott.
- [ ] A domain Flutter- és parserfüggetlen.
- [ ] A Song Trainer csak publikus Practice Engine API-t használ.
- [ ] Cross-feature belső import nincs.

## Migráció és storage

- [ ] Minden legacy Song migrálható.
- [ ] A 3/4 legacy működés megmaradt.
- [ ] Minden legacy Setlist migrálható.
- [ ] Duplikált setlist item megmarad.
- [ ] Hiányzó referencia recoverable.
- [ ] SongDocument nem SharedPreferencesben tárolódik.
- [ ] A repository atomikus.
- [ ] Revision conflict kezelt.
- [ ] Asset hash ellenőrzött.
- [ ] Trash és restore működik.
- [ ] Startup recovery tesztelt.

## Import

- [ ] Natív StrumSight JSON round-trip működik.
- [ ] MusicXML import működik a dokumentált subsetben.
- [ ] MXL biztonságosan importálható.
- [ ] MIDI import működik a dokumentált subsetben.
- [ ] Guitar Pro stratégia ADR-ben rögzített.
- [ ] A GP felhasználói út az ADR-rel egyezik.
- [ ] Parser warningok stabil code-dal rendelkeznek.
- [ ] Import megszakítható.
- [ ] Import hiba nem hagy félkész rekordot.
- [ ] ZIP bomb, path traversal és XXE tesztelt.
- [ ] Fixturek jogtiszták és verziózottak.

## Library és editor

- [ ] V2 Song Library működik.
- [ ] Keresés, szűrés és rendezés működik.
- [ ] Importpreview capability reportot mutat.
- [ ] Song Overview működik.
- [ ] Section és track kiválasztható.
- [ ] Song Editor V2 működik.
- [ ] Undo/redo működik.
- [ ] Unsaved change guard működik.
- [ ] Invalid dokumentum nem menthető.

## Transport és playback

- [ ] A SongTransport explicit state machine.
- [ ] Monotonic clockot használ.
- [ ] Pause/resume működik.
- [ ] Seek működik.
- [ ] Section és A–B loop működik.
- [ ] Stop idempotens.
- [ ] Backing audio adapter cserélhető.
- [ ] Playback capability explicit.
- [ ] Grid offset kezelhető.
- [ ] Drift mérhető és kontrollált.
- [ ] Audio interruption safe pause-t okoz.
- [ ] Nincs player vagy stream leak.

## Scoring

- [ ] Chord/rhythm scoring a Chapter 3 motorból érkezik.
- [ ] Direction scoring csak direction target esetén aktív.
- [ ] Chord scoring csak támogatott symbol esetén aktív.
- [ ] Monophonic pitch scoring működik.
- [ ] Pitch latency kompenzált.
- [ ] Duration coverage mérhető.
- [ ] Polyphonic track nem kap hamis pitch score-t.
- [ ] Playback-only mód nem kér mikrofont.
- [ ] Minden verdict source eventre és measure-re mapelhető.

## Gyakorlási élmény

- [ ] Full song gyakorolható.
- [ ] Section gyakorolható.
- [ ] Measure range gyakorolható.
- [ ] A–B loop működik.
- [ ] Speed Builder működik.
- [ ] Count-in és metronóm működik.
- [ ] Backing track opcionális.
- [ ] Capo és transpose kezelve.
- [ ] Tuning reminder működik.
- [ ] Result screen részletes.
- [ ] Measure heatmap hozzáférhető.
- [ ] Problem range retry működik.
- [ ] Resume point működik.

## Setlist és progress

- [ ] Setlist V2 működik.
- [ ] Practice mode működik.
- [ ] Performance mode működik.
- [ ] Item override-ok működnek.
- [ ] Dalok külön resultot kapnak.
- [ ] SongPracticeRecord verziózott.
- [ ] Measure- és section-progress működik.
- [ ] Revision-aware mapping működik.
- [ ] Daily goal integráció működik.
- [ ] Streak eligibility nem számol puszta playbacket.
- [ ] Progress commit idempotens.

## Minőség és biztonság

- [ ] Format gate zöld.
- [ ] Analyze gate zöld.
- [ ] Minden Flutter teszt zöld.
- [ ] Property tesztek zöldek.
- [ ] Import fixture tesztek zöldek.
- [ ] Security fixture tesztek zöldek.
- [ ] Architecture gate zöld.
- [ ] Nincs jogosulatlan teljes kereskedelmi dal fixture.
- [ ] Importált tartalom alapértelmezetten offline marad.
- [ ] Lyrics és source fájl nem kerül logba.
- [ ] Hosszú dal performance baseline elfogadható.
- [ ] Valós eszközös checklist lezárult.

---

# 35. Az Epic eredménye

Az Epic 3 végére a StrumSight rendelkezik egy olyan teljes Song Trainer alrendszerrel, amely:

- megőrzi a jelenlegi saját dalokat és setlisteket;
- strukturált, verziózott SongDocumentet használ;
- képes több zenei idő-, section- és trackstruktúrát kezelni;
- biztonságosan importál támogatott dalfájlokat;
- egyértelműen megmutatja a támogatott és nem támogatott képességeket;
- sectiont, measure-t és A–B tartományt gyakoroltat;
- a Practice Engine segítségével chordot, ritmust és directiont pontoz;
- egyhangú riffeknél pitch scoringot biztosít;
- backing trackkel, count-innal és metronómmal szinkronban működik;
- Speed Buildert és automatikus loopot biztosít;
- measure-szintű fejlődést tárol;
- Setlist Practice és Performance módot kínál;
- offline, adatvédelmi és szerzői jogi szempontból biztonságos alapot ad.

Az Epic lezárása után kezdhető el:

```text
Chapter 5 — Epic 4: AI Guitar Teacher
```
