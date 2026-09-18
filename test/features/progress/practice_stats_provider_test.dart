// Learner-loop round 4 ("one progress model"): the rollup every hub reads is
// built from the V1 + V2 aggregated feed, so a Practice V2 session counts on
// the Today / Profile / streak / progress screens like a Learn moment does.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart'
    as practice;
import 'package:strumsight/features/practice/public.dart'
    show practiceHistoryV2ListProvider;
import 'package:strumsight/features/progress/public.dart';

import '../../support/preference_store.dart';

final class _SeededLog extends PracticeLogController {
  _SeededLog(this._seed);
  final List<PracticeEntry> _seed;
  @override
  List<PracticeEntry> build() => _seed;
}

PracticeHistoryEntry _v2(String id, {int seconds = 90}) => PracticeHistoryEntry(
  id: id,
  modeCode: PracticeMode.strumPattern.code,
  sourceCode: practice.PracticeSource.builtin.code,
  createdAt: DateTime(2026, 9, 15, 10),
  definitionId: 'builtin.quarterDownstrokes.v1',
  displayTitle: '',
  finishReasonCode: 'completedAllTargets',
  activeDuration: Duration(seconds: seconds),
  pausedDuration: Duration.zero,
  attemptsCount: 3,
  finalMetricSnapshot: const PracticeMetricSnapshot(
    completion: PracticeMetricDimensionAvailable(0.9),
    rhythm: PracticeMetricDimensionAvailable(0.85),
    direction: PracticeMetricDimensionAvailable(0.95),
    chord: PracticeMetricDimensionNotApplicable(),
    overall: PracticeMetricDimensionAvailable(0.9),
  ),
  totalTargets: 10,
  resolvedTargets: 9,
  scorePoints: 0,
  maxCombo: 0,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const [],
  skillTags: const [],
);

void main() {
  test('V1 moments and V2 sessions are counted together', () async {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        practiceLogProvider.overrideWith(
          () => _SeededLog([
            const PracticeEntry(
              day: 20700,
              source: PracticeSource.live,
              seconds: 60,
              strokes: 20,
            ),
            const PracticeEntry(
              day: 20701,
              source: PracticeSource.learn,
              seconds: 120,
              strokes: 40,
            ),
          ]),
        ),
        practiceHistoryV2ListProvider.overrideWith(
          (ref) async => [_v2('v2-a'), _v2('v2-b', seconds: 30)],
        ),
      ],
    );
    addTearDown(container.dispose);

    // Let the V2 list resolve, then read the rollup.
    await container.read(practiceHistoryV2ListProvider.future);
    final stats = container.read(practiceStatsProvider);

    expect(stats.totalSessions, 4);
    expect(stats.totalSeconds, 60 + 120 + 90 + 30);
  });

  test('with no history at all the rollup is an honest zero', () {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        practiceLogProvider.overrideWith(() => _SeededLog(const [])),
        practiceHistoryV2ListProvider.overrideWith(
          (ref) async => const <PracticeHistoryEntry>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(practiceStatsProvider).totalSessions, 0);
  });
}
