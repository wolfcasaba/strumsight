import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';

void main() {
  test('500-measure aggregate keeps every measure in deterministic order', () {
    final records = <SongPracticeRecord>[
      for (var index = 0; index < 500; index++)
        SongPracticeRecord(
          id: 'record-$index',
          songId: SongId('long-song'),
          songRevision: 1,
          source: SongProgressSource(
            measureId: 'measure-$index',
            eventId: 'event-$index',
            measureIndex: index,
          ),
          activeDuration: const Duration(seconds: 1),
          completed: true,
          score: 0.75,
          recordedAt: DateTime.utc(2026, 8, 4),
        ),
    ];

    final aggregate = SongProgressAggregator.aggregate(records);

    expect(aggregate.measures, hasLength(500));
    expect(aggregate.measures.first.measureIndex, 0);
    expect(aggregate.measures.last.measureIndex, 499);
  });
}
