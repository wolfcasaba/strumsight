import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_controller.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_session_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_session_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

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

  testWidgets('setlist list uses a windowed list and exposes its edit entry', (
    tester,
  ) async {
    final controller = SetlistController(
      _MemorySetlistRepository(<SongSetlist>[setlist]),
    );
    await tester.pumpWidget(
      _localizedApp(
        SetlistListScreenV2(
          controller: controller,
          clock: () => DateTime.utc(2026, 8, 4),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setlist-list-window')), findsOneWidget);
    expect(find.text('Warm-up'), findsOneWidget);
    expect(find.byKey(const Key('setlist-edit-setlist-1')), findsOneWidget);
  });

  testWidgets('Performance never constructs the lazy scoring runner', (
    tester,
  ) async {
    var scoringRunnerConstructions = 0;
    final single = SongSetlist(
      id: 'performance-single',
      name: 'Performance',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
      items: <SongSetlistItem>[
        SongSetlistItem(id: 'performance-item', songId: SongId('song-a')),
      ],
    );
    await tester.pumpWidget(
      _localizedApp(
        SetlistSessionScreen(
          setlist: single,
          mode: SetlistSessionMode.performance,
          availability: (_) => SetlistItemAvailability.ready,
          createPracticeRunner: () {
            scoringRunnerConstructions++;
            return (item) async => SetlistItemResult.completed(itemId: item.id);
          },
          performanceRunner: (item) async =>
              SetlistItemResult.completed(itemId: item.id),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('setlist-session-start')));
    await tester.pumpAndSettle();

    expect(scoringRunnerConstructions, 0);
    expect(find.byKey(const Key('setlist-session-result')), findsOneWidget);
  });

  testWidgets('result screen presents supplied progress and setlist result', (
    tester,
  ) async {
    final result = SongTrainerResult(
      sessionResult: PracticeSessionResult(
        id: 'result',
        activeDuration: Duration.zero,
        pausedDuration: Duration.zero,
        attempts: const <PracticeAttemptResult>[],
        finishReason: PracticeFinishReason.completedAllTargets,
        highestStableTempo: null,
        coachingSummary: const <String>[],
      ),
      verdicts: const <SongTrainerVerdict>[],
      measureResults: const <SongMeasureTrainerResult>[],
      sectionResults: const <SongSectionTrainerResult>[],
    );
    await tester.pumpWidget(
      _localizedApp(
        SongResultScreen(
          result: result,
          progress: const SongProgressAggregate.empty(),
          setlistResult: SetlistResult(
            setlistId: 'setlist-1',
            mode: SetlistSessionMode.performance,
            itemResults: <SetlistItemResult>[
              SetlistItemResult.completed(itemId: 'first'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('song-result-progress')), findsOneWidget);
    expect(find.byKey(const Key('song-result-setlist')), findsOneWidget);
  });
}

Widget _localizedApp(Widget home) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

final class _MemorySetlistRepository implements SetlistRepository {
  _MemorySetlistRepository(List<SongSetlist> initial)
    : _setlists = <String, SongSetlist>{
        for (final setlist in initial) setlist.id: setlist,
      };

  final Map<String, SongSetlist> _setlists;

  @override
  Future<AppResult<void>> delete(String id) async {
    _setlists.remove(id);
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<SongSetlist?>> get(String id) async =>
      AppResult<SongSetlist?>.success(_setlists[id]);

  @override
  Future<AppResult<List<SongSetlist>>> list() async =>
      AppResult<List<SongSetlist>>.success(_setlists.values.toList());

  @override
  Future<AppResult<void>> save(SongSetlist setlist) async {
    _setlists[setlist.id] = setlist;
    return const AppResult<void>.success(null);
  }
}
