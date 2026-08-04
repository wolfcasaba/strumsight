import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_session_controller.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';

void main() {
  final setlist = SongSetlist(
    id: 'setlist-1',
    name: 'Warm-up',
    createdAt: DateTime.utc(2026, 8, 4),
    updatedAt: DateTime.utc(2026, 8, 4),
    items: <SongSetlistItem>[
      SongSetlistItem(id: 'first', songId: SongId('song-a')),
      SongSetlistItem(id: 'missing', songId: SongId('song-missing')),
      SongSetlistItem(id: 'second', songId: SongId('song-a')),
    ],
  );

  test(
    'duplicate song items produce two results in their original order',
    () async {
      final controller = SetlistSessionController(
        availability: (item) => item.id == 'missing'
            ? SetlistItemAvailability.missingSong
            : SetlistItemAvailability.ready,
        practiceRunner: (item) async => SetlistItemResult.completed(
          itemId: item.id,
          activeDuration: const Duration(seconds: 4),
        ),
        performanceRunner: (item) async => SetlistItemResult.completed(
          itemId: item.id,
          activeDuration: const Duration(seconds: 2),
        ),
      );

      final result = await controller.run(
        setlist: setlist,
        mode: SetlistSessionMode.practice,
      );

      expect(result.itemResults.map((item) => item.itemId), <String>[
        'first',
        'missing',
        'second',
      ]);
      expect(result.itemResults[0].status, SetlistItemResultStatus.completed);
      expect(result.itemResults[1].status, SetlistItemResultStatus.skipped);
      expect(result.itemResults[2].status, SetlistItemResultStatus.completed);
    },
  );

  test(
    'missing song is a recoverable skip and the following item still runs',
    () async {
      var completed = 0;
      final controller = SetlistSessionController(
        availability: (item) => item.id == 'missing'
            ? SetlistItemAvailability.missingSong
            : SetlistItemAvailability.ready,
        practiceRunner: (item) async {
          completed++;
          return SetlistItemResult.completed(itemId: item.id);
        },
        performanceRunner: (item) async =>
            SetlistItemResult.completed(itemId: item.id),
      );

      final result = await controller.run(
        setlist: setlist,
        mode: SetlistSessionMode.practice,
      );

      expect(completed, 2);
      expect(result.itemResults[1].repairRequired, isTrue);
      expect(
        result.itemResults[1].availability,
        SetlistItemAvailability.missingSong,
      );
    },
  );

  test(
    'Practice creates scoring work while Performance stays playback-only',
    () async {
      var practiceRuns = 0;
      var performanceRuns = 0;
      final controller = SetlistSessionController(
        availability: (_) => SetlistItemAvailability.ready,
        practiceRunner: (item) async {
          practiceRuns++;
          return SetlistItemResult.completed(itemId: item.id);
        },
        performanceRunner: (item) async {
          performanceRuns++;
          return SetlistItemResult.completed(itemId: item.id);
        },
      );
      final single = SongSetlist(
        id: 'single',
        name: 'Single',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        items: <SongSetlistItem>[
          SongSetlistItem(id: 'one', songId: SongId('song-a')),
        ],
      );

      final practice = await controller.run(
        setlist: single,
        mode: SetlistSessionMode.practice,
      );
      final performance = await controller.run(
        setlist: single,
        mode: SetlistSessionMode.performance,
      );

      expect(practiceRuns, 1);
      expect(performanceRuns, 1);
      expect(practice.usesScoring, isTrue);
      expect(practice.requiresMicrophone, isTrue);
      expect(performance.usesScoring, isFalse);
      expect(performance.requiresMicrophone, isFalse);
    },
  );
}
