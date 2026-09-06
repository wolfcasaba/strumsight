// Javító sáv 2026-09-06 (R3) — the Setup → session hand-off that the
// shipped app never had (`docs/ui/apk-functionality-audit-2026-09-06.md`).
//
// A1 — a config for a stored song yields the session inputs.
// A2 — a song that is gone is an explicit `songMissing` failure.
// A3 — a config whose revision no longer matches is `staleConfig`, not a
//      crash (the compiler's ArgumentError is translated).
// A4 — the backing asset is the one the backing track references; a
//      document without a backing track yields none.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/tuning.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_launcher.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/loop_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';

void main() {
  group('SongTrainerLauncher', () {
    test('A1 — a stored song yields session inputs', () async {
      final repository = InMemorySongRepository();
      final document = _document();
      expect(await repository.create(document), isA<Success<void>>());
      final launcher = SongTrainerLauncher(songRepository: repository);

      final prepared = await launcher.prepare(_config(document));

      expect(prepared, isA<Success<SongTrainerControllerInputs>>());
      final inputs = (prepared as Success<SongTrainerControllerInputs>).value;
      expect(inputs.compilation.isPlaybackOnly, isTrue);
      expect(inputs.backingAsset, isNull);
    });

    test('A2 — a missing song is an explicit songMissing failure', () async {
      final launcher = SongTrainerLauncher(
        songRepository: InMemorySongRepository(),
      );

      final prepared = await launcher.prepare(_config(_document()));

      expect(prepared, isA<Failure<SongTrainerControllerInputs>>());
      expect(
        (prepared as Failure<SongTrainerControllerInputs>).error.code,
        SongTrainerLaunchFailureCode.songMissing,
      );
    });

    test('A3 — a stale revision is a staleConfig failure, not a crash', () {
      final document = _document();

      final prepared = SongTrainerLauncher.compile(
        document: document,
        config: _config(document, revision: document.revision + 1),
      );

      expect(prepared, isA<Failure<SongTrainerControllerInputs>>());
      expect(
        (prepared as Failure<SongTrainerControllerInputs>).error.code,
        SongTrainerLaunchFailureCode.staleConfig,
      );
    });

    test('A4 — the backing asset is the referenced one', () {
      final asset = SongAssetReference(
        id: SongAssetId('backing'),
        sha256: 'a' * 64,
        extension: 'mp3',
        byteLength: 100,
        mimeType: 'audio/mpeg',
        durationMs: 60000,
      );
      final withBacking = _document(
        assets: <SongAssetReference>[asset],
        extraTracks: <SongTrack>[
          BackingAudioTrack(
            id: SongTrackId('backing'),
            name: 'Backing',
            instrument: SongInstrument(name: 'Band'),
            assetId: asset.id,
            gridOffset: Duration.zero,
          ),
        ],
      );

      expect(SongTrainerLauncher.backingAssetOf(withBacking), same(asset));
      expect(SongTrainerLauncher.backingAssetOf(_document()), isNull);
    });
  });
}

SongDocument _document({
  List<SongAssetReference> assets = const <SongAssetReference>[],
  List<SongTrack> extraTracks = const <SongTrack>[],
}) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('launch'),
    revision: 0,
    metadata: SongMetadata(
      title: 'Launch song',
      defaultTuning: Tunings.standard,
      defaultCapo: 0,
    ),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'launch.song',
      sha256: 'b' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    assets: assets,
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const [],
      ),
      ...extraTracks,
    ],
  );
}

/// A pitch-mode config: the compiler short-circuits to the playback-only
/// compilation for it (no events needed), which is exactly the path the
/// launcher's hand-off is measured on here.
TrainerConfig _config(SongDocument document, {int? revision}) {
  final range = MeasureRange(start: 0, endExclusive: 2);
  return TrainerConfig(
    songId: document.id,
    songRevision: revision ?? document.revision,
    trackId: SongTrackId('chords'),
    selection: range,
    range: range,
    mode: TrainerMode.pitch,
    targetSpeed: 1,
    countInBars: 1,
    metronomeEnabled: false,
    loopConfig: LoopConfig(range: range),
    tuningReminder: null,
    capo: 0,
    capoReminder: false,
  );
}
