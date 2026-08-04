# Epic 3 — Song Trainer completion evidence

**Állapot:** implementációs evidence rögzítve az E03-R22 branch-en; ez nem
release approval. A production feature flag, a Setlist-route, a független
review, az exact-SHA CI/APK és a valódi eszközös ellenőrzés még nyitott.

## Ténylegesen támogatott helyi importút

| Formátum | Mért határ | Evidence |
| --- | --- | --- |
| StrumSight JSON | A verziózott native envelope exportálható/importálható a saját codec fölött. | [`native_json_exporter.dart`](../../lib/features/song_trainer/data/importers/native_json_exporter.dart), [`native_json_importer.dart`](../../lib/features/song_trainer/data/importers/native_json_importer.dart), [ADR 0118](../adr/0118-native-json-exchange-contract.md) |
| MusicXML | A dokumentált, fail-closed MusicXML subset kerül a production importer-registrybe; nem minden MusicXML jelölés állítható vissza. | [`musicxml_importer.dart`](../../lib/features/song_trainer/data/importers/musicxml_importer.dart), [ADR 0120](../adr/0120-musicxml-mxl-import-boundary.md) |
| MXL | A MusicXML út archive-változata; a közös archive-entry és extracted-byte policy védi. | [`mxl_importer.dart`](../../lib/features/song_trainer/data/importers/mxl_importer.dart), [`import_limits.dart`](../../lib/features/song_trainer/data/importers/import_limits.dart), [ADR 0120](../adr/0120-musicxml-mxl-import-boundary.md) |
| MIDI | Csak SMF 0/1, PPQ division; SMPTE, chord inference és MIDI playback nem támogatott. | [`midi_importer.dart`](../../lib/features/song_trainer/data/importers/midi_importer.dart), [ADR 0121](../adr/0121-midi-import-boundary.md) |
| Guitar Pro | Nincs production GP parser, registry-bejegyzés vagy feltöltés. A felhasználó külső eszközben MusicXML/MXL vagy MIDI formátumba konvertál. | [ADR 0122](../adr/0122-guitar-pro-import-strategy.md), [feasibility report](../research/epic-03-guitar-pro-feasibility.md) |

Az R22 provenance-gate a teljes, jelenlegi `test/fixtures/song_trainer/`
import-fixture készletet inline `{provenance, licence, sha256}` manifesttel
fedi, beleértve az MPL-2.0 `minimal_gpx.gpx`-et. A gate egy hiányzó manifest
bejegyzést, hiányzó fájlt vagy hash-driftet hibának tekint:
[`check_song_fixture_licenses.dart`](../../tool/ci/check_song_fixture_licenses.dart).

## Perzisztencia, capability és progress

- A SongDocument, index, native exchange, Setlist V2 és Song progress encode/decode
  részei a tracked, inline schema-snapshot gate alá tartoznak. Nem-schema kódsor
  nem változtatja a snapshotot; encoding/decoding drift explicit hash-frissítést
  igényel. Evidence: [`check_song_schema.dart`](../../tool/ci/check_song_schema.dart).
- A SongDocument és assetek fájl-alapú, atomikus repositoryban élnek, nem
  SharedPreferencesben. Evidence: [`file_song_repository.dart`](../../lib/features/song_trainer/data/local/file_song_repository.dart),
  [`file_song_asset_repository.dart`](../../lib/features/song_trainer/data/local/file_song_asset_repository.dart).
- A Setlist V2 sorrendet és duplikált itemet őriz, a hiányzó referenciát
  recoverable skipként adja vissza; a progress record `songId + revision +
  measure/event` koordinátát tárol és a kétes revision mappinget archiválja.
  Evidence: [`song_setlist.dart`](../../lib/features/song_trainer/domain/models/song_setlist.dart),
  [`setlist_session_controller.dart`](../../lib/features/song_trainer/application/setlists/setlist_session_controller.dart),
  [`song_revision_progress_mapper.dart`](../../lib/features/song_trainer/application/progress/song_revision_progress_mapper.dart).
- A scored terminal a publikus Practice History/daily-goal bridge-en megy;
  playback-only record nem kap streak-kreditet. Evidence:
  [`song_progress_aggregator.dart`](../../lib/features/song_trainer/application/progress/song_progress_aggregator.dart),
  [`song_trainer_providers.dart`](../../lib/features/song_trainer/application/song_trainer_providers.dart),
  [ADR 0130](../adr/0130-setlist-v2-song-progress-and-epic-3-closure-boundary.md).
- A Performance képernyő a Practice runner factoryt nem hívja meg, ezért ezen
  belépési ponton nem konstruál scoring gateway-t. Evidence:
  [`setlist_session_screen.dart`](../../lib/features/song_trainer/presentation/screens/setlist_session_screen.dart),
  [`setlist_session_controller_test.dart`](../../test/features/song_trainer/application/setlists/setlist_session_controller_test.dart).

## Backing playback és importlimitek

Az aktuális local backing adapter `mp3` és `wav` formátumot deklarál, seeket és
0.5–1.5× rate-et tud; rate-váltáskor nem állít pitch-preservationt. Evidence:
[`local_backing_audio_player.dart`](../../lib/features/song_trainer/data/playback/local_backing_audio_player.dart).

Az import policy alapértékei: 1,048,576 source byte, 100,000 event, 128 MIDI
track, 8,388,608 workspace/extracted byte, 128 archive entry és 30 másodperc
wall-time. Evidence: [`import_limits.dart`](../../lib/features/song_trainer/data/importers/import_limits.dart).

## Determinisztikus teljesítmény-evidence

Az R22 long-song baseline jelenleg strukturális, nem eszközprofil: a
500-measure progress aggregate minden measure-t determinisztikus indexsorrendben
ad vissza. Nincs ebből levezethető FPS-, CPU-, memória- vagy akkumulátorállítás.
Evidence: [`long_song_performance_test.dart`](../../test/features/song_trainer/performance/long_song_performance_test.dart).

## Nyitott release blockerek

1. A `songTrainerV2Enabled`-gated alkalmazásrouter nem regisztrál Setlist V2
   route-ot; az R22 `SetlistListScreenV2` és `SetlistSessionScreen` komponensek
   route-integrációja külön, scope-os kör. Evidence:
   [`app_router.dart`](../../lib/app/routing/app_router.dart),
   [`setlist_list_screen_v2.dart`](../../lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart).
2. A feature flag production bekapcsolása és a legacy storage törlése az
   [ADR 0130](../adr/0130-setlist-v2-song-progress-and-epic-3-closure-boundary.md)
   szerint külön döntés.
3. Nincs exact-branch-head teljes Flutter/property/APK CI vagy független review
   evidence ebben a branch snapshotban.
4. A teljes valódi eszközös lista még nincs mért evidence-szel lezárva:
   legacy migráció; native import; MusicXML/MXL import; MIDI import; GP conversion
   út; 3/4 és 6/8; tempo change; section practice; A–B loop; backing track;
   repeated seek; Bluetooth interruption; chord/rhythm scoring; monophonic pitch
   scoring; Setlist Practice; Setlist Performance; 20 perces session; app
   background; storage recovery. Mindegyik önálló release blocker, amíg a
   készülék/módszer/eredmény nincs rögzítve.
## R22 gépi evidence

- Distinguishing tests: duplicate sorrend, missing-skip, Practice/Performance
  mode, lusta scoring runner konstrukció, progress/streak terminal idempotency,
  revision archive és randomizált aggregate idempotencia. Evidence:
  [`test/features/song_trainer`](../../test/features/song_trainer) és
  [`song_progress_property_test.dart`](../../test/property/song_progress_property_test.dart).
- A kötelező local gate 2026-08-04-én egy futásban zöld volt: format, analyzer,
  Song Trainer, Songs, Practice, property és architecture. A korábbi inotify
  `errno=24` host-hiba ezért már nem aktuális gate-blocker.
- CI-ben a shared Flutter gate után külön fut a schema és fixture provenance
  gate. Evidence: [`build-apk.yml`](../../.github/workflows/build-apk.yml).
