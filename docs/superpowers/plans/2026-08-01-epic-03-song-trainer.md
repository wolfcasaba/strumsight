# Epic 3 — Song Trainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan one round at a time, with the repository round brief, independent review, and CI checkpoint required before advancing.

**Goal:** A StrumSight jelenlegi dal- és setlistadatait megőrző, verziózott SongDocument V2-re épülő Song Trainer szállítása biztonságos importtal, strukturált szerkesztéssel, determinisztikus transporttal, chord/rhythm és monophonic pitch scoringgal, loop/Speed Builder élménnyel, Setlist V2-vel és revision-aware progresszel.

**Architecture:** Új `song_trainer` feature készül domain → data/application → presentation függési iránnyal. A domain Flutter-, Riverpod-, parser- és platformfüggetlen; az importerek, codec-ek és fájlrendszeres repositoryk a data rétegben, az orchestration az application rétegben, a UI a presentation rétegben él. A trainer kizárólag a Practice feature publikus contractját és a közös core audio/music/storage contractokat használja. Minden kör TDD-ben, külön branchen, külön briefből, merge és friss-main pre-flight után fut.

**Tech Stack:** Flutter/Dart, Riverpod, immutable Dart domain modellek, explicit verziózott JSON codec, fájlrendszeres atomikus tárolás, streamelt import, XML/MXL és MIDI adapterek, közös audio lifecycle, `flutter_test`, property/fixture/widget/integration tesztek, `tools/round-gate.sh`, GitHub Actions full suite/property/APK gate.

---

## 0. A terv státusza és végrehajtási szerződése

- Státusz: `PREPARED`.
- Tervezési baseline: `main` @ `eeb4f6d`, 2026-08-01.
- Normatív termékforrás: `docs/sdd/04-epic-03-song-trainer.md`.
- Jóváhagyott tervdesign: `docs/superpowers/specs/2026-08-01-epic-03-planning-design.md`.
- Körszerződések: `docs/rounds/e03-r01-*.md` … `docs/rounds/e03-r22-*.md`.
- Ez a fájl nem jogosít Epic 3 production módosításra. E03-R01 csak E02-R20 merge-je és a teljes csomag friss-main auditja után indulhat.
- A részletes körbrief engedélyezett fájllistája elsőbbséget élvez a főtervben felsorolt elsődleges fájlokkal szemben. Ha eltérés van, `stopped` jelzés és dokumentált brief-revízió szükséges.
- A planning batch nem foglal ADR-számot az aktív Epic 2 mellett. Az ADR tárgya kötött; az ütközésmentes sorszámot a kör pre-flightja osztja ki, és még `PLANNING` előtt beírja a brief tételes fájllistájába.

## 1. Függőségi gráf és fáziskapuk

```text
E02-R20 merge
    |
    v
R01 -> R02 -> R03 -> R04 -> R05       Domainalapok
                              |
                              v
R06 -> R07 -> R08 -> R09 -> R10       Migráció, storage, natív import
                              |
                              +--> R11 -> R12 -> R13 -> R14
                              |                         Külső formátumok
                              v
R15 -> R16 -> R17 -> R18               Tartalomkezelés és transport
                       |
                       v
R19 -> R20 -> R21 -> R22               Trainer, progress, Epic-zárás
```

Fázison belül és a fázisok között a merge-sorrend lineáris. R14 csak R13 elfogadott ADR-jének egyetlen aktivált ágát hajtja végre. R19 hard gate-je a Practice Engine publikus compiler/result/lifecycle contractjának tényleges elérhetősége; feature-belső Practice importtal ezt tilos megkerülni.

## 2. Kötelező körprotokoll

Minden körnél ugyanaz a végrehajtási ritmus érvényes.

- [ ] **Pre-flight:** frissítsd a teljes klónt `origin/main`-re; igazold a közvetlen elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1, Chapter 3, Chapter 4, `HANDOFF.md`, releváns ADR és `docs/LESSONS.md` részeket.
- [ ] **Contract audit:** `rg`-vel ellenőrizd a brief minden mai útvonalát, típusát, providerét, state producerét, resource ownerét és numeric boundaryjét. Drift esetén írd le a mérést és feloldást a brief `§0.0` részében.
- [ ] **Ready:** oszd ki az esetleges ADR számát, tedd tételessé a fájllistát, állítsd a briefet `PLANNING` státuszra, majd commitold a kör branchére az implementer indítása előtt.
- [ ] **RED:** először a briefben megnevezett legkisebb viselkedési tesztet írd meg; futtasd célzottan, és igazold, hogy a várt okból piros.
- [ ] **GREEN:** csak a teszt átfordításához szükséges legkisebb production változást készítsd el; ne kezd el a következő kört.
- [ ] **REFACTOR:** tartsd meg a réteghatárokat, futtasd újra a célzott tesztet, majd töltsd ki a brief handoffját tényleges kimenettel.
- [ ] **Lokális gate:** egyetlen `tools/round-gate.sh ...` parancs, csővezeték, csonkítás és összeláncolt analyze/test nélkül.
- [ ] **Független review:** a reviewer legalább egy központi invariánst mutációs vagy reference-próbával ellenőriz; BLOCKER/MAJOR nyitva maradásakor nincs merge.
- [ ] **CI:** az orchestrátor indítja a full suite + randomizált property + APK workflow-t a körbranch exact `headSha` értékére; az implementer nem hív `gh`-t.
- [ ] **Merge gate:** csak zöld lokális gate, zöld exact-SHA CI és elfogadott review után merge; ezután indulhat a következő pre-flight.

## 3. Központi contractok

### SongDocument és zenei idő

Az R02–R05 által felépített modell gyökere a Chapter 4 szerződését követi: stabil typed ID, `schemaVersion`, monoton `revision`, UTC timestamp, immutable listák, beat-position események, determinisztikus codec és idempotens normalizer. A `SongTimeMap` egyetlen felelőssége a beat ↔ aktív idő konverzió; UI frame, wall clock és backing player position nem lehet forrása.

### Import és atomikus commit

```text
ImportSourceFile.openRead
  -> format probe
  -> korlátozott temporary workspace
  -> SongImporter
  -> SongNormalizer
  -> SongValidator + SongCapabilityReport
  -> SongRepository/AssetRepository atomikus commit
  -> index update
```

Az import state nem tart teljes byte arrayt. Warning és fatal failure külön contract. Cancel, timeout, parserhiba, validation failure vagy storage failure után nincs library rekord, asset leak vagy bent maradt workspace.

### Practice integráció

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

Minden generált Practice eventhez megmarad a `songId`, `songRevision`, `trackId`, `sourceEventId`, `measureIndex` és opcionális `sectionId`. Chord/rhythm/direction scoringot nem duplikálunk: a Chapter 3 publikus scorer/result contractja fut. Playback-only módban nincs microphone lease.

### Transport és backing

A `SongTransport` tiszta state/effect orchestration, monotonic clockkal. A backing adapter cserélhető; capabilityje explicit. Seek új attemptet vagy scorer resetet hoz létre, stop idempotens, interruption safe pause-t okoz, route leave minden mic/player/stream/timer erőforrást lezár.

### Hibák és perzisztencia

Várt domain/application/data hibák stabil code-dal rendelkező `AppFailure`/`AppResult` úton jutnak a UI-ba. A storage tesztek a production provider-wiringen is mentenek és friss instance-ból visszaolvasnak; a fake siker önmagában nem persistence-bizonyíték. Nyers parser-, IO- és platformexception nem szivároghat ki.

## 4. Fázis I — Domainalapok

### Task 1: E03-R01 — Baseline, boundaries, ADR-témák és feature flag

**Brief:** `docs/rounds/e03-r01-baseline-and-boundaries.md`

**Elsődleges fájlok:** `docs/baseline/epic-03-song-trainer-start.md`, a pre-flightban kiosztott négy ADR-fájl, `lib/app/config/feature_flags.dart`, `lib/features/song_trainer/public.dart`, `test/fixtures/song_trainer/legacy/`, `test/features/song_trainer/baseline/legacy_fixture_parity_test.dart`.

- [ ] Snapshotold a legacy Song/Setlist storage kulcsokat, JSON alakot, 3/4 és 4/4 időzítést, builder/Learn/combine viselkedést és saját/jogtiszta fixtureket.
- [ ] RED: rögzítsd a flag default-off, public-boundary és legacy parity tesztet úgy, hogy a hiányzó scaffolding miatt célzottan bukjon.
- [ ] GREEN: add hozzá kizárólag a default-off `songTrainerV2Enabled` rollout-határt és az üres publikus feature boundaryt; legacy runtime viselkedést ne módosíts.
- [ ] A pre-flight auditálja a `lib/features/practice/public.dart` tényleges exportjait. Hiányzó compiler/result contract esetén bridge-kör vagy R01 brief-revízió kötelező; belső Practice import tilos.
- [ ] Gate: `tools/round-gate.sh test/features/songs test/features/learn/setlist_expected_hint_test.dart test/features/song_trainer/baseline`.
- [ ] Commit: `chore(song-trainer): establish Epic 3 baseline and boundaries`.

### Task 2: E03-R02 — SongDocument identity és metadata

**Brief:** `docs/rounds/e03-r02-song-document-identity-metadata.md`

**Elsődleges fájlok:** `lib/features/song_trainer/domain/models/song_id.dart`, `song_metadata.dart`, `song_source.dart`, `song_document.dart`, `song_asset_reference.dart`, `song_marker.dart`, `lib/features/song_trainer/data/local/song_document_codec.dart`; tesztek: `test/features/song_trainer/domain/song_id_test.dart`, `song_document_test.dart`, `test/features/song_trainer/data/local/song_document_codec_test.dart`.

- [ ] RED: ID üres/hossz/karakter, metadata trim/capo/tag, UTC round-trip, revision/equality és unknown source policy mátrix.
- [ ] GREEN: immutable typed ID-k, minimális üres-listás document skeleton, explicit determinisztikus JSON codec, safe filename mapping és UTC ISO-8601 perzisztencia.
- [ ] Architektúra-próba: a domain transitív importgráfjában nincs Flutter, Riverpod, platform API vagy más feature.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/domain/song_id_test.dart test/features/song_trainer/domain/song_document_test.dart test/features/song_trainer/domain/song_document_codec_test.dart`.
- [ ] Commit: `feat(song-domain): add versioned SongDocument identity and metadata`.

### Task 3: E03-R03 — Struktúra és determinisztikus SongTimeMap

**Brief:** `docs/rounds/e03-r03-song-structure-and-time-map.md`

**Elsődleges fájlok:** `song_section.dart`, `song_measure.dart`, `tempo_map.dart`, `meter_map.dart`, `key_map.dart`, `domain/services/song_time_map.dart`; `test/features/song_trainer/domain/song_structure_test.dart`, `song_time_map_test.dart`, `test/property/song_time_map_property_test.dart`.

- [ ] RED: section/range/pickup invalid cellák, 3/4–4/4–6/8, tempo/meter boundary, valamint beat→time→beat és monotonic property tesztek.
- [ ] A speed-mátrix legalább `{0.5, 1.0, 2.0}` értékeket és a tempo-boundary előtte/pontosan rajta/utána cellákat tartalmazza; a várt értékeket géppel számítsd ki.
- [ ] GREEN: rational/integer köztes reprezentációval építsd meg a mapet; speed nem módosíthat source adatot, pickup nem kaphat teljes measure durationt.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/domain/song_structure_test.dart test/features/song_trainer/domain/song_time_map_test.dart test/property/song_time_map_property_test.dart`.
- [ ] Commit: `feat(song-domain): add song structure and deterministic time maps`.

### Task 4: E03-R04 — Trackek, események és monophonic elemzés

**Brief:** `docs/rounds/e03-r04-tracks-events-monophonic-analysis.md`

**Elsődleges fájlok:** `lib/features/song_trainer/domain/models/song_track.dart`, `song_event.dart`, `song_instrument.dart`, `song_note_technique.dart`, `backing_audio_track.dart`, `domain/services/note_track_analyzer.dart`; `test/features/song_trainer/domain/song_track_codec_test.dart`, `note_track_analyzer_test.dart`.

- [ ] RED: minden track/event codec, unknown direction/technique, pitch/string/fret, tie, overlap, immutable list és stable sort kombinációk.
- [ ] GREEN: sealed track/event hierarchia, display-only versus scoring-relevant adat, backingben kizárólag asset ID, determinisztikus monophonic report.
- [ ] A stable sorrend kulcsa start → track → ID; az input-lista mutálása és az overlap önkényes hangválasztása nem elfogadható.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/domain/song_track_codec_test.dart test/features/song_trainer/domain/note_track_analyzer_test.dart`.
- [ ] Commit: `feat(song-domain): add structured tracks events and note analysis`.

### Task 5: E03-R05 — Validator, normalizer és capability resolver

**Brief:** `docs/rounds/e03-r05-validator-normalizer-capabilities.md`

**Elsődleges fájlok:** `domain/services/song_validator.dart`, `song_normalizer.dart`, `song_capability_resolver.dart`, `domain/models/song_validation_report.dart`, `song_capability.dart`, `import_warning.dart`; tesztek és propertyk azonos nevű fájlokban a `test/features/song_trainer/domain/` és `test/property/` alatt.

- [ ] RED: profile × severity, fatal persist tiltás, display/scoring capability, polyphony, stable warning code és normalize-twice property.
- [ ] GREEN: sorting, duplicate tempo collapse, Full song section, chord normalize, biztos tie merge és kizárólag hiányzó import ID-k generálása.
- [ ] Unknown input kontrollált reportot ad; bizonytalan zenei jelentést a normalizer nem javíthat némán.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/domain/song_validator_test.dart test/features/song_trainer/domain/song_normalizer_test.dart test/features/song_trainer/domain/song_capability_resolver_test.dart test/property/song_normalizer_property_test.dart`.
- [ ] Commit: `feat(song-domain): validate normalize and classify trainer capabilities`.

## 5. Fázis II — Migráció, storage és natív import

### Task 6: E03-R06 — Legacy Song/Setlist adapterek

**Brief:** `docs/rounds/e03-r06-legacy-song-setlist-adapters.md`

**Elsődleges fájlok:** `lib/features/song_trainer/data/migration/legacy_song_reader.dart`, `legacy_song_adapter.dart`, `legacy_setlist_adapter.dart`, `legacy_migration_report.dart`; `test/features/song_trainer/data/migration/legacy_song_adapter_test.dart`, `legacy_setlist_adapter_test.dart`, `legacy_parity_test.dart`.

- [ ] RED: fixture-mátrix 4/4, 3/4, rest, több chord, corrupt pattern, eltérő BPM, duplikált setlist item és hiányzó song ID esetekkel.
- [ ] GREEN: kicsi legacy DTO/codec boundary; teljes-measure chord, measure-enként pattern, beat-0 tempo/meter, Full song section, megőrzött ID és `legacyLocal` source.
- [ ] Ismételt adapterhívás determinisztikus; ebben a körben nincs legacy delete és nincs persistent migráció.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/data/migration test/features/songs test/features/learn/setlist_expected_hint_test.dart`.
- [ ] Commit: `feat(song-migration): adapt legacy songs and setlists to V2`.

### Task 7: E03-R07 — Song repository és asset store

**Brief:** `docs/rounds/e03-r07-song-repository-asset-store.md`

**Elsődleges fájlok:** `lib/features/song_trainer/domain/repositories/song_repository.dart`, `song_asset_repository.dart`, `lib/features/song_trainer/data/local/file_song_repository.dart`, `file_song_asset_repository.dart`, `song_index_codec.dart`, `atomic_file_writer.dart`, `song_repository_recovery.dart`; tesztek: `test/features/song_trainer/data/local/`.

- [ ] RED: create/read/update, stale revision, minden atomic write fázisban crash, corrupt/missing index/document, hash mismatch, dedupe, trash/restore/delete és orphan recovery.
- [ ] GREEN: injektált platform directory, streamelt SHA-256 asset copy, temp→flush→decode-check→rename→index temp→rename sorrend.
- [ ] Production-wiring teszt friss repository instance-ból visszaolvas; reális storage exceptiont alakít stabil failure code-dá. Korábbi jó dokumentum hiba után olvasható marad.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/data/local`.
- [ ] Commit: `feat(song-storage): add atomic document and asset repositories`.

### Task 8: E03-R08 — Tartós V2 migráció

**Brief:** `docs/rounds/e03-r08-persistent-v2-migration.md`

**Elsődleges fájlok:** `lib/features/song_trainer/application/migration/song_storage_migrator.dart`, `song_migration_state.dart`, `lib/features/song_trainer/data/migration/song_migration_version_store.dart`, `lib/features/song_trainer/application/song_trainer_providers.dart`; `test/features/song_trainer/application/migration/song_storage_migrator_test.dart`, `song_storage_migrator_wiring_test.dart`.

- [ ] RED: üres/egy/több/corrupt rekord, N-edik write failure, restart minden checkpointnál, már migrált ID, setlist missing reference, version és legacy fallback.
- [ ] GREEN: rekord-szintű újraindítható tranzakció, write-back/read-back parity, version marker csak teljes siker után, setlist csak teljes song mapping után.
- [ ] A legacy storage törlése tilos; user-visible recovery state nem tartalmaz dalcímet, lyricset vagy nyers rekordot diagnosztikai logban.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/application/migration test/features/song_trainer/data/migration test/features/songs`.
- [ ] Commit: `feat(song-migration): persist legacy content in the V2 repository`.

### Task 9: E03-R09 — Natív StrumSight JSON

**Brief:** `docs/rounds/e03-r09-native-json-import-export.md`

**Elsődleges fájlok:** `lib/features/song_trainer/data/importers/native_json_importer.dart`, `native_json_exporter.dart`, `lib/features/song_trainer/data/local/song_document_codec.dart`, `lib/features/song_trainer/data/importers/export_filename_sanitizer.dart`, `song_importer.dart`; `test/features/song_trainer/data/importers/native_json_importer_test.dart`, `native_json_exporter_test.dart`, `test/fixtures/song_trainer/native/`.

- [ ] RED: full round-trip, optional metadata, több track, assets manifest, corrupt/root/version/size/duplicate/cancel, privacy scrub és deterministic bytes/hash.
- [ ] GREEN: `.strumsight-song.json`, root format/version probe, streamelt limit, fail-closed newer schema, sanitized export név és source-hash warning.
- [ ] Az importer eredménye még nem tehet félkész rekordot a librarybe; abszolút path és személyes import metadata nem jelenhet meg exportban.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/data/importers/native_json_importer_test.dart test/features/song_trainer/data/importers/native_json_exporter_test.dart`.
- [ ] Commit: `feat(song-import): add native StrumSight song import and export`.

### Task 10: E03-R10 — Import flow és security boundary

**Brief:** `docs/rounds/e03-r10-import-flow-security-boundary.md`

**Elsődleges fájlok:** `lib/features/song_trainer/application/import/song_import_controller.dart`, `song_import_state.dart`, `song_import_effect.dart`, `import_preview.dart`, `cancellation_token.dart`, `lib/features/song_trainer/data/importers/importer_registry.dart`, `import_limits.dart`, `import_workspace.dart`, `file_picker_adapter.dart`; `test/features/song_trainer/application/import/`, `test/features/song_trainer/data/importers/import_workspace_test.dart`.

- [ ] RED: minden state transition és state+effect kombináció: selection cancel, probe/import/validation/commit failure, cancel minden szakaszban, retry, route leave, dispose és duplicate terminal callback.
- [ ] GREEN: explicit reducer/controller, adapterezett picker, limitált workspace, streamelt input, cancel-aware probe→preview→parse→validate→commit pipeline.
- [ ] A repository record csak az atomikus terminal commitnál jelenik meg. Nagy bytes, parser object és platform picker type nem kerül Riverpod state-be.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/application/import test/features/song_trainer/data/importers/import_workspace_test.dart`.
- [ ] Commit: `feat(song-import): add secure import orchestration and preview state`.

## 6. Fázis III — Külső formátumok

### Task 11: E03-R11 — MusicXML/MXL importer

**Brief:** `docs/rounds/e03-r11-musicxml-mxl-importer.md`

**Elsődleges fájlok:** `pubspec.yaml`, `pubspec.lock`, `lib/features/song_trainer/data/importers/musicxml_importer.dart`, `musicxml_parser_adapter.dart`, `musicxml_mapper.dart`, `musicxml_repeat_expander.dart`, `mxl_importer.dart`, `mxl_archive_reader.dart`; `test/features/song_trainer/data/importers/musicxml_importer_test.dart`, `mxl_security_test.dart`, `test/fixtures/song_trainer/musicxml/` és `test/fixtures/song_trainer/mxl/`.

- [ ] Pre-flight licence/maintenance/security döntés után rögzítsd a parser dependencyt; jogtiszta fixture nélkül a kör nem Ready.
- [ ] RED: a Chapter 4 §15.7 teljes fixture-listája, divisions/tuplet/dotted/tie/repeat snapshot, XXE, traversal, entry count, extracted bytes, corrupt container/root és nested archive.
- [ ] GREEN: parser-package típusokat bezáró adapter, external entity tiltás, rational duration, limitált repeat expansion és workspace-en belüli MXL extraction.
- [ ] Unsupported elem stabil warning; extension/content mismatch nem néma siker. Snapshot a normalizált SongDocumentet méri.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/data/importers/musicxml`.
- [ ] Commit: `feat(song-import): add secure MusicXML and MXL import`.

### Task 12: E03-R12 — Standard MIDI importer

**Brief:** `docs/rounds/e03-r12-midi-importer.md`

**Elsődleges fájlok:** szükség esetén `pubspec.yaml` és `pubspec.lock`, `lib/features/song_trainer/data/importers/midi_importer.dart`, `midi_parser_adapter.dart`, `midi_timeline_mapper.dart`, `midi_track_preview.dart`; `test/features/song_trainer/data/importers/midi_importer_test.dart`, `midi_malformed_test.dart`, `test/fixtures/song_trainer/midi/`.

- [ ] RED: format 0/1, PPQ szélek, tempo/meter/marker/lyric, running status, velocity-0 off, dangling/overlap, drum, malformed chunk, event limit és cancellation.
- [ ] GREEN: raw timing megőrzése, note-on/off pairing, track preview + polyphony report; quantization csak explicit option, drum nem default trainer track.
- [ ] Chord inference és SMPTE timing nincs ebben a körben. Malformed input stabil failure, dangling note stabil warning.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/data/importers/midi`.
- [ ] Commit: `feat(song-import): add Standard MIDI song import`.

### Task 13: E03-R13 — Guitar Pro feasibility

**Brief:** `docs/rounds/e03-r13-guitar-pro-feasibility.md`

**Elsődleges fájlok:** a pre-flightban kiosztott Guitar Pro strategy ADR, `tool/guitar_pro_feasibility/pubspec.yaml`, `bin/run_spike.dart`, `lib/gp_spike.dart`, `test/gp_spike_test.dart`, `test/fixtures/song_trainer/guitar_pro/README.md`, `docs/research/epic-03-guitar-pro-feasibility.md`.

- [ ] Legalább három reális megoldást hasonlíts össze licence, GP-verzió, Android/iOS, offline, build size, fidelity, security, maintenance és effort alapján; ha három nem létezik, a keresési bizonyítékot dokumentáld.
- [ ] A spike kizárólag `tool/guitar_pro_feasibility/` alatt fut, saját/jogtiszta technikai fixturekkel; production registryt és `lib/features/song_trainer/` kódot nem módosít.
- [ ] Mérd parse success, track, tuning, measure, note, string/fret, tempo és meter fidelityt; válassz A, B vagy C stratégiát és indokold az elutasított alternatívákat.
- [ ] Gate: a briefben rögzített reprodukálható spike-parancs plusz `tools/round-gate.sh test/features/song_trainer/data/importers` az érintetlenségi regresszióra.
- [ ] Commit: `research(song-import): decide Guitar Pro import strategy`.

### Task 14: E03-R14 — Jóváhagyott GP út

**Brief:** `docs/rounds/e03-r14-guitar-pro-path.md`

**Aktiválás:** a pre-flight az R13 ADR alapján pontosan egy ágat hagy a `PLANNING` brief scope-jában; a másik ágat és fájljait explicit tilos zónává teszi.

**A ág elsődleges fájlok:** dependency esetén `pubspec.yaml`/`pubspec.lock`, `lib/features/song_trainer/data/importers/guitar_pro_importer.dart`, `guitar_pro_parser_adapter.dart`, `guitar_pro_mapper.dart`, registry és versioned fixture tesztek.

**C ág elsődleges fájlok:** `lib/features/song_trainer/presentation/screens/song_import_screen.dart`, `presentation/widgets/guitar_pro_conversion_guidance.dart`, importer-registry unsupported response, `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`, `docs/user-guide/guitar-pro-conversion.md` és widget/registry tesztjeik.

- [ ] RED az aktív ágra: parsernél verzió/fidelity/warning/crash-boundary; conversion UX-nél GP nincs aktív extensionként, stabil unsupported választ és MusicXML/MIDI útmutatást ad.
- [ ] GREEN kizárólag az ADR által jóváhagyott ágon; parser package/natív típus nem lép át a data boundaryn, C ág nem állít közvetlen támogatást.
- [ ] Gate A: `tools/round-gate.sh test/features/song_trainer/data/importers/guitar_pro`; Gate C: `tools/round-gate.sh test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart`.
- [ ] Commit A: `feat(song-import): implement approved Guitar Pro import path`; Commit C: `feat(song-import): add safe Guitar Pro conversion guidance`.

## 7. Fázis IV — Tartalomkezelés és transport

### Task 15: E03-R15 — Song Library V2 és import UI

**Brief:** `docs/rounds/e03-r15-song-library-import-ui.md`

**Elsődleges fájlok:** `lib/features/song_trainer/application/library/song_library_controller.dart`, `song_library_state.dart`, `song_query.dart`, `presentation/screens/song_library_screen.dart`, `song_import_screen.dart`, `song_import_preview_screen.dart`, `presentation/widgets/song_summary_tile.dart`, `song_capability_badges.dart`, `import_warning_list.dart`, routing/flag/l10n fájlok; tesztek: `test/features/song_trainer/application/library/song_library_controller_test.dart`, valamint a három screen azonos nevű tesztje a `test/features/song_trainer/presentation/` alatt.

- [ ] RED: empty/loading/error, migrated legacy, search/filter/favorite, cancel/probe/fatal/warning/success/duplicate, trash+undo, missing asset, HU/EN, large text és re-entry.
- [ ] GREEN: indexalapú lazy listázás, fake picker, capability/source badge, natív export action és flagelt route. Listázás nem decode-olja az összes documentet.
- [ ] Legacy és V2 azonos logikai dal deduplikált; warning elérhető, fatal preview nem enged commitot; kombinált badge+error cellák külön teszteltek.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/application/library test/features/song_trainer/presentation/library test/features/song_trainer/presentation/import test/app/routing`.
- [ ] Commit: `feat(song-ui): add V2 library and secure import experience`.

### Task 16: E03-R16 — Song Editor V2

**Brief:** `docs/rounds/e03-r16-song-editor-v2.md`

**Elsődleges fájlok:** `lib/features/song_trainer/application/editor/song_editor_controller.dart`, `song_editor_state.dart`, `editor_command.dart`, `editor_history.dart`, `presentation/screens/song_editor_screen.dart`, metadata/section/measure/event/backing editor widgetek, route guard és l10n; tesztek: `test/features/song_trainer/application/editor/`, `test/features/song_trainer/presentation/song_editor_screen_test.dart`, `song_editor_route_guard_test.dart`.

- [ ] RED: create/edit, deterministic undo/redo és history limit, section reorder, measure insert/delete, két chord, meter marker, pattern bulk apply, invalid save, revision conflict, unsaved route, backing attach, dispose és legacy→V2 save.
- [ ] GREEN: persisted documenttől külön immutable draft, command-alapú history, save előtti validate és expectedRevision update, draft-snapshot preview.
- [ ] Conflict nem ír felül némán, route guard nem veszít draftot, attach failure nem hagy asset reference-et. A scope nem teljes kottaszerkesztő.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/application/editor test/features/song_trainer/presentation/editor test/app/routing/route_guards_test.dart`.
- [ ] Commit: `feat(song-editor): add structured V2 song editing`.

### Task 17: E03-R17 — Overview, track/range és setup

**Brief:** `docs/rounds/e03-r17-overview-track-range-setup.md`

**Elsődleges fájlok:** `lib/features/song_trainer/domain/models/trainer_range.dart`, `trainer_config.dart`, `application/trainer/song_trainer_setup_controller.dart`, `song_trainer_setup_state.dart`, `presentation/screens/song_overview_screen.dart`, `trainer_setup_screen.dart`, `presentation/widgets/song_section_list.dart`, `song_track_picker.dart` és capability/tuning widgetek; tesztek: `test/features/song_trainer/domain/trainer_range_test.dart`, `test/features/song_trainer/application/trainer/song_trainer_setup_controller_test.dart`, `test/features/song_trainer/presentation/trainer_setup_screen_test.dart`.

- [ ] RED: chord/strum/mono/polyphonic/backing/missing asset capability-mátrix, full/section/measure/bookmark range, invalid bounds, tuning/capo, resume és nagy szöveg.
- [ ] GREEN: capabilityből származtatott control enablement, immutable setup config, speed/count-in/metronome/loop/mode beállítás és repair belépési pont.
- [ ] Unsupported control látható magyarázattal disabled; setup nem módosít SongDocumentet és range nem lép ki a dalból.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/domain/trainer_range_test.dart test/features/song_trainer/application/trainer/song_trainer_setup_controller_test.dart test/features/song_trainer/presentation/trainer_setup_screen_test.dart`.
- [ ] Commit: `feat(song-ui): add song overview and trainer setup`.

### Task 18: E03-R18 — SongTransport és backing playback

**Brief:** `docs/rounds/e03-r18-transport-backing-playback.md`

**Elsődleges fájlok:** `lib/features/song_trainer/application/trainer/song_transport.dart`, `song_transport_state.dart`, `song_transport_command.dart`, `transport_effect.dart`, `song_transport_clock.dart`, `lib/features/song_trainer/data/playback/backing_audio_player.dart`, `playback_capabilities.dart`, `local_backing_audio_player.dart`; tesztek: `test/features/song_trainer/application/trainer/song_transport_test.dart`, `test/features/song_trainer/data/playback/`.

- [ ] RED: teljes engedélyezett `(előző, új)` transition-pártábla, minden tiltott pár, chained state path, prepare/play/pause/seek/stop-stop/dispose, background/route, asset/codec/rate failure és fake-clock determinism.
- [ ] RED benchmarkból származtatott drift-mátrix: szigorúan küszöb alatt, pontosan rajta, fölötte; a származtatott drift értéke külön oszlop.
- [ ] GREEN: tiszta reducer/effect, monotonic anchor, explicit backing capability, grid offset, safe resync és ready/paused-only speed változtatás.
- [ ] Nincs UI/scoring a transportban; minden terminal ág lezárja a subscriptiont/playert/timert, interruption után nincs automatikus hangos resume.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/application/trainer/song_transport_test.dart test/features/song_trainer/data/playback`.
- [ ] Commit: `feat(song-transport): add deterministic playback and backing sync`.

## 8. Fázis V — Trainer, progress és Epic-zárás

### Task 19: E03-R19 — Practice compiler és chord/rhythm session

**Brief:** `docs/rounds/e03-r19-practice-compiler-chord-rhythm.md`

**Elsődleges fájlok:** szükség esetén kizárólag audit után `lib/features/practice/public.dart`, továbbá `lib/features/song_trainer/domain/services/song_practice_compiler.dart`, `lib/features/song_trainer/domain/models/song_event_reference.dart`, `song_trainer_result.dart`, `lib/features/song_trainer/application/trainer/song_trainer_controller.dart`, `song_trainer_state.dart`, `song_result_mapper.dart`; tesztek: `test/features/song_trainer/domain/song_practice_compiler_test.dart`, `test/features/song_trainer/application/trainer/song_trainer_controller_test.dart`, `song_trainer_integration_test.dart`.

- [ ] Hard pre-flight: bizonyítsd, hogy a PracticeDefinition, szükséges target/scoring config, session orchestration és PracticeResult publikus contractként elérhető. Ha nem, a kör megáll és public bridge-revízió készül.
- [ ] RED: 4/4/3/4, több chord, section offset, tempo/meter change, unknown direction, chord/rhythm/playback-only, pause/resume, seek új attempt, backing+scoring, mic denied és background.
- [ ] GREEN: determinisztikus range-local compile, source mapping, speed/transpose/capo, count-in/pre-roll, publikus Practice Engine futtatás és measure/section result mapping.
- [ ] Belső Practice import és duplikált scorer tilos. Microphone lease csak scoring mode-ban; playback-only permission prompt nem elfogadható.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/domain/song_practice_compiler_test.dart test/features/song_trainer/application/trainer test/features/practice`.
- [ ] Commit: `feat(song-trainer): compile songs into chord and rhythm practice sessions`.

### Task 20: E03-R20 — Pitch observation és monophonic note scoring

**Brief:** `docs/rounds/e03-r20-pitch-observation-note-scoring.md`

**Elsődleges fájlok:** `lib/core/audio/pitch/pitch_observation.dart`, `pitch_observation_config.dart`, `pitch_observation_gateway.dart`, `lib/core/audio/dsp/yin_pitch_detector.dart`, `lib/features/song_trainer/domain/services/monophonic_note_scorer.dart`, `domain/models/note_scoring_models.dart`, `lib/features/song_trainer/data/audio/live_pitch_observation_gateway.dart`, trainer controller és minimális note lane; tesztek: `test/core/audio/dsp/`, `test/features/tuner/`, `test/features/song_trainer/domain/monophonic_note_scorer_test.dart`, `test/features/song_trainer/data/audio/`, `test/fixtures/audio/song_trainer/`.

- [ ] Pre-flight benchmarkkal mérd observation latencyt és fixture-disztribúciót; benchmark és ADR/revízió nélkül nincs threshold- vagy közös YIN-viselkedés változtatás.
- [ ] RED: tiszta E2/A2/E4, kromatikus riff, early/late, félhang/oktáv, rövid/vibrato/bend/noise/speech/silence/polyphony, Drop D/capo, deterministic replay, seek/pause/loop reset.
- [ ] A cent/latency/coverage küszöbmátrix mindegyikénél alatta/rajta/fölötte származtatott cellák kellenek; tuner regresszió külön gate.
- [ ] GREEN: közös audio boundary, lease-elt gateway, latency-compensated tiszta scorer, written→sounding pitch szabály és polyphonic hard disable.
- [ ] Gate: `tools/round-gate.sh test/core/audio/dsp test/features/tuner test/features/song_trainer/domain/scoring test/features/song_trainer/data/audio`.
- [ ] Commit: `feat(song-trainer): add monophonic pitch and note scoring`.

### Task 21: E03-R21 — Trainer UI, loop, Speed Builder és result

**Brief:** `docs/rounds/e03-r21-trainer-ui-loop-speed-results.md`

**Elsődleges fájlok:** `lib/features/song_trainer/domain/models/loop_config.dart`, `application/trainer/song_progress_committer.dart`, `song_resume_repository.dart`, `presentation/screens/song_trainer_screen.dart`, `song_result_screen.dart`, `presentation/widgets/chord_lane.dart`, `strum_lane.dart`, `note_lane.dart`, `tablature_lane.dart`, `transport_controls.dart`, `loop_controls.dart`, `measure_heatmap.dart`, route/l10n fájlok; tesztek: `test/features/song_trainer/presentation/trainer/`, `test/features/song_trainer/application/trainer/song_progress_committer_test.dart`, lifecycle integration teszt.

- [ ] RED: count-in/playing/paused, loop index, invalid A–B, backing-rate-disabled, minden verdict lane, heatmap semantics, problem retry, next section, resume, repeated terminal callback, reader throttling, left-handed, landscape, reduced motion és large text.
- [ ] GREEN: windowolt lane-ok, section/measure/A–B navigation, elkülönített loop attempt, publikus Speed Builder policy, non-blocking feedback, idempotency-keyes progress commit és safe resume checkpoint.
- [ ] Heatmap nem csak szín; re-entry után state helyes; pause/route leave/dispose után nincs mic/player/subscription. Teljes dalt egyszerre renderelni tilos.
- [ ] Gate: `tools/round-gate.sh test/features/song_trainer/presentation/trainer test/features/song_trainer/application/trainer test/features/song_trainer/integration`.
- [ ] Commit: `feat(song-trainer): add loops speed building results and coaching UI`.

### Task 22: E03-R22 — Setlist V2, progress és Epic closure

**Brief:** `docs/rounds/e03-r22-setlist-progress-epic-closure.md`

**Elsődleges fájlok:** `lib/features/song_trainer/domain/models/song_setlist.dart`, `song_practice_record.dart`, repository contractok; `lib/features/song_trainer/application/setlists/`, `application/progress/`, `data/local/file_setlist_repository.dart`, `file_song_progress_repository.dart`, `presentation/screens/setlist_list_screen_v2.dart`, `setlist_session_screen.dart`, Practice History integration; CI/architecture/schema/performance tesztek; `README.md`, `docs/sdd/00-index.md`, `docs/sdd/epic-03-completion-report.md`, RTM/HANDOFF a kör lezárási protokollja szerint.

- [ ] RED: legacy setlist migration, duplicate/missing song, item override, Practice/Performance boundaries, per-song result, revision mapping, daily goal/streak eligibility és duplicate progress callback.
- [ ] GREEN: verziózott Setlist V2 + repository/editor/session, versioned SongPracticeRecord, measure/section aggregate, revision-aware mapping és idempotens production-wired progress persistence.
- [ ] Add hozzá az importer/security/architecture/schema/recovery/long-song gate-eket; mérd a teljesítménybaseline-t és coverage-et a tényleges kódon.
- [ ] Futtasd a teljes lokális gate-et: `tools/round-gate.sh test/features/song_trainer test/features/songs test/features/practice test/property test/integration`.
- [ ] Az orchestrátor exact-SHA CI-ja mellett hajtsd végre a Chapter 4 R22 teljes valós-eszközös checklistjét. Szintetikus teszt nem jelölheti ezt késznek; hiányzó device bizonyíték release blocker.
- [ ] A completion report csak mért támogatást, subsetet, GP döntést, codecet, limitet, migrációt és ismert korlátot állíthat. Feature flag production enable külön release-döntés; legacy delete külön későbbi cleanup PR.
- [ ] Commit: `docs(song-trainer): close Epic 3 and prepare controlled rollout`.

## 9. Epic 3 DoD traceability

| DoD-terület | Elsődleges körök | Kötelező bizonyíték |
|---|---|---|
| SongDocument, beat-time, track/event, pure domain | R02–R05 | domain unit + codec snapshot + property + architecture gate |
| Legacy Song/Setlist parity | R01, R06, R08, R22 | jogtiszta fixture parity + restart/migration integration |
| Atomic repository, asset, revision, recovery | R07–R08 | crash-point mátrix + real provider re-open + recovery fixture |
| Natív JSON | R09–R10 | deterministic byte/hash round-trip + cancel/no-partial-record |
| MusicXML/MXL | R11 | teljes subset snapshot + XXE/traversal/zip-limit security |
| MIDI | R12 | format/timing/event fixture snapshot + malformed/limit/cancel |
| Guitar Pro út | R13–R14 | elfogadott ADR + spike/fidelity vagy unsupported conversion UX |
| Library/editor/overview/setup | R15–R17 | controller + widget + re-entry + a11y/l10n kombinációs teszt |
| Transport/backing | R18 | transition-pártábla + fake clock + lifecycle + device audio |
| Chord/rhythm integration | R19 | compiler/source-map property + Practice integration + no-mic playback |
| Monophonic pitch | R20 | benchmarkolt audio fixture + boundary matrix + tuner regression + device |
| Loop/Speed Builder/result/resume | R21 | widget/integration + idempotent commit + leak/lifecycle |
| Setlist/progress | R22 | migration + per-song boundary + revision-aware production persistence |
| Security/privacy/copyright | R09–R14, R22 | malicious fixture + log/redaction audit + fixture provenance |
| Performance és teljes rollout readiness | R15, R18, R21, R22 | long-song baseline + exact-SHA CI/APK + valós-eszközös checklist |

## 10. Indítási és lezárási STOP-feltételek

Az adott kör nem indul vagy azonnal megáll, ha az elődkör nincs merge-elve, a branch baseline nem friss, a brief nincs pre-flightolva/commitolva, szükséges public contract vagy jogtiszta fixture hiányzik, az engedélyezett fájllista nem fedi az acceptance-et, ADR-döntés nincs meg, security/resource owner nem azonosítható, vagy a teszt nem tudja a hibás implementációt megkülönböztetni.

Az Epic nem zárható le pusztán zöld unit tesztekkel. Szükséges a 22 elfogadott körreview, exact-SHA CI evidence, teljes DoD traceability, tényleges dokumentáció, migráció/recovery bizonyíték, security suite, teljesítménybaseline és a valós-eszközös checklist. Minden nem futtatott release-kritikus ellenőrzés név szerinti blocker, nem implicit siker.
