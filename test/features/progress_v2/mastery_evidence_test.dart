// E13-R31 §6 A1/A2/A7 — mastery is evidence, not XP; every mastery claim
// opens an auditable session; a recommendation never ignores an unmet
// prerequisite. See docs/rounds/e13-r31-progress-and-skills.md §6/§6.1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

MasteryMilestone _milestone({int minEvidenceSessions = 5}) => MasteryMilestone(
  id: 'chord_transition_beginner',
  catalogVersion: 1,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: MasteryDifficulty.beginner,
  tempoRange: MasteryTempoRange(minBpm: 60, maxBpm: 100),
  minEvidenceSessions: minEvidenceSessions,
  titleKey: 'chordTransitionBeginnerTitle',
  descriptionKey: 'chordTransitionBeginnerDescription',
);

SkillDetailProjection _projection({
  required MasteryProgress progress,
  MasteryMilestone? milestone,
  List<SkillEvidenceReference> evidence = const [],
  SkillRecommendation? recommendation,
  Set<String> achievedMilestoneIds = const {},
}) => SkillDetailProjection(
  milestone: milestone ?? _milestone(),
  progress: progress,
  title: 'Chord transitions — beginner',
  description: 'Smooth transitions between open chords.',
  evidence: evidence,
  achievedMilestoneIds: achievedMilestoneIds,
  recommendation: recommendation,
);

void main() {
  group('A1 — mastery is derived from measured evidence, never XP', () {
    testWidgets(
      '3 of 5 evidence sessions renders 60%, driven only by evidenceSessionCount',
      (tester) async {
        final milestone = _milestone(minEvidenceSessions: 5);
        final progress = MasteryProgress(
          milestoneId: milestone.id,
          catalogVersion: 1,
          evidenceSessionCount: 3,
        );

        expect(progress.progressValue(milestone), closeTo(0.6, 0.0001));

        await tester.pumpWidget(
          _host(
            SkillDetailScreen(
              projection: _projection(progress: progress, milestone: milestone),
              onOpenEvidence: (_, _) {},
              onStartRecommendedPractice: () {},
            ),
          ),
        );

        expect(find.text('60%'), findsOneWidget);
      },
    );

    testWidgets(
      'a fully-achieved milestone (5 of 5) renders 100%, matching evidenceSessionCount alone',
      (tester) async {
        final milestone = _milestone(minEvidenceSessions: 5);
        final progress = MasteryProgress(
          milestoneId: milestone.id,
          catalogVersion: 1,
          evidenceSessionCount: 5,
        );

        expect(progress.progressValue(milestone), 1.0);

        await tester.pumpWidget(
          _host(
            SkillDetailScreen(
              projection: _projection(progress: progress, milestone: milestone),
              onOpenEvidence: (_, _) {},
              onStartRecommendedPractice: () {},
            ),
          ),
        );

        expect(find.text('100%'), findsOneWidget);
      },
    );
  });

  group('A2 — every mastery claim opens an auditable session', () {
    test('dedupeEvidenceBySession keeps one entry per sessionId, in order', () {
      final evidence = [
        MasteryEvidence(
          sessionId: 'session-1',
          origin: MasteryEvidenceOrigin.vision,
          difficulty: MasteryDifficulty.beginner,
          tempoBpm: 80,
          metricValue: 0.9,
          observedAt: DateTime.utc(2026, 8, 1),
        ),
        MasteryEvidence(
          sessionId: 'session-1',
          origin: MasteryEvidenceOrigin.vision,
          difficulty: MasteryDifficulty.beginner,
          tempoBpm: 82,
          metricValue: 0.95,
          observedAt: DateTime.utc(2026, 8, 2),
        ),
        MasteryEvidence(
          sessionId: 'session-2',
          origin: MasteryEvidenceOrigin.analysis,
          difficulty: MasteryDifficulty.beginner,
          tempoBpm: 84,
          metricValue: 0.85,
          observedAt: DateTime.utc(2026, 8, 3),
        ),
      ];

      final deduped = dedupeEvidenceBySession(evidence);

      expect(deduped, hasLength(2));
      expect(deduped[0].sessionId, 'session-1');
      expect(deduped[0].observedAt, DateTime.utc(2026, 8, 1));
      expect(deduped[1].sessionId, 'session-2');
    });

    testWidgets('tapping an evidence row opens it via the AppRoutes constant', (
      tester,
    ) async {
      String? openedRoute;
      String? openedSessionId;
      final milestone = _milestone();
      final progress = MasteryProgress(
        milestoneId: milestone.id,
        catalogVersion: 1,
        evidenceSessionCount: 2,
      );

      await tester.pumpWidget(
        _host(
          SkillDetailScreen(
            projection: _projection(
              progress: progress,
              milestone: milestone,
              evidence: [
                SkillEvidenceReference(
                  sessionId: 'session-77',
                  origin: MasteryEvidenceOrigin.vision,
                  observedAt: DateTime.utc(2026, 8, 20),
                ),
                SkillEvidenceReference(
                  sessionId: 'session-78',
                  origin: MasteryEvidenceOrigin.analysis,
                  observedAt: DateTime.utc(2026, 8, 21),
                ),
              ],
            ),
            onOpenEvidence: (route, sessionId) {
              openedRoute = route;
              openedSessionId = sessionId;
            },
            onStartRecommendedPractice: () {},
          ),
        ),
      );

      expect(
        find.byKey(const Key('skill-detail-evidence-list')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('event-list-row-session-77')));
      await tester.pumpAndSettle();

      expect(openedRoute, AppRoutes.profileLibrarySession);
      expect(openedSessionId, 'session-77');
    });

    testWidgets(
      'no evidence yet renders an explicit empty state, not a dead link',
      (tester) async {
        final milestone = _milestone();
        final progress = MasteryProgress.fresh(
          milestoneId: milestone.id,
          catalogVersion: 1,
        );

        await tester.pumpWidget(
          _host(
            SkillDetailScreen(
              projection: _projection(progress: progress, milestone: milestone),
              onOpenEvidence: (_, _) {},
              onStartRecommendedPractice: () {},
            ),
          ),
        );

        expect(
          find.byKey(const Key('skill-detail-no-evidence')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('skill-detail-evidence-list')),
          findsNothing,
        );
      },
    );
  });

  group('A7 — a recommendation never ignores an unmet prerequisite', () {
    test('isRecommendationEligible rejects an unmet prerequisite', () {
      const recommendation = SkillRecommendation(
        milestoneId: 'strum_consistency_intermediate',
        title: 'Strum consistency — intermediate',
        message: 'Ready for a faster tempo drill.',
        prerequisiteMilestoneId: 'chord_transition_beginner',
        prerequisiteTitle: 'Chord transitions — beginner',
      );

      expect(isRecommendationEligible(recommendation, const {}), isFalse);
      expect(
        isRecommendationEligible(recommendation, const {
          'chord_transition_beginner',
        }),
        isTrue,
      );
    });

    test('a recommendation with no prerequisite is always eligible', () {
      const recommendation = SkillRecommendation(
        milestoneId: 'chord_transition_beginner',
        title: 'Chord transitions — beginner',
        message: 'Keep the streak going.',
      );

      expect(isRecommendationEligible(recommendation, const {}), isTrue);
    });

    testWidgets(
      'an unmet prerequisite locks the recommendation instead of offering it',
      (tester) async {
        final milestone = _milestone();
        final progress = MasteryProgress(
          milestoneId: milestone.id,
          catalogVersion: 1,
          evidenceSessionCount: 1,
        );

        await tester.pumpWidget(
          _host(
            SkillDetailScreen(
              projection: _projection(
                progress: progress,
                milestone: milestone,
                recommendation: const SkillRecommendation(
                  milestoneId: 'strum_consistency_intermediate',
                  title: 'Strum consistency — intermediate',
                  message: 'Ready for a faster tempo drill.',
                  prerequisiteMilestoneId: 'chord_transition_beginner',
                  prerequisiteTitle: 'Chord transitions — beginner',
                ),
                achievedMilestoneIds: const {},
              ),
              onOpenEvidence: (_, _) {},
              onStartRecommendedPractice: () {},
            ),
          ),
        );

        expect(
          find.byKey(const Key('skill-detail-recommendation-locked')),
          findsOneWidget,
        );
        expect(
          find.text('Requires Chord transitions — beginner first'),
          findsOneWidget,
        );
        expect(find.text('Start practice'), findsNothing);
      },
    );

    testWidgets('a met prerequisite offers the recommendation as an action', (
      tester,
    ) async {
      var started = false;
      final milestone = _milestone();
      final progress = MasteryProgress(
        milestoneId: milestone.id,
        catalogVersion: 1,
        evidenceSessionCount: 5,
      );

      await tester.pumpWidget(
        _host(
          SkillDetailScreen(
            projection: _projection(
              progress: progress,
              milestone: milestone,
              recommendation: const SkillRecommendation(
                milestoneId: 'strum_consistency_intermediate',
                title: 'Strum consistency — intermediate',
                message: 'Ready for a faster tempo drill.',
                prerequisiteMilestoneId: 'chord_transition_beginner',
                prerequisiteTitle: 'Chord transitions — beginner',
              ),
              achievedMilestoneIds: const {'chord_transition_beginner'},
            ),
            onOpenEvidence: (_, _) {},
            onStartRecommendedPractice: () => started = true,
          ),
        ),
      );

      expect(
        find.byKey(const Key('skill-detail-recommendation-locked')),
        findsNothing,
      );
      expect(find.text('Start practice'), findsOneWidget);

      await tester.tap(find.text('Start practice'));
      await tester.pumpAndSettle();

      expect(started, isTrue);
    });
  });
}
