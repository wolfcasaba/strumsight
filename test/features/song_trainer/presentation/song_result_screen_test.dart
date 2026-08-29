// Widget-level coverage for the Song Trainer result screen + measure heatmap.
// The heatmap is accessible — color always sits next to a label / icon / text
// semantics, and the screen reader's live feedback is throttled.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/measure_heatmap.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  testWidgets('renders the measure heatmap, retry, and next-section CTAs', (
    tester,
  ) async {
    final result = _result();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongResultScreen(result: result),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('song-result-heatmap')), findsOneWidget);
    expect(find.byKey(const Key('song-result-retry')), findsOneWidget);
    expect(find.byKey(const Key('song-result-next-section')), findsOneWidget);
  });

  testWidgets('heatmap cells expose a label semantics for the screen reader', (
    tester,
  ) async {
    final result = _result();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MeasureHeatmap(
            measureResults: result.measureResults,
            sectionResults: result.sectionResults,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final measure in result.measureResults) {
      final key = ValueKey<String>('measure-heatmap-${measure.measureIndex}');
      final semantics = tester.getSemantics(find.byKey(key));
      expect(semantics.label, isNotEmpty);
    }
  });
}

SongTrainerResult _result() {
  final verdicts = <SongTrainerVerdict>[];
  final measureResults = <SongMeasureTrainerResult>[
    for (var index = 0; index < 4; index++)
      SongMeasureTrainerResult(
        measureIndex: index,
        verdicts: verdicts,
        averageEventScore: 0.85 - (index * 0.1),
      ),
  ];
  final sectionResults = <SongSectionTrainerResult>[];
  return SongTrainerResult(
    sessionResult: PracticeSessionResult(
      id: 'practice-result',
      activeDuration: const Duration(seconds: 4),
      pausedDuration: Duration.zero,
      attempts: const <PracticeAttemptResult>[],
      finishReason: PracticeFinishReason.completedAllTargets,
      highestStableTempo: null,
      coachingSummary: const <String>[],
    ),
    verdicts: verdicts,
    measureResults: measureResults,
    sectionResults: sectionResults,
  );
}
