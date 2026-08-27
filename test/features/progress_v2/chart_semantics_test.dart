// E13-R31 §6 A8 — the trend diagram always carries a textual summary AND a
// linear, browsable alternative to the plotted points (ADR 0282, ADR 0286
// §3). See docs/rounds/e13-r31-progress-and-skills.md §6/§0.0.B/B5.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

MasteryMilestone _milestone() => MasteryMilestone(
  id: 'chord_transition_beginner',
  catalogVersion: 1,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: MasteryDifficulty.beginner,
  tempoRange: MasteryTempoRange(minBpm: 60, maxBpm: 100),
  minEvidenceSessions: 5,
  titleKey: 'chordTransitionBeginnerTitle',
  descriptionKey: 'chordTransitionBeginnerDescription',
);

Future<void> _pumpWithTrend(WidgetTester tester, List<double> values) async {
  final milestone = _milestone();
  final entry = MilestoneOverviewEntry(
    milestone: milestone,
    progress: MasteryProgress(
      milestoneId: milestone.id,
      catalogVersion: 1,
      evidenceSessionCount: 5,
    ),
    title: 'Chord transitions — beginner',
  );

  await tester.pumpWidget(
    _host(
      ProgressDashboardScreen(
        projection: ProgressOverviewProjection(
          isOffline: false,
          milestones: [entry],
          trend: ProgressTrend(
            points: [
              for (var i = 0; i < values.length; i++)
                ProgressTrendPoint(
                  observedAt: DateTime.utc(2026, 8, 1 + i),
                  value: values[i],
                ),
            ],
          ),
          metricSegments: const [],
        ),
        onOpenSkillDetail: (_) {},
        onGetStarted: () {},
      ),
    ),
  );
}

void main() {
  group('A8 — the trend diagram pairs a text summary with a linear list', () {
    testWidgets('a plotted trend has a non-empty SsChartTextSummary', (
      tester,
    ) async {
      await _pumpWithTrend(tester, [0.5, 0.55, 0.6, 0.62, 0.7]);

      final summaryFinder = find.byType(SsChartTextSummary);
      expect(summaryFinder, findsOneWidget);
      final summary = tester.widget<SsChartTextSummary>(summaryFinder);
      expect(summary.summaryText, isNotEmpty);
      expect(summary.extremesText, isNotNull);
      expect(summary.extremesText, isNotEmpty);
    });

    testWidgets(
      'a plotted trend also has a browsable linear list with one row per point',
      (tester) async {
        await _pumpWithTrend(tester, [0.5, 0.55, 0.6, 0.62, 0.7]);

        final listFinder = find.byKey(const Key('progress-trend-event-list'));
        expect(listFinder, findsOneWidget);
        final list = tester.widget<SsEventList>(listFinder);
        expect(list.rows, hasLength(5));
        expect(list.semanticLabel, isNotEmpty);
      },
    );

    testWidgets(
      'when there is no trend to plot, neither the chart summary nor the list renders',
      (tester) async {
        await _pumpWithTrend(tester, [0.5, 0.55, 0.6]);

        expect(find.byType(SsChartTextSummary), findsNothing);
        expect(
          find.byKey(const Key('progress-trend-event-list')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('progress-trend-insufficient')),
          findsOneWidget,
        );
      },
    );
  });
}
