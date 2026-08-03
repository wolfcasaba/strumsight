import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/importers/midi_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';

void main() {
  const importer = MidiImporter();

  test(
    'imports format 0 with raw PPQ timing and a stable note preview',
    () async {
      final bytes = await File(
        'test/fixtures/song_trainer/midi/format0.mid',
      ).readAsBytes();

      final result = await importer.import(
        _source('format0.mid', bytes),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );

      expect(result, isA<Success<SongImportResult>>());
      final document = result.valueOrNull!.document;
      final notes = document.tracks.whereType<NoteTrack>().single.events;
      expect(notes.single.midiPitch, 60);
      expect(notes.single.start, const Duration(milliseconds: 250));
      expect(notes.single.duration, const Duration(milliseconds: 500));
      expect(document.tempoMap.changes.single.bpm.bpm, 120);
      expect(result.valueOrNull!.parts.single.channel, 0);
      expect(
        result.valueOrNull!.parts.single.duration,
        const Duration(milliseconds: 750),
      );
      expect(result.valueOrNull!.parts.single.isMonophonic, isTrue);
    },
  );

  test('imports format 1 metadata and preserves every note track', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/midi/format1_multitrack.mid',
    ).readAsBytes();

    final result = await importer.import(
      _source('multi.midi', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    final document = result.valueOrNull!.document;
    expect(document.metadata.title, 'Format One');
    expect(document.tracks.whereType<NoteTrack>(), hasLength(2));
    expect(
      document.tracks.whereType<NoteTrack>().map((track) => track.name),
      <String>['Lead', 'Bass'],
    );
  });

  test('maps tempo meter key marker and lyric meta events', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/midi/tempo_meter_marker.mid',
    ).readAsBytes();

    final result = await importer.import(
      _source('meta.mid', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    final document = result.valueOrNull!.document;
    expect(document.tempoMap.changes.map((change) => change.bpm.bpm), <int>[
      120,
      90,
    ]);
    expect(document.meterMap.changes.single.meter.numerator, 3);
    expect(document.keyMap.changes.single.key.tonic, -1);
    expect(document.markers.single.label, 'Verse');
    expect(
      document.tracks.whereType<LyricsTrack>().single.events.single.text,
      'Hello',
    );
  });

  test(
    'treats running velocity zero as note off and reports drum polyphony',
    () async {
      final velocityZero = await File(
        'test/fixtures/song_trainer/midi/running_velocity0.mid',
      ).readAsBytes();
      final drum = await File(
        'test/fixtures/song_trainer/midi/polyphonic_drum.mid',
      ).readAsBytes();

      final velocityResult = await importer.import(
        _source('running.mid', velocityZero),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );
      final drumProbe = await importer.probe(
        _source('drum.mid', drum),
        const NeverCancelledToken(),
      );

      expect(
        velocityResult.valueOrNull!.document.tracks
            .whereType<NoteTrack>()
            .single
            .events
            .single
            .duration,
        const Duration(milliseconds: 500),
      );
      expect(drumProbe.parts.single.suspectedDrum, isTrue);
      expect(drumProbe.parts.single.isPolyphonic, isTrue);
    },
  );
}

ImportSourceFile _source(String name, List<int> bytes) => ImportSourceFile(
  displayName: name,
  byteLength: bytes.length,
  openRead: () => Stream<List<int>>.value(bytes),
);
