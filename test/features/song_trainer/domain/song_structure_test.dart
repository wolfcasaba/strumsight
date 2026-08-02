import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  group('song structure', () {
    test('validates sections and preserves immutable lists', () {
      final sections = <SongSection>[
        SongSection(
          id: SongSectionId('intro'),
          name: 'Intro',
          startMeasure: 0,
          endMeasureExclusive: 2,
          kind: SongSectionKind.intro,
        ),
      ];
      final document = SongDocument(
        schemaVersion: songDocumentSchemaVersion,
        id: SongId('song'),
        revision: 0,
        metadata: SongMetadata(title: 'Song'),
        source: SongSource(
          type: SongSourceType.createdInApp,
          originalFileName: 'song.strum',
          sha256: List<String>.filled(64, '0').join(),
          importedAt: DateTime.utc(2026),
          importerVersion: 'test',
        ),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        sections: sections,
        measures: [
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(3)),
          SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(3)),
        ],
        tempoMap: TempoMap.constant(Tempo(120)),
        meterMap: MeterMap.constant(Meter(3, 4)),
        keyMap: KeyMap.constant(KeySignature(0, KeyMode.major)),
      );

      sections.clear();
      expect(document.sections, hasLength(1));
      expect(document.measures.first.durationBeats, BeatPosition.fromBeats(3));
    });

    test('supports pickup and common meters', () {
      expect(
        SongMeasure(
          index: 0,
          durationBeats: BeatPosition.fromBeats(1),
          pickup: true,
        ).pickup,
        isTrue,
      );
      expect(Meter(3, 4).beatsPerMeasure, 3);
      expect(Meter(6, 8).beatsPerMeasure, 3);
    });

    test('rejects invalid ranges and duplicate map boundaries', () {
      expect(
        () => SongSection(
          id: SongSectionId('bad'),
          name: 'Bad',
          startMeasure: 2,
          endMeasureExclusive: 2,
        ),
        throwsA(isA<SongStructureValidationException>()),
      );
      expect(
        () => TempoMap([
          TempoChange(at: BeatPosition.zero, bpm: Tempo(120)),
          TempoChange(at: BeatPosition.zero, bpm: Tempo(90)),
        ]),
        throwsA(isA<SongStructureValidationException>()),
      );
    });
  });
}
