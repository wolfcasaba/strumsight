// E13-R31 §6 A3/A4/A6 — missing data is never shown as zero, a trend needs
// the 5-point threshold (inclusive), and local/offline progress stays
// visible without a network call. See
// docs/rounds/e13-r31-progress-and-skills.md §6/§6.1.
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

/// `id` is snake_case (matches `MasteryMilestone.id`'s own contract); the
/// key fields must be lowerCamelCase, so this converts once per fixture.
String _camel(String snakeCase) {
  final parts = snakeCase.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join();
}

MasteryMilestone _milestone(String id) => MasteryMilestone(
  id: id,
  catalogVersion: 1,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: MasteryDifficulty.beginner,
  tempoRange: MasteryTempoRange(minBpm: 60, maxBpm: 100),
  minEvidenceSessions: 5,
  titleKey: '${_camel(id)}Title',
  descriptionKey: '${_camel(id)}Description',
);

List<ProgressTrendPoint> _points(int count) => [
  for (var i = 0; i < count; i++)
    ProgressTrendPoint(
      observedAt: DateTime.utc(2026, 8, 1 + i),
      value: 0.5 + i * 0.01,
    ),
];

ProgressOverviewProjection _projection({
  bool isOffline = false,
  required List<MilestoneOverviewEntry> milestones,
  ProgressTrend? trend,
}) => ProgressOverviewProjection(
  isOffline: isOffline,
  milestones: milestones,
  trend: trend ?? ProgressTrend(points: _points(5)),
  metricSegments: const [],
);

void main() {
  group('A3 — missing data is never rendered as zero', () {
    testWidgets(
      'a milestone with zero evidence shows the unavailable glyph, never "0%"',
      (tester) async {
        final milestone = _milestone('chord_transition_beginner');
        final entry = MilestoneOverviewEntry(
          milestone: milestone,
          progress: MasteryProgress.fresh(
            milestoneId: milestone.id,
            catalogVersion: 1,
          ),
          title: 'Chord transitions — beginner',
        );
        final measuredEntry = MilestoneOverviewEntry(
          milestone: _milestone('rhythm_accuracy_beginner'),
          progress: MasteryProgress(
            milestoneId: 'rhythm_accuracy_beginner',
            catalogVersion: 1,
            evidenceSessionCount: 5,
          ),
          title: 'Rhythm accuracy — beginner',
        );

        await tester.pumpWidget(
          _host(
            ProgressDashboardScreen(
              projection: _projection(milestones: [entry, measuredEntry]),
              onOpenSkillDetail: (_) {},
              onGetStarted: () {},
            ),
          ),
        );

        expect(find.text('0%'), findsNothing);
        expect(find.text('Not measured yet'), findsOneWidget);
        // The measured sibling still renders its real value — this proves
        // the missing-data branch is a distinct state, not a global "hide
        // all percentages" fallback.
        expect(find.text('100%'), findsOneWidget);

        final rings = tester.widgetList<SsScoreRing>(find.byType(SsScoreRing));
        final states = rings.map((ring) => ring.state).toList();
        expect(states, contains(SsScoreRingState.unavailable));
        expect(states, contains(SsScoreRingState.measured));
      },
    );

    testWidgets(
      'a brand-new user (no evidence anywhere) sees the getting-started state',
      (tester) async {
        var startedPractice = false;
        final milestone = _milestone('chord_transition_beginner');
        final entry = MilestoneOverviewEntry(
          milestone: milestone,
          progress: MasteryProgress.fresh(
            milestoneId: milestone.id,
            catalogVersion: 1,
          ),
          title: 'Chord transitions — beginner',
        );

        await tester.pumpWidget(
          _host(
            ProgressDashboardScreen(
              projection: _projection(
                milestones: [entry],
                trend: ProgressTrend(points: const []),
              ),
              onOpenSkillDetail: (_) {},
              onGetStarted: () => startedPractice = true,
            ),
          ),
        );

        expect(
          find.byKey(const Key('progress-dashboard-new-user')),
          findsOneWidget,
        );
        expect(find.text('0%'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('ss-empty-state-action')));
        await tester.pumpAndSettle();
        expect(startedPractice, isTrue);
      },
    );
  });

  group('A4 — the trend needs the 5-point inclusive threshold', () {
    Future<void> pumpWithTrend(WidgetTester tester, int pointCount) async {
      final milestone = _milestone('chord_transition_beginner');
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
            projection: _projection(
              milestones: [entry],
              trend: ProgressTrend(points: _points(pointCount)),
            ),
            onOpenSkillDetail: (_) {},
            onGetStarted: () {},
          ),
        ),
      );
    }

    testWidgets('below the threshold (3 points) shows no trend', (
      tester,
    ) async {
      await pumpWithTrend(tester, 3);

      expect(
        find.byKey(const Key('progress-trend-insufficient')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('progress-trend-chart-summary')),
        findsNothing,
      );
      expect(find.byType(SsTrendIndicator), findsNothing);
    });

    testWidgets(
      'exactly at the threshold (5 points, inclusive) shows a trend',
      (tester) async {
        await pumpWithTrend(tester, 5);

        expect(
          find.byKey(const Key('progress-trend-insufficient')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('progress-trend-chart-summary')),
          findsOneWidget,
        );
        expect(find.byType(SsTrendIndicator), findsOneWidget);
      },
    );

    testWidgets('above the threshold (30 points) shows a trend', (
      tester,
    ) async {
      await pumpWithTrend(tester, 30);

      expect(
        find.byKey(const Key('progress-trend-insufficient')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('progress-trend-chart-summary')),
        findsOneWidget,
      );
      expect(find.byType(SsTrendIndicator), findsOneWidget);
    });
  });

  group('A6 — local/offline progress stays visible', () {
    testWidgets(
      'offline progress renders the offline marker alongside real data',
      (tester) async {
        final milestone = _milestone('chord_transition_beginner');
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
              projection: _projection(isOffline: true, milestones: [entry]),
              onOpenSkillDetail: (_) {},
              onGetStarted: () {},
            ),
          ),
        );

        expect(find.byType(SsStatusBadge), findsOneWidget);
        // The milestone's real, locally-held progress is still fully visible
        // while offline — offline never hides or blanks local data.
        expect(find.text('100%'), findsOneWidget);
        expect(find.text('Chord transitions — beginner'), findsOneWidget);
      },
    );

    testWidgets('a synced dashboard shows no offline marker', (tester) async {
      final milestone = _milestone('chord_transition_beginner');
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
            projection: _projection(milestones: [entry]),
            onOpenSkillDetail: (_) {},
            onGetStarted: () {},
          ),
        ),
      );

      expect(find.byType(SsStatusBadge), findsNothing);
    });
  });

  group('milestone navigation', () {
    testWidgets('tapping a milestone row opens its skill detail by id', (
      tester,
    ) async {
      String? openedId;
      final milestone = _milestone('chord_transition_beginner');
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
            projection: _projection(milestones: [entry]),
            onOpenSkillDetail: (id) => openedId = id,
            onGetStarted: () {},
          ),
        ),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('progress-skill-row-chord_transition_beginner'),
        ),
      );
      await tester.pumpAndSettle();

      expect(openedId, 'chord_transition_beginner');
    });
  });
}
