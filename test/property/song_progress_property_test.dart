import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';

void main() {
  test('randomized replay of persisted records is aggregate-idempotent', () {
    const seed = 20260804;
    final random = Random(seed);
    for (var caseIndex = 0; caseIndex < 100; caseIndex++) {
      final records = <SongPracticeRecord>[
        for (var index = 0; index < 1 + random.nextInt(40); index++)
          SongPracticeRecord(
            id: 'case-$caseIndex-record-$index',
            songId: SongId('property-song'),
            songRevision: 1,
            source: SongProgressSource(
              measureId: 'm-${random.nextInt(12)}',
              eventId: 'e-$index',
              measureIndex: random.nextInt(12),
              sectionId: 's-${random.nextInt(3)}',
            ),
            activeDuration: Duration(seconds: 1 + random.nextInt(60)),
            completed: random.nextBool(),
            score: random.nextDouble(),
            recordedAt: DateTime.utc(2026, 8, 4),
          ),
      ];
      final replayed = <SongPracticeRecord>[...records, ...records];

      expect(
        SongProgressAggregator.aggregate(replayed),
        SongProgressAggregator.aggregate(records),
        reason: 'seed=$seed case=$caseIndex',
      );
    }
  });
}
