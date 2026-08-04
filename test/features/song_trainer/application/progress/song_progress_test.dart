import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_revision_progress_mapper.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';

SongPracticeRecord _record({
  required String id,
  required int revision,
  required String measureId,
  required int measureIndex,
  String? sectionId,
  double score = 0.8,
}) => SongPracticeRecord(
  id: id,
  songId: SongId('song-a'),
  songRevision: revision,
  source: SongProgressSource(
    measureId: measureId,
    eventId: 'event-$id',
    measureIndex: measureIndex,
    sectionId: sectionId,
  ),
  activeDuration: const Duration(seconds: 12),
  completed: true,
  score: score,
  recordedAt: DateTime.utc(2026, 8, 4),
);

void main() {
  test(
    'aggregate is idempotent when the same persisted record is replayed',
    () {
      final first = _record(
        id: 'same',
        revision: 1,
        measureId: 'm1',
        measureIndex: 0,
      );
      final second = _record(
        id: 'other',
        revision: 1,
        measureId: 'm2',
        measureIndex: 1,
      );

      final once = SongProgressAggregator.aggregate(<SongPracticeRecord>[
        first,
        second,
      ]);
      final replayed = SongProgressAggregator.aggregate(<SongPracticeRecord>[
        first,
        second,
        first,
      ]);

      expect(replayed, once);
      expect(once.measures.map((measure) => measure.measureId), <String>[
        'm1',
        'm2',
      ]);
    },
  );

  test(
    'new revision carries progress only through a stable measure-id mapping',
    () {
      final source = _record(
        id: 'stable',
        revision: 2,
        measureId: 'old-verse',
        measureIndex: 4,
      );

      final mapped = SongRevisionProgressMapper.map(
        records: <SongPracticeRecord>[source],
        targetRevision: 3,
        stableMeasureIds: const <String, String>{'old-verse': 'new-verse'},
      );

      expect(mapped.mapped, hasLength(1));
      expect(mapped.mapped.single.songRevision, 3);
      expect(mapped.mapped.single.source.measureId, 'new-verse');
      expect(mapped.archived, isEmpty);
    },
  );

  test(
    'deleted or ambiguous measure ids are archived without false transfer',
    () {
      final deleted = _record(
        id: 'deleted',
        revision: 2,
        measureId: 'removed',
        measureIndex: 1,
      );
      final ambiguous = _record(
        id: 'ambiguous',
        revision: 2,
        measureId: 'old-chorus',
        measureIndex: 2,
      );

      final mapped = SongRevisionProgressMapper.map(
        records: <SongPracticeRecord>[deleted, ambiguous],
        targetRevision: 3,
        stableMeasureIds: const <String, String>{
          'old-a': 'new-chorus',
          'old-chorus': 'new-chorus',
        },
      );

      expect(mapped.mapped, isEmpty);
      expect(mapped.archived.map((record) => record.id), <String>[
        'ambiguous',
        'deleted',
      ]);
      expect(mapped.archived.every((record) => record.isArchived), isTrue);
    },
  );
}
