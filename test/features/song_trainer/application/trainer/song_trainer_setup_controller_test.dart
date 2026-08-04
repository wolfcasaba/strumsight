import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_setup_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_setup_state.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';

void main() {
  late InMemorySongRepository repository;
  late SongTrainerSetupController controller;

  setUp(() {
    repository = InMemorySongRepository();
    controller = SongTrainerSetupController(repository: repository);
  });

  tearDown(() => controller.dispose());

  test('loads through validation and capabilities, disables polyphonic pitch, '
      'and emits an immutable config without changing the document', () async {
    final document = _document(
      id: 'polyphonic',
      tracks: <SongTrack>[_polyphonicNotes()],
    );
    await repository.create(document);

    await controller.load(document.id);

    expect(controller.state.status, SongTrainerSetupStatus.ready);
    expect(
      controller.state.modeAvailability(TrainerMode.pitch).isEnabled,
      isFalse,
    );
    expect(
      controller.state.modeAvailability(TrainerMode.pitch).reason,
      TrainerModeUnavailableReason.polyphonicNotes,
    );
    expect(controller.selectMode(TrainerMode.pitch), isFalse);
    expect(
      controller.selectRange(
        MeasureRange.fromInclusive(start: 1, endInclusive: 1),
      ),
      isTrue,
    );
    expect(
      controller.selectRange(
        MeasureRange.fromInclusive(start: 2, endInclusive: 2),
      ),
      isFalse,
    );

    final config = controller.complete();

    expect(config, isA<TrainerConfig>());
    expect(config!.range, MeasureRange(start: 1, endExclusive: 2));
    expect(config.mode, TrainerMode.rhythm);
    expect((await repository.get(document.id)).valueOrNull, document);
  });

  test(
    'reports a dangling backing reference while playback rate stays pending',
    () async {
      final document = _document(
        id: 'missing-backing',
        tracks: <SongTrack>[_chords(), _backing()],
      );
      await repository.create(document);

      await controller.load(document.id);

      expect(controller.state.hasMissingBackingAsset, isTrue);
      expect(
        controller.state.backingRateAvailability,
        BackingRateAvailability.pending,
      );
      expect(
        controller.state.modeAvailability(TrainerMode.chord).isEnabled,
        isTrue,
      );
      expect(controller.complete(), isNotNull);
    },
  );
}

SongDocument _document({required String id, required List<SongTrack> tracks}) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(id),
    revision: 3,
    metadata: SongMetadata(title: id),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: '$id.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 2,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: tracks,
  );
}

ChordTrack _chords() => ChordTrack(
  id: SongTrackId('chords'),
  name: 'Chords',
  instrument: SongInstrument(name: 'Guitar'),
  events: const <SongChordEvent>[],
);

NoteTrack _polyphonicNotes() => NoteTrack(
  id: SongTrackId('notes'),
  name: 'Lead',
  instrument: SongInstrument(name: 'Guitar'),
  events: <SongNoteEvent>[
    SongNoteEvent(
      id: SongEventId('note-1'),
      start: Duration.zero,
      duration: const Duration(seconds: 1),
      midiPitch: 60,
    ),
    SongNoteEvent(
      id: SongEventId('note-2'),
      start: const Duration(milliseconds: 500),
      duration: const Duration(seconds: 1),
      midiPitch: 64,
    ),
  ],
);

BackingAudioTrack _backing() => BackingAudioTrack(
  id: SongTrackId('backing'),
  name: 'Backing',
  instrument: SongInstrument(name: 'Audio'),
  assetId: SongAssetId('missing-asset'),
  gridOffset: Duration.zero,
);
