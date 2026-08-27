// E13-R31 §6 A5 — a metric-version change stays visible in the history
// instead of reading as a sudden jump inside one continuous line. See
// docs/rounds/e13-r31-progress-and-skills.md §6/§6.1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  catalogVersion: 2,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: MasteryDifficulty.beginner,
  tempoRange: MasteryTempoRange(minBpm: 60, maxBpm: 100),
  minEvidenceSessions: 5,
  titleKey: 'chordTransitionBeginnerTitle',
  descriptionKey: 'chordTransitionBeginnerDescription',
);

void main() {
  group('segmentByCatalogVersion (pure function)', () {
    test('groups contiguous samples of the same version into one segment', () {
      final samples = <VersionedTrendSample>[
        (
          catalogVersion: 1,
          point: ProgressTrendPoint(
            observedAt: DateTime.utc(2026, 1, 1),
            value: 0.2,
          ),
        ),
        (
          catalogVersion: 1,
          point: ProgressTrendPoint(
            observedAt: DateTime.utc(2026, 1, 2),
            value: 0.25,
          ),
        ),
        (
          catalogVersion: 2,
          point: ProgressTrendPoint(
            observedAt: DateTime.utc(2026, 1, 3),
            value: 0.8,
          ),
        ),
      ];

      final segments = segmentByCatalogVersion(samples);

      expect(segments, hasLength(2));
      expect(segments[0].catalogVersion, 1);
      expect(segments[0].points, hasLength(2));
      expect(segments[1].catalogVersion, 2);
      expect(segments[1].points, hasLength(1));
    });

    test(
      'a version reappearing later starts a NEW segment, never re-merges',
      () {
        final samples = <VersionedTrendSample>[
          (
            catalogVersion: 1,
            point: ProgressTrendPoint(
              observedAt: DateTime.utc(2026, 1, 1),
              value: 0.2,
            ),
          ),
          (
            catalogVersion: 2,
            point: ProgressTrendPoint(
              observedAt: DateTime.utc(2026, 1, 2),
              value: 0.8,
            ),
          ),
          (
            catalogVersion: 1,
            point: ProgressTrendPoint(
              observedAt: DateTime.utc(2026, 1, 3),
              value: 0.3,
            ),
          ),
        ];

        final segments = segmentByCatalogVersion(samples);

        expect(segments, hasLength(3));
        expect(segments.map((s) => s.catalogVersion), [1, 2, 1]);
      },
    );

    test('an empty sample list produces no segments', () {
      expect(segmentByCatalogVersion(const []), isEmpty);
    });
  });

  group('A5 — a version change renders as a visibly separate section', () {
    testWidgets(
      'two catalog versions render as distinct labelled segments with a change note',
      (tester) async {
        final milestone = _milestone();
        final entry = MilestoneOverviewEntry(
          milestone: milestone,
          progress: MasteryProgress(
            milestoneId: milestone.id,
            catalogVersion: 2,
            evidenceSessionCount: 5,
          ),
          title: 'Chord transitions — beginner',
        );

        final segments = [
          MetricVersionSegment(
            catalogVersion: 1,
            points: [
              ProgressTrendPoint(
                observedAt: DateTime.utc(2026, 1, 1),
                value: 0.2,
              ),
              ProgressTrendPoint(
                observedAt: DateTime.utc(2026, 1, 2),
                value: 0.22,
              ),
            ],
          ),
          MetricVersionSegment(
            catalogVersion: 2,
            points: [
              ProgressTrendPoint(
                observedAt: DateTime.utc(2026, 6, 1),
                value: 0.85,
              ),
            ],
          ),
        ];

        await tester.pumpWidget(
          _host(
            ProgressDashboardScreen(
              projection: ProgressOverviewProjection(
                isOffline: false,
                milestones: [entry],
                trend: ProgressTrend(
                  points: List.generate(
                    5,
                    (i) => ProgressTrendPoint(
                      observedAt: DateTime.utc(2026, 8, 1 + i),
                      value: 0.5,
                    ),
                  ),
                ),
                metricSegments: segments,
              ),
              onOpenSkillDetail: (_) {},
              onGetStarted: () {},
            ),
          ),
        );

        expect(
          find.byKey(const Key('progress-metric-version-changed-note')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('progress-metric-segment-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('progress-metric-segment-2')),
          findsOneWidget,
        );
        expect(find.text('Measure v1'), findsOneWidget);
        expect(find.text('Measure v2'), findsOneWidget);
      },
    );

    testWidgets('a single catalog version shows no history section at all', (
      tester,
    ) async {
      final milestone = _milestone();
      final entry = MilestoneOverviewEntry(
        milestone: milestone,
        progress: MasteryProgress(
          milestoneId: milestone.id,
          catalogVersion: 2,
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
                points: List.generate(
                  5,
                  (i) => ProgressTrendPoint(
                    observedAt: DateTime.utc(2026, 8, 1 + i),
                    value: 0.5,
                  ),
                ),
              ),
              metricSegments: [
                MetricVersionSegment(
                  catalogVersion: 2,
                  points: [
                    ProgressTrendPoint(
                      observedAt: DateTime.utc(2026, 6, 1),
                      value: 0.85,
                    ),
                  ],
                ),
              ],
            ),
            onOpenSkillDetail: (_) {},
            onGetStarted: () {},
          ),
        ),
      );

      expect(
        find.byKey(const Key('progress-metric-version-changed-note')),
        findsNothing,
      );
    });
  });
}
